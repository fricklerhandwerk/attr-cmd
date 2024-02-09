# `attr-cmd`

Build shell commands from Nix attribute sets.

## Motivation

I keep running into a scalability problem with the following pattern:

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
