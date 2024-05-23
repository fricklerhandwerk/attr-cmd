{
  sources ? import ./npins,
  system ? builtins.currentSystem,
  pkgs ? import sources.nixpkgs { inherit system; config = { }; overlays = [ ]; },
  nixdoc-to-github ? pkgs.callPackage sources.nixdoc-to-github { },
  git-hooks ? pkgs.callPackage sources.git-hooks { },
}:
let
  lib  = {
    inherit (git-hooks.lib) git-hooks;
    inherit (nixdoc-to-github.lib) nixdoc-to-github;
  };
  update-readme = lib.nixdoc-to-github.run {
    description = "\\`attr-cmd\\`";
    category = "attr-cmd";
    file = "${toString ./lib.nix}";
    output = "${toString ./README.md}";
  };
in
{
  lib.attr-cmd = pkgs.callPackage ./lib.nix { };

  shell = pkgs.mkShellNoCC {
    packages = [
      pkgs.npins
    ];
    shellHook = ''
      ${with lib.git-hooks; pre-commit (wrap.abort-on-change update-readme)}
    '';
  };
}
