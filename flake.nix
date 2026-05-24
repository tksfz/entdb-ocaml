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
          ];

          shellHook = ''
            echo "OCaml development environment loaded"
            ocaml --version
            dune --version
          '';
        };
      });
}
