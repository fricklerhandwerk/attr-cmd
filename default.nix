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
in
rec {
  attr-cmd = attrs:
    let
      command = name: inner:
        with pkgs.lib;
        if isDerivation inner then pkgs.writeScriptBin name ''${inner}/bin/${name} "$@"''
        else if isAttrs inner
        then
          let
            cases = name: attr: ''
              ${name})
                shift
                exec ${command name attr}/bin/${name} "$@"
                ;;
            '';
            echo-indented = depth: strings:
              let
                indent = concatStrings (builtins.genList (x: " ") depth);
              in
              ''${concatStringsSep "\n" (map (x: "echo '${indent}${x}'") strings)}'';
          in
          pkgs.writeShellApplication
            {
              inherit name;
              text = ''
                if [ $# -eq 0 ]; then
                  echo "Available subcommands:"
                  ${echo-indented 2 (attrNames inner)}
                  exit 1
                fi
                case "$1" in
                  ${concatStringsSep "\n" (mapAttrsToList cases inner)}
                  *)
                    echo "Subcommand '$1' not available. Available subcommands:"
                    ${echo-indented 2 (attrNames inner)}
                    exit 1
                    ;;
                esac
              '';
            }
        else
          throw "attribute '${name}' must be a derivation or an attribute set";
    in
    pkgs.lib.mapAttrs command attrs;
  shell = pkgs.mkShellNoCC {
    packages = builtins.attrValues commands ++ [
      pkgs.npins
    ];
  };
  commands = attr-cmd { inherit foo; };
  foo.bar.baz = pkgs.writeScriptBin "baz" "echo success $@";
}
