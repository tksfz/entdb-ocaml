open Lwt.Infix

module Make (S : Entdb_storage.Trait.S) = struct
  module D = Entdb_data.Api.Make(S)

  let register_entity (t : D.t) (module E : Trait.S) =
    S.get_entity_definition_by_name t.storage E.name >>= function
    | Error e -> Lwt.return (Error (Entdb_storage.Trait.error_to_string e))
    | Ok (Some _) -> Lwt.return (Ok ())
    | Ok None ->
        let definition =
          Entdb_core.Entity_definition.
            {
              id = Entdb_core.Entity_definition.create_id ();
              name = E.name;
              description = E.description;
              type_id_prefix = E.type_id_prefix;
              primary_key_field = E.primary_key_field;
            }
        in
        S.insert_entity_definition t.storage definition >>= function
        | Ok () -> Lwt.return (Ok ())
        | Error e -> Lwt.return (Error (Entdb_storage.Trait.error_to_string e))

  let put_entity (type a) (t : D.t) (module E : Trait.S with type t = a) (data : a) =
    let json = E.yojson_of_t data in
    D.put_entity_yojson t E.name json

  let get_entity (type a) (t : D.t) (module E : Trait.S with type t = a) id_str =
    D.get_entity_data t id_str >>= function
    | Error e -> Lwt.return (Error e)
    | Ok None -> Lwt.return (Ok None)
    | Ok (Some json) -> (
        try Lwt.return (Ok (Some (E.t_of_yojson json)))
        with _ -> Lwt.return (Error "Failed to deserialize entity data"))
end
