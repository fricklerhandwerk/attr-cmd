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
    with pkgs.lib;
    let
      subcommand = prefix: name: value:
        if isDerivation value then ''exec ${getExe' value (value.meta.mainProgram or name)} "$@"''
        else if isAttrs value
        then
          let
            case = name: value: ''
              "${name}")
                shift
                ${indent "  " (lines (subcommand (prefix ++ [name]) name value))}
                ;;'';
          in
          ''
            if [ $# -eq 0 ]; then
              ${indent "  " (mapLines (x: "echo \"${x}\"") (available prefix value))}
              exit 1
            fi
            case "$1" in
              ${indent "  " (map (block: indent "  " (lines block)) (mapAttrsToList case value))}
              *)
                echo "Error: Invalid subcommand '$1'"
                ${indent "    " (mapLines (x: "echo \"${x}\"") (available prefix value))}
                exit 1
                ;;
            esac''
        else
          throw "attr-cmd: '${join "." prefix}' must be a derivation or an attribute set, but its type is '${builtins.typeOf value}'";

      available = prefix: value:
        let
          attrpaths =
            let
              # collect linear attribute paths.
              # that is, stop either at derivations, or when an attribute set has more than one entry.
              recurse = prefix: attrs:
                concatLists (mapAttrsToList
                  (name: value:
                    if isDerivation value then [ (prefix ++ [ name ]) ]
                    else if isAttrs value then
                      if length (attrNames value) > 1 then [ (prefix ++ [ name ]) ]
                      else recurse (prefix ++ [ name ]) value
                    else [ ]
                  )
                  attrs);
            in
            recurse [ ];
        in
        ''
          Usage: ${join " " prefix} [subcommand]... [argument]...

          Available subcommands:
            ${indent "  " (map (join " ") (attrpaths value))}'';

      join = concatStringsSep;
      indent = prefix: join "\n${prefix}";
      lines = splitString "\n";
      mapLines = f: text: map f (lines text);

      command = name: value:
        pkgs.writeShellApplication { inherit name; text = (subcommand [ name ] name value); };

    in
    pkgs.lib.mapAttrs command attrs;

  shell = pkgs.mkShellNoCC {
    packages = builtins.attrValues commands ++ [
      pkgs.npins
    ];
  };

  commands = attr-cmd { inherit foo; };

  foo.bar.baz = pkgs.writeScriptBin "baz" "echo success $@";
  foo.bam = pkgs.writeScriptBin "bam" "echo bam";
  foo.qux.qum = pkgs.writeScriptBin "qum" "echo failure";
  foo.qux.zut = pkgs.writeScriptBin "zut" "echo shh";
}
