{
  self,
  pkgs,
  ...
}:
rec {
  all = pkgs.symlinkJoin {
    name = "dms-greeter-nixos-tests";
    paths = [
      greeter-niri-module
    ];
  };

  greeter-niri-module = import ./greeter-niri-module.nix { inherit self pkgs; };
}
