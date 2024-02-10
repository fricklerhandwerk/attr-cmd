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
  attr-cmd = { path, attrs }:
    let
      command = name: pkgs.writeShellApplication {
        inherit name;
        text = ''
          attrs=()
          while (( "$#" )); do
            if [[ "$1" == "--" ]]; then
              shift
              break
            fi
            attrs+=("$1")
            shift
          done
          attrpath=${name}."$(IFS=.; echo "''${attrs[*]}")"
          "$(nix-build ${path} -A "$attrpath" --no-out-link)"/bin/"''${attrs[-1]}" "$@"
        '';
      };
    in
    builtins.mapAttrs (name: attr: command name) attrs;
  shell = pkgs.mkShellNoCC {
    packages = builtins.attrValues commands ++ [
      pkgs.npins
    ];
  };
  commands = attr-cmd { path = ./.; attrs = { inherit foo; }; };
  foo.bar.baz = pkgs.writeScriptBin "baz" "echo success";
}
