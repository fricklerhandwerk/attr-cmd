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
      subcommand = name: value:
        with pkgs.lib;
        if isDerivation value then ''exec ${value}/bin/${name} "$@"''
        else if isAttrs value
        then
          let
            cases = name: attr: ''
              ${name})
                shift
                ${concatStringsSep "\n  " (splitString "\n" (subcommand name attr))}
                ;;'';
          in
          ''
            if [ $# -eq 0 ]; then
              echo "Available subcommands:"
              ${concatStringsSep "\n  " (map (x: "echo '  ${x}'") (attrNames value))}
              exit 1
            fi
            case "$1" in
              ${concatStringsSep "\n  " (map (block: concatStringsSep "\n  " (splitString "\n" block)) (mapAttrsToList cases value))}
              *)
                echo "Subcommand '$1' not available. Available subcommands:"
                ${concatStringsSep "\n    " (map (x: "echo '  ${x}'") (attrNames value))}
                exit 1
                ;;
            esac''
        else
          throw "attribute '${name}' must be a derivation or an attribute set";
      command = name: value:
        pkgs.writeShellApplication { inherit name; text = (subcommand name value); };
    in
    pkgs.lib.mapAttrs command attrs;
  shell = pkgs.mkShellNoCC {
    packages = builtins.attrValues commands ++ [
      pkgs.npins
    ];
  };
  commands = attr-cmd { inherit foo; };
  foo.bar.baz = pkgs.writeScriptBin "baz" "echo success $@";
  foo.qux.qum = pkgs.writeScriptBin "qum" "echo failure";
}
