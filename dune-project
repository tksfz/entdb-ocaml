(lang dune 3.21)

(name entdb)

(generate_opam_files true)

(package
 (name entdb)
 (synopsis "EntDB")
 (description "A database for agents")
 (depends
  ocaml
  dune
  lwt
  lwt_ppx
  caqti
  caqti-lwt
  caqti-driver-sqlite3
  yojson
  ppx_yojson_conv
  uuidm
  cmdliner
  findlib
  validate))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
