open Lwt.Infix

module Db = struct
  let or_error = function
    | Ok x -> Ok x
    | Error e -> Error (Storage.QueryError (Caqti_error.show e))

  let connect path =
    let uri = Uri.make ~scheme:"sqlite3" ~path () in
    Caqti_lwt_unix.connect uri >|= function
    | Ok (module C : Caqti_lwt.CONNECTION) -> Ok (module C : Caqti_lwt.CONNECTION)
    | Error e -> Error (Storage.ConnectionError (Caqti_error.show e))
end

type t = (module Caqti_lwt.CONNECTION)

let init_tables (module C : Caqti_lwt.CONNECTION) =
  let open Caqti_request.Infix in
  let create_entity_defs =
    (Caqti_type.unit ->. Caqti_type.unit)
      "CREATE TABLE IF NOT EXISTS entity_definitions ( \
       id TEXT PRIMARY KEY, \
       type_id_prefix TEXT NOT NULL, \
       name TEXT NOT NULL, \
       description TEXT, \
       primary_key_field TEXT NOT NULL \
       )"
  in
  let create_idx_prefix =
    (Caqti_type.unit ->. Caqti_type.unit)
      "CREATE INDEX IF NOT EXISTS idx_entity_definitions_prefix ON entity_definitions(type_id_prefix)"
  in
  let create_idx_name =
    (Caqti_type.unit ->. Caqti_type.unit)
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_entity_definitions_name ON entity_definitions(LOWER(name))"
  in
  let create_entity_data =
    (Caqti_type.unit ->. Caqti_type.unit)
      "CREATE TABLE IF NOT EXISTS entity_data ( \
       id TEXT PRIMARY KEY, \
       entity_definition_id TEXT NOT NULL, \
       data TEXT NOT NULL \
       )"
  in
  C.exec create_entity_defs () >>= function
  | Error e -> Lwt.return (Db.or_error (Error e))
  | Ok () ->
      C.exec create_idx_prefix () >>= function
      | Error e -> Lwt.return (Db.or_error (Error e))
      | Ok () ->
          C.exec create_idx_name () >>= function
          | Error e -> Lwt.return (Db.or_error (Error e))
          | Ok () ->
              C.exec create_entity_data () >|= Db.or_error

let create_database path =
  Db.connect path >>= function
  | Ok conn -> (
      init_tables conn >|= function
      | Ok () -> Ok conn
      | Error e -> Error e)
  | Error e -> Lwt.return (Error e)

let open_database path = Db.connect path

let insert_entity_definition (module C : Caqti_lwt.CONNECTION) (def : Data.Entity_definition.t) =
  let open Caqti_request.Infix in
  let query =
    (Caqti_type.(t2 string (t2 string (t2 string (t2 (option string) string)))) ->. Caqti_type.unit)
      "INSERT INTO entity_definitions (id, type_id_prefix, name, description, primary_key_field) VALUES (?, ?, ?, ?, ?)"
  in
  C.exec query
    ( Type_id.to_string def.id,
      (def.type_id_prefix,
       (def.name,
        (def.description,
         def.primary_key_field) ) ) )
  >|= Db.or_error

let row_to_entity_def (id_str, (type_id_prefix, (name, (description, primary_key_field)))) =
  match Type_id.of_string id_str with
  | Ok id ->
      Ok
        Data.Entity_definition.
          { id; type_id_prefix; name; description; primary_key_field }
  | Error e -> Error (Storage.SerializationError e)

let get_entity_definition (module C : Caqti_lwt.CONNECTION) id =
  let open Caqti_request.Infix in
  let query =
    (Caqti_type.string ->? Caqti_type.(t2 string (t2 string (t2 string (t2 (option string) string)))))
      "SELECT id, type_id_prefix, name, description, primary_key_field FROM entity_definitions WHERE id = ?"
  in
  C.find_opt query (Type_id.to_string id) >|= Db.or_error >>= function
  | Error e -> Lwt.return (Error e)
  | Ok None -> Lwt.return (Ok None)
  | Ok (Some row) -> Lwt.return (match row_to_entity_def row with Ok x -> Ok (Some x) | Error e -> Error e)

