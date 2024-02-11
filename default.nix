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
            valid = value: attrsets.filterAttrs (_: v: isAttrs v) value;
          in
          ''
            if [ $# -eq 0 ]; then
              ${indent "  " (mapLines (x: "echo \"${x}\"") (available prefix (valid value)))}
              exit 1
            fi
            case "$1" in
              ${indent "  " (map (block: indent "  " (lines block)) (mapAttrsToList case (valid value)))}
              *)
                echo "Error: Invalid subcommand '$1'"
                ${indent "    " (mapLines (x: "echo \"${x}\"") (available prefix (valid value)))}
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
                    if isDerivation value then [ (prefix ++ [{ inherit name value; }]) ]
                    else if isAttrs value then
                      if length (attrNames value) > 1 then [ (prefix ++ [{ inherit name value; }]) ]
                      else recurse (prefix ++ [{ inherit name value; }]) value
                    else [ ]
                  )
                  attrs);
            in
            recurse [ ];
          info-lines =
            # a lot of effort to avoid trailing spaces
            let
              cmd = path: join " " (attrNames (listToAttrs path));
              cmds = map cmd (attrpaths value);
              info = path: (lists.last (attrValues (listToAttrs path))).meta.description or "";
              infos = map info (attrpaths value);
              pad = strings:
                let
                  longest = foldl' (acc: elem: if elem > acc then elem else acc) 0 (map stringLength strings);
                  fill = string: string + join "" (genList (x: " ") (longest - (stringLength string)));
                in
                map fill strings;
              padded = lists.imap0 (i: x: if elemAt infos i == "" then elemAt cmds i else x) (pad cmds);
            in
            zipListsWith (path: info: if info == "" then path else "${path} - ${info}") padded infos;
        in
        ''
          Usage: ${join " " prefix} [subcommand]... [argument]...

          Available subcommands:
            ${indent "  " info-lines}'';

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
  foo.qux.zip = pkgs.writeScriptBin "zip" "echo shh";
  foo.qux.meta.description = "additional quxings";
  foo.qux.greet = pkgs.hello;
}
