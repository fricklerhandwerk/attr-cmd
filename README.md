# `attr-cmd`

Build shell commands from Nix attribute sets.

## Usage

`attr-cmd` takes an as argument an attribute set with the following attributes:

- `path` (Path)

  Directory of the `default.nix` Nix file containing the attributes that are passed as `attrs`.

  Nix expressions in this directory must be pure.
  In particular, they must refer only to sub-paths of the directory.
  If the target directory is large, consider filtering only relevant files with the [fileset library](https://nixos.org/manual/nixpkgs/unstable/#sec-functions-library-fileset).

- `attrs` (Attribute Set)

  Attributes to convert to commands.
  Each leaf attribute `<leaf>` should evaluate to a [derivation](https://nix.dev/manual/nix/2.19/language/derivations) that has `/bin/<leaf>` in its default [output](https://nix.dev/manual/nix/2.19/language/derivations#attr-outputs).

It returns an attribute set of derivations, where each deriviation produces `/bin/<root>` for a root attribute `<root>` in `attrs`.

Then you can run the executable in each `<leaf>` by specifying its attribute path as command line arguments:

```console
<root> ... <leaf> [-- <arguments>]
```

## Example

```nix
# ./default.nix
{
  sources ? import ./npins,
  system ? builtins.currentSystem,
}:
let
  pkgs = import sources.nixpkgs {
    inherit system;
    config = { };
    overlays = [ ];
  };
  inherit (import sources.attr-cmd { inherit sources system; }) attr-cmd;
in
rec {
  foo.bar.baz = pkgs.writeScriptBin "baz" "echo success";
  commands = attr-cmd { path = ./.; attrs = { inherit foo; }; };
  shell = pkgs.mkShellNoCC {
    packages = builtins.attrValues commands ++ [
      pkgs.npins
    ];
  };
}
```

```console
$ nix-shell -p npins --run "npins init"
$ nix-shell
[nix-shell:~]$ foo bar baz
success
```

## Development

For a smoke test, run:

```console
$ nix-shell --run "foo bar baz"
success
```

Passing arguments also works:

```console
$ nix-shell --run "foo bar baz -- and other stuff"
success and other stuff
```

Actual tests would be great.

The script itself can be made configurable to death with extra attributes in its argument.
For instance, currently it uses the ambient `nix-build` without parameters.

There is also no error handling whatsoever.
The given attribute path has to exist and evaluate to a derivation.
A more sophisticated approach would be testing the passed attributes for validity.
For example, if the given attribute path exists but does not evaluate to a derivation one could print an error message that suggests other attributes.

All of this would get a lot easier with [Python bindings to the Nix language evaluator](https://github.com/tweag/python-nix).

## Motivation

I kept running into a scalability problem with the following pattern:

Assume we have a `default.nix` that specifies various NixOS configurations as attributes:

```nix
# ./default.nix
{
  sources ? import ./npins,
  system ? builtins.currentSystem,
}:
let
  pkgs = import sources.nixpkgs {
    config = { };
    overlays = [ ];
    system = builtins.currentSystem;
  };
in
{
  machines = mapAttrs (name: config: pkgs.nixos [ config ]) {
    foo = ./machines/foo.nix;
    bar = ./machines/bar.nix;
    # ...
  };
  shell = pkgs.mkShellNoCC {
    packages = [
      pkgs.npins
    ];
  };
}
```

We may now want to add some convenience commands to the shell environment.
For example, to run a given configuration in a virtual machine:

```diff
+  run-vm = pkgs.writeShellApplication {
+    name = "run-vm";
+    text = ''
+      machine="$1"
+      shift
+      # make QEMU create the disk image in memory
+      cd "$(mktemp -d)"
+      # always clean up
+      trap 'rm -f nixos.qcow2' EXIT
+      "$(nix-build ${./.} -A machines."$machine".config.system.build.vm --no-out-link)"/bin/run-nixos-vm "$@"
+    '';
+  };
 in
 {
   machines = mapAttrs (name: config: pkgs.nixos [ config ]) {
     foo = ./machines/foo.nix;
     bar = ./machines/bar.nix;
     # ...
   };
   shell = pkgs.mkShellNoCC {
     packages = [
       pkgs.npins
+      run-vm
     ];
   };
 }
```

This is neat!
All you need is to enter the shell and run:

```console
run-vm foo
```

But what if we wanted to add more such commands, for example to build an ISO image from the shell?
It would require refactoring the Nix expression substantially to accommodate:

```nix
# ./default.nix
{
  sources ? import ./npins,
  system ? builtins.currentSystem,
}:
let
  pkgs = import sources.nixpkgs {
    config = { };
    overlays = [ ];
    system = builtins.currentSystem;
  };
  run-vm = pkgs.writeShellApplication {
    name = "run-vm";
    text = ''
      machine="$1"
      shift
      # make QEMU create the disk image in memory
      cd "$(mktemp -d)"
      # always clean up
      trap 'rm -f nixos.qcow2' EXIT
      "$(nix-build ${./.} -A machines."$machine".config.system.build.vm --no-out-link)"/bin/run-nixos-vm "$@"
    '';
  };
  iso = config: pkgs.nixos [{
    imports = [
      config
      "${sources.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    ];
    virtualisation.memorySize = 2048; # GiB
  }];
  make-iso = pkgs.writeShellApplication {
    name = "make-iso";
    text = ''
      machine="$1"
      shift
      nix-build ${./.} -A installers."$machine".config.system.build.isoImage --no-out-link "$@"
    '';
  };
in
rec {
  configurations = {
    foo = ./machines/foo.nix;
    bar = ./machines/bar.nix;
    # ...
  };
  machines = mapAttrs (name: config: pkgs.nixos [ config ]) configurations;
  installers = mapAttrs (name: config: iso config) configurations;
  shell = pkgs.mkShellNoCC {
    packages = [
      pkgs.npins
      run-vm
      make-iso
    ];
  };
}
```

The file has become unwieldy, and adding even more commands will completely drown the business logic in helper code.
At this point we will want to extract the definitions into a library to be able to write:

```nix
# ./default.nix
{
  sources ? import ./npins,
  system ? builtins.currentSystem,
}:
let
  pkgs = import sources.nixpkgs {
    config = { };
    overlays = [ ];
    system = builtins.currentSystem;
  };
  helpers = pkgs.callPackage ./lib/nixos-helpers.nix {};
in
rec {
  configurations = {
    foo = ./machines/foo.nix;
    bar = ./machines/bar.nix;
    # ...
  };
  machines = mapAttrs (name: config: helpers.nixos [ config ]) configurations;
  installers = mapAttrs (name: config: helpers.iso [ config ]) configurations;
  shell = pkgs.mkShellNoCC {
    packages = [
      pkgs.npins
      helpers.run-vm
      helpers.make-iso
    ];
  };
}
```

But how to actually do that while keeping the library reusable?
For example, `make-iso` hard-codes two assumptions:
1. The expression to build lives in a particular directory.
2. The expression has an attribute `installers`.

```
# ./lib/nixos-helpers.nix
{ pkgs }:
{
  make-iso = pkgs.writeShellApplication {
    name = "make-iso";
    text = ''
      machine="$1"
      shift
      nix-build ${../.} -A installers."$machine".config.system.build.isoImage --no-out-link "$@"
    '';
  };
  # ...
}
```

Moving the expression to a different directory will simply break the script.
And the library cannot be used by anyone else!

Changing the layout of `default.nix` will require adapting it.
Other users may want to organise their code differently.

Naive attempts to work around that only lead to more clumsy hacks, such as passing paths and attribute names.
And even then, additional use cases will likely require more entries in `default.nix` for the output attribute set *and* the shell's `packages`.

This doesn't scale.

So, what if we turned everything around, and let such a script take the relevant Nix value directly?

```nix
# ./lib/nixos-helpers.nix
{ pkgs }:
{
  make-iso = machine: pkgs.writeShellApplication {
    name = "make-iso";
    text = ''
      nix-build ${machine.config.system.build.isoImage} --no-out-link "$@"
    '';
  };
  # ...
}
```

Then the helper library could wire up configurations in an attribute set arranged by use case:

```nix
# ./lib/nixos-helpers.nix
{ pkgs }:
{
  # ...
  attrs = config: {
    inherit (nixos config) config;
    make-iso = make-iso config;
    run-vm = run-vm config;
    # ...
  };
}
```

Finally, in `default.nix` all that is left is something that translates from attributes to command line arguments.
This is where `attr-cmd` comes in:

```nix
# ./default.nix
{
  sources ? import ./npins,
  system ? builtins.currentSystem,
}:
let
  pkgs = import sources.nixpkgs {
    config = { };
    overlays = [ ];
    system = builtins.currentSystem;
  };
  attr-cmd = import sources.attr-cmd {};
  helpers = pkgs.callPackage ./lib/nixos-helpers.nix {};
in
rec {
  nixos = mapAttrs (name: config: helpers.attrs config) {
    foo = ./machines/foo.nix;
    bar = ./machines/bar.nix;
    # ...
  };
  commands = attr-cmd {
    path = ./.;
    attrs = { inherit nixos; };
  };
  shell = pkgs.mkShellNoCC {
    packages = builtins.attrValues commands ++ [
      pkgs.npins
    ];
  };
}
```

From this shell environment, you can now run:

```console
nixos foo make-iso
```

And this is just the beginning:
- You can restructure the commands simply by re-organising the attribute set passed to `attr-cmd`.
- You can use these exact commands from anywhere, since they are Nix derivations.
