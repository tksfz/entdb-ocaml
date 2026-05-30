type lang = Ocaml

let lang_to_string = function
  | Ocaml -> "ocaml"

let lang_of_string = function
  | "ocaml" -> Ok Ocaml
  | s -> Error (Printf.sprintf "Unknown schema source lang: %s" s)

type id = Type_id.t

let create_id () = Type_id.create_v7 "ent_source"

(* Stored source files that define schemas and should 
   be evaluated on entdb startup *)
type t = {
  id: id;
  created_at: float;
  filename: string;
  file_hash: string;
  lang: lang;
  source: string;
}
