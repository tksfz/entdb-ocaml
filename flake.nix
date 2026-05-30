{
  description = "OCaml development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_1;
        validate = ocamlPackages.buildDunePackage rec {
          pname = "validate";
          version = "1.1.0";
          src = pkgs.fetchurl {
            url = "https://github.com/Axot017/validate/releases/download/v1.1.0/validate-1.1.0.tbz";
            sha256 = "830d3b1ac8cdacfca2877030dd0377e46115527e7963359537daa5897e563da4";
          };
          propagatedBuildInputs = with ocamlPackages; [ ppx_deriving re uri ];
          doCheck = false;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            ocamlPackages.ocaml
            ocamlPackages.dune_3
            ocamlPackages.ocaml-lsp
            ocamlPackages.ocamlformat
            ocamlPackages.utop
            ocamlPackages.findlib
            opam
          ];

          buildInputs = with ocamlPackages; [
            lwt
            lwt_ppx
            caqti
            caqti-lwt
            caqti-driver-sqlite3
            yojson
            ppx_yojson_conv
            uuidm
            cmdliner
            validate
            alcotest
          ];

          shellHook = ''
            echo "OCaml development environment loaded"
            ocaml --version
            dune --version
            # ocamlc -custom needs to find C stub archives (.a) for static linking.
            # In Nix these live inside each package's site-lib subdir, not on the
            # standard linker path, so we add them explicitly.
            export LIBRARY_PATH="$(ocamlfind query -format '%d' \
              lwt.unix base base.base_internalhash_types \
              ocaml_intrinsics_kernel bigstringaf mtime.clock.os sqlite3 \
              | tr '\n' ':')''${LIBRARY_PATH:+:$LIBRARY_PATH}"
          '';
        };
      });
}
