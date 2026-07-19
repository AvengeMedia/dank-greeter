{
  lib,
  config,
  pkgs,
  greeterPkgs,
  ...
}:
let
  inherit (lib) types;
  cfg = config.programs.dms-greeter;
  cfgAutoLogin = config.services.displayManager.autoLogin;
  sessionData = config.services.displayManager.sessionData;

  inherit (config.services.greetd.settings.default_session) user;

  compositorPackage =
    let
      configured = lib.attrByPath [ "programs" cfg.compositor.name "package" ] null config;
    in
    if configured != null then configured else builtins.getAttr cfg.compositor.name pkgs;

  cacheDir = "/var/lib/dms-greeter";
  greeterCommand = pkgs.writeShellScriptBin "dms-greeter-session" ''
    export PATH=$PATH:${
      lib.makeBinPath [
        cfg.quickshell.package
        compositorPackage
        pkgs.glib # provides gdbus, used by the fprintd hardware probe and portal reads
      ]
    }
    ${
      lib.escapeShellArgs (
        [
          "${cfg.package}/bin/dms-greeter"
          "--cache-dir"
          cacheDir
          "--command"
          cfg.compositor.name
        ]
        ++ lib.optionals (cfg.compositor.customConfig != "") [
          "-C"
          "${pkgs.writeText "dms-greeter-compositor-config" cfg.compositor.customConfig}"
        ]
        ++ lib.optionals cfg.logs.save [ "--debug" ]
      )
    } ${lib.optionalString cfg.logs.save "> ${cfg.logs.path} 2>&1"}
  '';

  autoLoginCommand =
    pkgs.runCommand "dms-greeter-autologin-command"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.coreutils
        ];
      }
      ''
        set -euo pipefail

        session="${sessionData.autologinSession}"
        desktops="${sessionData.desktops}"

        for sessionFile in \
          "$desktops/share/wayland-sessions/$session.desktop" \
          "$desktops/share/xsessions/$session.desktop"
        do
          if [ -f "$sessionFile" ]; then
            command="$(grep -m1 '^Exec=' "$sessionFile" | cut -d= -f2- || true)"

            if [ -n "$command" ]; then
              printf '%s\n' "$command" > "$out"
              exit 0
            fi
          fi
        done

        echo "dms-greeter autologin: could not resolve Exec for session '$session'" >&2
        exit 1
      '';

  jq = lib.getExe pkgs.jq;
