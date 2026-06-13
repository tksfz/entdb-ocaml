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
            nativeBuildInputs = [ pkgs.patchelf ocamlPkgs.findlib pkgs.python3 ];
            preBuild = ''
              export LIBRARY_PATH="$(ocamlfind query -format '%d' \
                lwt.unix base base.base_internalhash_types \
                ocaml_intrinsics_kernel bigstringaf mtime.clock.os sqlite3 \
                | tr '\n' ':')$LIBRARY_PATH"
            '';
            # strip rewrites the ELF and drops OCaml's appended bytecode, so we
            # disable it and strip only native shared objects ourselves.
            dontStrip = true;
            preFixup = ''
              find $out/lib -name "*.cmxs" -exec strip -S -p {} \;
            '';
            postFixup = ''
              # Patch the interpreter in-place so patchelf doesn't append a new
              # ELF segment at EOF, which would displace the OCaml bytecode trailer
              # that the runtime locates by reading from the end of the file.
              # Dead Nix store RPATH entries are harmless on non-Nix systems.
              python3 -c "
import re, sys
path = '$out/bin/entdb'
new = b'/lib64/ld-linux-x86-64.so.2\x00'
with open(path, 'r+b') as f:
    data = f.read()
    m = re.search(b'/nix/store/[^\x00]+/ld-linux-x86-64\\.so\\.2\x00', data)
    if not m:
        sys.exit('interpreter not found in binary')
    old = m.group(0)
    assert len(old) >= len(new), 'new interpreter longer than old'
    f.seek(m.start())
    f.write(new + b'\x00' * (len(old) - len(new)))
"
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
