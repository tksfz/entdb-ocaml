{
  description = "OCaml development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # glibc 2.39 (Ubuntu 24.04); unstable currently ships 2.42.
    nixpkgsGlibc239.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgsGlibc239, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        pkgsPortable = nixpkgsGlibc239.legacyPackages.${system};

        makePackages = { pkgs, ocamlPkgs }: rec {
          validate = ocamlPkgs.buildDunePackage rec {
            pname = "validate";
            version = "1.1.0";
            src = pkgs.fetchurl {
              url = "https://github.com/Axot017/validate/releases/download/v1.1.0/validate-1.1.0.tbz";
              sha256 = "830d3b1ac8cdacfca2877030dd0377e46115527e7963359537daa5897e563da4";
            };
            propagatedBuildInputs = with ocamlPkgs; [ ppx_deriving ppxlib re uri ];
            doCheck = false;
          };

          # How the portable binary works
          # ==============================
          # Goal: a single self-contained binary that runs on any x86_64 Linux
          # with glibc, libsqlite3, and libev — no Nix store or build tree needed.
          #
          # 1. CMI embedding (build time)
          #    tools/gen_embed uses findlib to discover every .cmi file from the
          #    five internal libraries and emits them as string literals in
          #    lib/sources/embedded_cmis.ml.  The dune rule for this file depends
          #    on each library's .cma so it rebuilds whenever a library changes.
          #
          # 2. CMI extraction (runtime)
          #    lib/sources/runner.ml has a lazy `cmi_dir` value that, on first
          #    use, writes all embedded CMIs into a temp directory and adds that
          #    directory to the OCaml toploop's load path.  This replaces the
          #    old approach of hardcoding _build/default/... paths.
          #
          # 3. Binary format
          #    bin/dune builds with (modes byte) and ocamlc -custom, which
          #    produces an ELF binary containing the OCaml C runtime followed by
          #    the bytecode appended after the last ELF section.  The runtime
          #    locates the bytecode by reading a trailer from the end of the file.
          #
          # 4. Nix packaging pitfalls
          #    a. strip -S rewrites the ELF and silently drops everything after
          #       the last ELF section — i.e. the bytecode.  Avoided with
          #       dontStrip = true; native .cmxs shared objects are stripped
          #       manually in preFixup instead.
          #    b. patchelf --set-interpreter may append a new PT_LOAD segment at
          #       end-of-file to store the longer/shorter interpreter string,
          #       again displacing the bytecode trailer.  Avoided by patching the
          #       interpreter bytes in-place with Python (simple find-and-replace
          #       inside the binary).
          #    c. RUNPATH entries pointing at the Nix store must be removed.  On
          #       CI the store paths exist after `nix build`, so the system
          #       ld-linux would load Nix glibc alongside the host linker and
          #       crash (FPE).  On end-user systems we want system libsqlite3,
          #       libev, and glibc from the default search path anyway.
          #
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
            nativeBuildInputs = with pkgs; [
              ocamlPkgs.findlib
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.patchelf pkgs.python3 ];
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
            postFixup = pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              # Patch the interpreter in-place so patchelf doesn't append a new
              # ELF segment at EOF, which would displace the OCaml bytecode trailer
              # that the runtime locates by reading from the end of the file.
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
              # Drop Nix store RUNPATH so the binary uses system libsqlite3, libev,
              # and glibc.  --remove-rpath only edits the dynamic section in place.
              patchelf --remove-rpath ''$out/bin/entdb
            '';
            doCheck = false;
          };
        };

        ocamlPackages = pkgs.ocaml-ng.ocamlPackages_5_1;

        devPackages = makePackages { inherit pkgs; ocamlPkgs = ocamlPackages; };
        portablePackages = makePackages {
          pkgs = pkgsPortable;
          ocamlPkgs = pkgsPortable.ocaml-ng.ocamlPackages_5_1;
        };

        localEntdb = devPackages.entdb.overrideAttrs (old: {
          preFixup = "";
          postFixup = "";
          nativeBuildInputs = builtins.filter
            (p: p != pkgs.patchelf && p != pkgs.python3)
            old.nativeBuildInputs;
        });

      in
      {
        # Linux: portable binary with glibc 2.39 and ELF interpreter patching.
        # macOS: local build (no ELF patching; runs on the build host).
        packages.default =
          if pkgs.stdenv.isDarwin then
            localEntdb
          else
            portablePackages.entdb.overrideAttrs (old: {
              # nixos-24.05 ships dune 3.15; patch the language version for the build.
              preBuild = ''
                substituteInPlace dune-project --replace-fail '(lang dune 3.21)' '(lang dune 3.15)'
                chmod -R u+w test
                rm -rf test
                export LIBRARY_PATH="$(ocamlfind query -format '%d' \
                  lwt.unix base base.base_internalhash_types \
                  bigstringaf mtime.clock.os sqlite3 \
                  | tr '\n' ':')$LIBRARY_PATH"
              '';
            });
        # NixOS-native build: no interpreter patching, runs directly on this system.
        # Use with: nix run .#local  or  nix build .#local
        packages.local = localEntdb;

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            ocamlPackages.ocaml
            ocamlPackages.dune_3
            ocamlPackages.ocaml-lsp
            ocamlPackages.ocamlformat
            ocamlPackages.utop
            ocamlPackages.findlib
            opam
            localEntdb
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
