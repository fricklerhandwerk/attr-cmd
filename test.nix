{ sources ? import ./npins
, system ? builtins.currentSystem
,
}:
let
  pkgs = import sources.nixpkgs {
    inherit system;
    config = { };
    overlays = [ ];
  };

  inherit (pkgs.callPackage ./lib.nix { }) attr-cmd;
in
rec {
  shell = pkgs.mkShellNoCC {
    packages = builtins.attrValues commands ++ [
      pkgs.npins
    ];
  };

  commands = attr-cmd {
    foo.bar.baz = pkgs.writeScriptBin "baz" "echo success $@";
    foo.bam = pkgs.writeScriptBin "bam" "echo bam";
    foo.qux.zip = pkgs.writeScriptBin "zip" "echo shh";
    foo.qux.meta.description = "additional quxings";
    foo.qux.greet = pkgs.hello;
    nope = "nope";
  };
}
