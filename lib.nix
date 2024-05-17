/**
  Build shell commands from Nix attribute sets.
*/
{ lib, writeShellApplication }:
rec {
  /**
    ```
    exec :: AttrSet -> AttrSet
    ```

    `exec` transforms a nested attribute set `<input>` into a flat attribute set `<output>`.
    For each attribute `<attr>` of `<input>` at the [attribute path](https://nix.dev/manual/nix/stable/language/operators.html#attribute-selection) `<root> . [...] . <attr>` that evaluates to a [derivation](https://nix.dev/manual/nix/stable/language/derivations), it creates an attribute `<root>` in `<output>`.
    All other attribute paths are ignored.

    :::{.example}
    # Transformation of attributes

    ```nix
    { lib, attr-cmd }:
    let
      input = {
        a.b.c = drv;
        d.e.f = drv';
        g.h.i = "ignored";
      };
      output = attr-cmd.exec input;
    in
    {
      inherit = output;
      executable = lib.getExe output.a;
    }
    ```

    ```console
    { output = { a = drv''; d = drv'''; }; executable = "/nix/store/...-a/bin/a"}
    ```
    :::

    Each attribute `<root>` in `<output>` is a derivation that produces an executable `/bin/<root>`.
    Such an executable `<root>` accepts [command line words](https://www.gnu.org/software/bash/manual/bash.html#index-word) that correspond to attribute paths in `<attrs-in>` starting from `<root>`.
    The final command line word `<attr>` executes the `meta.mainProgram` (or `/bin/<attr>`) from the derivation's `bin` (or `out`) [output](https://nix.dev/manual/nix/stable/language/derivations#attr-outputs) at the corresponding attribute `<attr>` from `<input>`.

    After adding the derivations from `<output>` to the environment, run the executable `<attr>` by specifying its attribute path as command line arguments:

    ```console
    <root> ... <attr> [<arguments>]...
    ```

    Help will be shown for intermediate subcommands, displaying `meta.description` on a derivation or attribute set if available.

    :::{.example}
    # Create a command from a derivation in an attribute set

    Declare a nested attribute set `foo` with a derivation `baz` as a leaf attribute, and pass that attribute set to `attr-cmd`:

    ```nix
    # ./default.nix
    {
      sources ? import ./npins,
      system ? builtins.currentSystem,
      pkgs ? import sources.nixpkgs { inherit system; config = { }; overlays = [ ]; },
      attr-cmd ? pkgs.callPackage "${sources.attr-cmd}/lib.nix" {};
    }:
    let
      lib = pkgs.lib // attr-cmd.lib
    lib
    rec {
      foo.bar.baz = pkgs.writeScriptBin "baz" "echo success $@";
      commands = lib.attr-cmd.exec { inherit foo; }; ;
      shell = pkgs.mkShellNoCC {
        packages = builtins.attrValues commands ++ [
          pkgs.npins
        ];
      };
    }
    ```

    The values of the resulting attribute set `commands` are now derivations that create executables:

    ```shell-session
    $ nix-shell -p npins --run "npins init"
    $ nix-shell
    [nix-shell:~]$ foo bar baz
    success
    [nix-shell:~]$ foo bar baz or else
    success or else
    ```
    :::
  */
  exec = attrs:
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
