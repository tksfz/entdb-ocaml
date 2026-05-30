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

        makePackages = ocamlPkgs: rec {
          validate = ocamlPkgs.buildDunePackage rec {
            pname = "validate";
            version = "1.1.0";
            src = pkgs.fetchurl {
              url = "https://github.com/Axot017/validate/releases/download/v1.1.0/validate-1.1.0.tbz";
              sha256 = "830d3b1ac8cdacfca2877030dd0377e46115527e7963359537daa5897e563da4";
            };
            propagatedBuildInputs = with ocamlPkgs; [ ppx_deriving re uri ];
            doCheck = false;
          };

          entdb = ocamlPkgs.buildDunePackage {
            pname = "entdb";
            version = "0.1.0";
            src = self;
            buildInputs = with ocamlPkgs; [
              lwt lwt_ppx
              caqti caqti-lwt caqti-driver-sqlite3
              yojson ppx_yojson_conv
              uuidm cmdliner
              findlib ppxlib
              validate
            ];
            nativeBuildInputs = [ pkgs.patchelf ocamlPkgs.findlib ];
            preBuild = ''
              export LIBRARY_PATH="$(ocamlfind query -format '%d' \
                lwt.unix base base.base_internalhash_types \
                ocaml_intrinsics_kernel bigstringaf mtime.clock.os sqlite3 \
                | tr '\n' ':')$LIBRARY_PATH"
            '';
            postFixup = ''
              patchelf \
                --set-interpreter /lib64/ld-linux-x86-64.so.2 \
                --set-rpath "" \
                $out/bin/entdb
            '';
            doCheck = false;
          };
        };

        ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_1;
        staticOcamlPackages = pkgs.pkgsStatic.ocaml-ng.ocamlPackages_5_1;

        devPackages = makePackages ocamlPackages;

      in
      {
        packages.default = devPackages.entdb;

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
            devPackages.validate
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
