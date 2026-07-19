{
  description = "DMS Greeter";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    dank-qml-common = {
      url = "github:AvengeMedia/dank-qml-common";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, dank-qml-common, ... }:
    let
      goModVersion =
        let
          content = builtins.readFile ./core/go.mod;
          lines = builtins.filter builtins.isString (builtins.split "\n" content);
          goLines = builtins.filter (l: builtins.match "go [0-9]+\\..*" l != null) lines;
          matched =
            if goLines != [ ] then builtins.match "go ([0-9]+)\\.([0-9]+).*" (builtins.head goLines) else null;
        in
        if matched != null then
          {
            major = builtins.elemAt matched 0;
            minor = builtins.elemAt matched 1;
          }
        else
          {
            major = "1";
            minor = "26";
          };
      goForPkgs = pkgs: pkgs.${"go_${goModVersion.major}_${goModVersion.minor}"};

      forEachSystem =
        fn:
        nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
          system: fn system nixpkgs.legacyPackages.${system}
        );

      mkModuleWithGreeterPkgs =
        modulePath:
        args@{ pkgs, ... }:
        {
          imports = [
            (import modulePath (args // { greeterPkgs = buildGreeterPkgs pkgs; }))
          ];
        };

      mkDmsGreeter =
        pkgs:
        (
          let
            version = "0.1.0";
          in
          (pkgs.buildGoModule.override { go = goForPkgs pkgs; }) {
            inherit version;
            pname = "dms-greeter";
            src = ./.;
            modRoot = "core";
            vendorHash = pkgs.lib.fakeHash;

            subPackages = [ "cmd/dms-greeter" ];

            tags = [ "withshell" ];

            # Mirror `make -C core sync-shell`: bake the quickshell UI into
            # the binary, minus dev-only files. The flake src excludes
            # submodule content, so the DankCommon symlink is replaced with
            # the pinned dank-qml-common input.
            postPatch = ''
              rm -rf core/internal/shellembed/dist
              cp -r quickshell core/internal/shellembed/dist
              rm -f core/internal/shellembed/dist/DankCommon
              cp -r ${dank-qml-common}/DankCommon core/internal/shellembed/dist/DankCommon
              chmod -R u+w core/internal/shellembed/dist/DankCommon
              rm -rf core/internal/shellembed/dist/scripts \
                core/internal/shellembed/dist/.claude
              rm -f core/internal/shellembed/dist/.qmlls.ini \
                core/internal/shellembed/dist/translations/extract_translations.py
            '';

            ldflags = [
              "-s"
              "-w"
              "-X main.Version=${version}"
              "-X main.Commit=${self.shortRev or self.dirtyShortRev or "dirty"}"
            ];

            nativeBuildInputs = with pkgs; [
              installShellFiles
            ];

            postInstall = ''
              installShellCompletion --cmd dms-greeter \
                --bash <($out/bin/dms-greeter completion bash) \
                --fish <($out/bin/dms-greeter completion fish) \
                --zsh <($out/bin/dms-greeter completion zsh)
            '';

            meta = {
              description = "greetd login screen with the Dank Material aesthetic";
              homepage = "https://github.com/AvengeMedia/dank-greeter";
              license = pkgs.lib.licenses.mit;
              mainProgram = "dms-greeter";
              platforms = pkgs.lib.platforms.linux;
            };
          }
        );

      buildGreeterPkgs = pkgs: {
        dms-greeter = mkDmsGreeter pkgs;
      };
    in
    {
      packages = forEachSystem (
        system: pkgs: {
          dms-greeter = mkDmsGreeter pkgs;
          default = self.packages.${system}.dms-greeter;
        }
      );

      lib = { inherit mkDmsGreeter buildGreeterPkgs; };

      nixosModules.dank-greeter = mkModuleWithGreeterPkgs ./distro/nix/greeter.nix;

      nixosModules.default = self.nixosModules.dank-greeter;

      devShells = forEachSystem (
        system: pkgs: {
          default = pkgs.mkShell {
            GOTOOLCHAIN = "auto";

            buildInputs = with pkgs; [
              (goForPkgs pkgs)
              gopls
              delve
              go-tools
              gnumake

              quickshell

              prek
              uv
              python3

              nixd
              nil
            ];

            shellHook = ''
              touch quickshell/.qmlls.ini 2>/dev/null
              if [ ! -f .git/hooks/pre-commit ]; then prek install; fi
            '';
          };
        }
      );

      nixosTests = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (
        system:
        import ./distro/nix/tests {
          inherit self;
          pkgs = nixpkgs.legacyPackages.${system};
        }
      );
    };
}
