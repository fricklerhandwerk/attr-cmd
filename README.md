# `attr-cmd`
Build shell commands from Nix attribute sets.

## `lib.attr-cmd.exec`

    exec :: AttrSet -> AttrSet

`exec` transforms a nested attribute set `<input>` into a flat attribute set `<output>`.
For each attribute `<attr>` of `<input>` at the [attribute path](https://nix.dev/manual/nix/stable/language/operators.html#attribute-selection) `<root> . [...] . <attr>` that evaluates to a [derivation](https://nix.dev/manual/nix/stable/language/derivations), it creates an attribute `<root>` in `<output>`.
All other attribute paths are ignored.

> **Example**
>
> ### Transformation of attributes
>
> ```nix
> { lib, attr-cmd }:
> let
>   input = {
>     a.b.c = drv;
>     d.e.f = drv';
>     g.h.i = "ignored";
>   };
>   output = attr-cmd.exec input;
> in
> {
>   inherit = output;
>   executable = lib.getExe output.a;
> }
> ```
>
> ```console
> { output = { a = drv''; d = drv'''; }; executable = "/nix/store/...-a/bin/a"}
> ```
>

Each attribute `<root>` in `<output>` is a derivation that produces an executable `/bin/<root>`.
Such an executable `<root>` accepts [command line words](https://www.gnu.org/software/bash/manual/bash.html#index-word) that correspond to attribute paths in `<attrs-in>` starting from `<root>`.
The final command line word `<attr>` executes the `meta.mainProgram` (or `/bin/<attr>`) from the derivation's `bin` (or `out`) [output](https://nix.dev/manual/nix/stable/language/derivations#attr-outputs) at the corresponding attribute `<attr>` from `<input>`.

After adding the derivations from `<output>` to the environment, run the executable `<attr>` by specifying its attribute path as command line arguments:

```console
<root> ... <attr> [<arguments>]...
```

Help will be shown for intermediate subcommands, displaying `meta.description` on a derivation or attribute set if available.

> **Example**
>
> ### Create a command from a derivation in an attribute set
>
> Declare a nested attribute set `foo` with a derivation `baz` as a leaf attribute, and pass that attribute set to `attr-cmd`:
>
> ```nix
> # ./default.nix
> {
>   sources ? import ./npins,
>   system ? builtins.currentSystem,
>   pkgs ? import sources.nixpkgs { inherit system; config = { }; overlays = [ ]; },
>   attr-cmd ? pkgs.callPackage "${sources.attr-cmd}/lib.nix" {};
> }:
> let
>   lib = pkgs.lib // attr-cmd.lib
> lib
> rec {
>   foo.bar.baz = pkgs.writeScriptBin "baz" "echo success $@";
>   commands = lib.attr-cmd.exec { inherit foo; }; ;
>   shell = pkgs.mkShellNoCC {
>     packages = builtins.attrValues commands ++ [
>       pkgs.npins
>     ];
>   };
> }
> ```
>
> The values of the resulting attribute set `commands` are now derivations that create executables:
>
> ```shell-session
> $ nix-shell -p npins --run "npins init"
> $ nix-shell
> [nix-shell:~]$ foo bar baz
> success
> [nix-shell:~]$ foo bar baz or else
> success or else
> ```
>