let get_entity_definition_by_prefix (module C : Caqti_lwt.CONNECTION) prefix =
  let open Caqti_request.Infix in
  let query =
    (Caqti_type.string ->? Caqti_type.(t2 string (t2 string (t2 string (t2 (option string) string)))))
      "SELECT id, type_id_prefix, name, description, primary_key_field FROM entity_definitions WHERE type_id_prefix = ?"
  in
  C.find_opt query prefix >|= Db.or_error >>= function
  | Error e -> Lwt.return (Error e)
  | Ok None -> Lwt.return (Ok None)
  | Ok (Some row) -> Lwt.return (match row_to_entity_def row with Ok x -> Ok (Some x) | Error e -> Error e)

let get_entity_definition_by_name (module C : Caqti_lwt.CONNECTION) name =
  let open Caqti_request.Infix in
  let query =
    (Caqti_type.string ->? Caqti_type.(t2 string (t2 string (t2 string (t2 (option string) string)))))
      "SELECT id, type_id_prefix, name, description, primary_key_field FROM entity_definitions WHERE LOWER(name) = LOWER(?)"
  in
  C.find_opt query name >|= Db.or_error >>= function
  | Error e -> Lwt.return (Error e)
  | Ok None -> Lwt.return (Ok None)
  | Ok (Some row) -> Lwt.return (match row_to_entity_def row with Ok x -> Ok (Some x) | Error e -> Error e)

let get_all_entity_definitions (module C : Caqti_lwt.CONNECTION) =
  let open Caqti_request.Infix in
  let query =
    (Caqti_type.unit ->* Caqti_type.(t2 string (t2 string (t2 string (t2 (option string) string)))))
      "SELECT id, type_id_prefix, name, description, primary_key_field FROM entity_definitions"
  in
  C.fold query (fun row acc ->
      match acc with
      | Error e -> Error e
      | Ok lst -> (
          match row_to_entity_def row with
          | Ok def -> Ok (def :: lst)
          | Error e -> Error e)) () (Ok []) >|= function
  | Ok (Ok lst) -> Ok (List.rev lst)
  | Ok (Error e) -> Error e
  | Error e -> Db.or_error (Error e)

let insert_entity_data (module C : Caqti_lwt.CONNECTION) (data : Data.Entity_data.t) =
  let open Caqti_request.Infix in
  let query =
    (Caqti_type.(t3 string string string) ->. Caqti_type.unit)
      "INSERT INTO entity_data (id, entity_definition_id, data) VALUES (?, ?, ?)"
  in
  let json_str = Yojson.Safe.to_string data.data in
  C.exec query
    (Type_id.to_string data.id, Type_id.to_string data.entity_definition_id, json_str)
  >|= Db.or_error

let get_entity_data (module C : Caqti_lwt.CONNECTION) id =
  let open Caqti_request.Infix in
  let query =
    (Caqti_type.string ->? Caqti_type.(t3 string string string))
      "SELECT id, entity_definition_id, data FROM entity_data WHERE id = ?"
  in
  C.find_opt query (Type_id.to_string id) >|= Db.or_error >>= function
  | Error e -> Lwt.return (Error e)
  | Ok None -> Lwt.return (Ok None)
  | Ok (Some (id_str, def_id_str, data_str)) ->
      Lwt.return
        (match (Type_id.of_string id_str, Type_id.of_string def_id_str) with
        | Ok id, Ok def_id ->
            let data = Yojson.Safe.from_string data_str in
            Ok (Some Data.Entity_data.{ id; entity_definition_id = def_id; data })
        | Error e, _ | _, Error e -> Error (Storage.SerializationError e))
