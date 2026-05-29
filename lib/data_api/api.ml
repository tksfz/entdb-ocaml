open Lwt.Infix

module Make (S : Entdb_storage.Trait.S) = struct
  type t = { storage : S.t }

  let create storage = { storage }

  (* --- Public Record-level API (Internal Logic Centralized Here) --- *)

  let get_entity_definition_by_name t name =
    S.get_entity_definition_by_name t.storage name >>= function
    | Error e -> Lwt.return (Error (Entdb_storage.Trait.error_to_string e))
    | Ok res -> Lwt.return (Ok res)

  let insert_entity_definition t (def : Entdb_data.Entity_definition.t) =
    S.insert_entity_definition t.storage def >>= function
    | Error e -> Lwt.return (Error (Entdb_storage.Trait.error_to_string e))
    | Ok () -> Lwt.return (Ok ())

  let put_entity_yojson t entity_name json =
    get_entity_definition_by_name t entity_name >>= function
    | Error e -> Lwt.return (Error e)
    | Ok None -> Lwt.return (Error (Printf.sprintf "Unknown entity definition name: %s" entity_name))
    | Ok (Some def) -> (
        let open Yojson.Safe.Util in
        match json |> member def.primary_key_field |> to_string_option with
        | None ->
            Lwt.return (Error (Printf.sprintf "Missing primary key field '%s' in JSON payload" def.primary_key_field))
        | Some id_str -> (
            match Entdb_data.Type_id.of_string id_str with
            | Error e -> Lwt.return (Error (Printf.sprintf "Invalid TypeId format: %s" e))
            | Ok type_id ->
                if String.equal (Entdb_data.Type_id.prefix type_id) def.type_id_prefix then
                  let data = Entdb_data.Entity_data.{ id = type_id; entity_definition_id = def.id; data = json } in
                  S.insert_entity_data t.storage data >>= function
                  | Ok () -> Lwt.return (Ok ())
                  | Error e -> Lwt.return (Error (Entdb_storage.Trait.error_to_string e))
                else
                  Lwt.return (Error (Printf.sprintf "ID prefix '%s' does not match entity definition prefix '%s'" (Entdb_data.Type_id.prefix type_id) def.type_id_prefix))))

  (* --- Public String/CLI API --- *)

  let add_entity_definition t blob =
    match Yojson.Safe.from_string blob with
    | exception _ -> Lwt.return (Error "Invalid JSON payload")
    | json -> (
        let open Yojson.Safe.Util in
        try
          let name = json |> member "name" |> to_string in
          let prefix = json |> member "prefix" |> to_string in
          let description = json |> member "description" |> to_string_option in
          let primary_key_field =
            match json |> member "primary_key_field" |> to_string_option with
            | Some v -> v
            | None -> "id"
          in
          let definition =
            Entdb_data.Entity_definition.
              {
                id = Entdb_data.Entity_definition.create_id ();
                name;
                description;
                type_id_prefix = prefix;
                primary_key_field;
              }
          in
          insert_entity_definition t definition
        with Type_error (msg, _) ->
          Lwt.return (Error (Printf.sprintf "Missing or invalid field in JSON payload: %s" msg)))

  let list_entity_definitions t =
    S.get_all_entity_definitions t.storage >>= function
    | Error e -> Lwt.return (Error (Entdb_storage.Trait.error_to_string e))
    | Ok defs ->
        let to_json (def : Entdb_data.Entity_definition.t) : Yojson.Safe.t =
          let base : (string * Yojson.Safe.t) list =
            [
              ("id", `String (Entdb_data.Type_id.to_string def.id));
              ("name", `String def.name);
              ("prefix", `String def.type_id_prefix);
              ("primary_key_field", `String def.primary_key_field);
            ]
          in
          let with_desc : (string * Yojson.Safe.t) list =
            match def.description with
            | Some desc -> ("description", `String desc) :: base
            | None -> base
          in
          `Assoc with_desc
        in
        Lwt.return (Ok (`List (List.map to_json defs) : Yojson.Safe.t))

  let put_entity_data t entity_name blob =
    match Yojson.Safe.from_string blob with
    | exception _ -> Lwt.return (Error "Invalid JSON payload")
    | json -> put_entity_yojson t entity_name json

  let get_entity_data t id_str =
    match Entdb_data.Type_id.of_string id_str with
    | Error e -> Lwt.return (Error (Printf.sprintf "Invalid TypeId format: %s" e))
    | Ok type_id -> (
        S.get_entity_data t.storage type_id >>= function
        | Error e -> Lwt.return (Error (Entdb_storage.Trait.error_to_string e))
        | Ok None -> Lwt.return (Ok None)
        | Ok (Some data) -> Lwt.return (Ok (Some data.Entdb_data.Entity_data.data)))
end