in
{
  options.programs.dms-greeter = {
    enable = lib.mkEnableOption "DMS Greeter";
    package = lib.mkOption {
      type = types.package;
      default = greeterPkgs.dms-greeter;
      defaultText = lib.literalExpression "built from source";
      description = "The dms-greeter package to use.";
    };
    compositor.name = lib.mkOption {
      type = types.enum [
        "niri"
        "hyprland"
        "sway"
        "labwc"
        "mango"
        "scroll"
        "miracle"
      ];
      description = "Compositor to run the greeter in";
    };
    compositor.customConfig = lib.mkOption {
      type = types.lines;
      default = "";
      description = "Custom compositor config";
    };
    configFiles = lib.mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = "Config files to copy into the greeter data directory";
      example = [
        "/home/user/.config/DankMaterialShell/settings.json"
      ];
    };
    configHome = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/user";
      description = ''
        User home directory to copy DankMaterialShell configurations from.
        If DMS config files are in non-standard locations use configFiles instead.
      '';
    };
    quickshell = {
      package = lib.mkOption {
        type = types.package;
        default = pkgs.quickshell;
        defaultText = lib.literalExpression "pkgs.quickshell";
        description = "The quickshell package to use (at least 0.3.0 recommended).";
      };
    };
    logs.save = lib.mkEnableOption "saving dms-greeter logs to a file";
    logs.path = lib.mkOption {
      type = types.path;
      default = "/tmp/dms-greeter.log";
      description = "File path to save dms-greeter logs to";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (config.users.users.${user} or { }) != { };
        message = ''
          dms-greeter: user set for greetd default_session ${user} does not exist. Please create it before referencing it.
        '';
      }
      {
        assertion = cfgAutoLogin.enable -> sessionData.autologinSession != null;
        message = ''
          dms-greeter auto-login requires services.displayManager.defaultSession to be set,
          or at least one session in services.displayManager.sessionPackages.
        '';
      }
    ];
    services.greetd = {
      enable = lib.mkDefault true;
      settings = {
        default_session.command = lib.mkDefault (lib.getExe greeterCommand);
        initial_session = lib.mkIf (cfgAutoLogin.enable && (cfgAutoLogin.user != null)) {
          inherit (cfgAutoLogin) user;
          command = ''${lib.getExe pkgs.bash} -lc "${pkgs.systemd}/bin/systemd-cat $(<${autoLoginCommand})"'';
        };
      };
    };
    fonts.packages = with pkgs; [
      fira-code
      inter
      material-symbols
    ];
    systemd.tmpfiles.settings."10-dms-greeter" = {
      ${cacheDir}.d = {
        inherit user;
        group =
          if config.users.users.${user}.group != "" then config.users.users.${user}.group else "greeter";
        mode = "0750";
      };
    };
    systemd.services.greetd.preStart = ''
      cd ${cacheDir}
      ${lib.concatStringsSep "\n" (
        lib.map (f: ''
          if [ -f "${f}" ]; then
              cp "${f}" .
          fi
        '') cfg.configFiles
      )}

      if [ -f session.json ]; then
          copy_wallpaper() {
              local path=$(${jq} -r ".$1 // empty" session.json)
              if [ -f "$path" ]; then
                  cp "$path" "$2"
                  ${jq} ".$1 = \"${cacheDir}/$2\"" session.json > session.tmp
                  mv session.tmp session.json
              fi
          }

          copy_monitor_wallpapers() {
              ${jq} -r ".$1 // {} | to_entries[] | .key + \":\" + .value" session.json 2>/dev/null | while IFS=: read monitor path; do
                  local dest="$2-$(echo "$monitor" | tr -c '[:alnum:]' '-')"
                  if [ -f "$path" ]; then
                      cp "$path" "$dest"
                      ${jq} --arg m "$monitor" --arg p "${cacheDir}/$dest" ".$1[\$m] = \$p" session.json > session.tmp
                      mv session.tmp session.json
                  fi
              done
          }

          copy_wallpaper "wallpaperPath" "wallpaper"
          copy_wallpaper "wallpaperPathLight" "wallpaper-light"
          copy_wallpaper "wallpaperPathDark" "wallpaper-dark"
          copy_monitor_wallpapers "monitorWallpapers" "wallpaper-monitor"
          copy_monitor_wallpapers "monitorWallpapersLight" "wallpaper-monitor-light"
          copy_monitor_wallpapers "monitorWallpapersDark" "wallpaper-monitor-dark"
      fi

      if [ -f settings.json ]; then
          theme_file="$(${jq} -r '.customThemeFile // empty' settings.json)"
          if [ -f "$theme_file" ] && [ -r "$theme_file" ]; then
              cp "$theme_file" custom-theme.json
              mv settings.json settings.orig.json
              ${jq} '.customThemeFile = "${cacheDir}/custom-theme.json"' settings.orig.json > settings.json
          fi
      fi

      mv dms-colors.json colors.json || :
      chown ${user}: * || :
    '';
    programs.dms-greeter.configFiles = lib.mkIf (cfg.configHome != null) [
      "${cfg.configHome}/.config/DankMaterialShell/settings.json"
      "${cfg.configHome}/.local/state/DankMaterialShell/session.json"
      "${cfg.configHome}/.cache/DankMaterialShell/dms-colors.json"
    ];
  };
}
