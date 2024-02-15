{ lib, writeShellApplication }:
rec {
  attr-cmd = attrs:
    let
      valid = value:
        with lib;
        attrsets.filterAttrs (_: anyLeaf isDerivation) value;
      subcommand = prefix: name: value:
        with lib;
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
            if [ $# -ne 0 ]; then
              case "$1" in
                ${indent "  " (map (block: indent "  " (lines block)) (mapAttrsToList case (valid value)))}
                *)
                  echo "Error: Invalid subcommand '$1'" >&2
                  ;;
              esac
            fi
            ${join "\n" (mapLines (x: "echo \"${x}\" >&2") (available (prefix ++ [name]) (valid value)))}
            exit 1''
        else
          throw "attr-cmd: '${join "." prefix}' must be a derivation or an attribute set, but its type is '${builtins.typeOf value}'";

      available = prefix: value:
        let
          attrpaths =
            let
              # collect linear attribute paths.
              # that is, stop either at derivations, or when an attribute set has more than one entry.
              recurse = prefix: attrs:
                with lib;
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
            with lib;
            # a lot of effort to avoid trailing spaces
            let
              cmd = path: join " " (attrNames (listToAttrs path));
              cmds = map cmd (attrpaths value);
              info = path: (lists.last (attrValues (listToAttrs path))).meta.description or "";
              infos = map info (attrpaths value);
              pad = strings:
                let
                  longest = max (map stringLength strings);
                  fill = string: string + join "" (genList (x: " ") (longest - (stringLength string)));
                in
                map fill strings;
              padIf = pred: strings:
                lists.imap0 (i: x: if (pred i x) then x else elemAt strings i) (pad strings);
              has-info = i: _: (elemAt infos i) != "";
            in
            zipListsWith
              (path: info: if info == "" then path else "${path} - ${info}")
              (padIf has-info cmds)
              infos;
        in
        ''
          Usage: ${join " " prefix} [subcommand]... [argument]...

          Available subcommands:
            ${indent "  " info-lines}'';

      command = name: value:
        writeShellApplication { inherit name; text = subcommand [ ] name value; };
    in
    lib.mapAttrs command (valid attrs);

  join = lib.concatStringsSep;
  indent = prefix: join "\n${prefix}";
  lines = lib.splitString "\n";
  mapLines = f: text: map f (lines text);
  max = lib.foldl' (acc: elem: if elem > acc then elem else acc) 0;
  anyLeaf = predicate: value:
    with lib;
    predicate value || isAttrs value && any (anyLeaf predicate) (attrValues value);
}
