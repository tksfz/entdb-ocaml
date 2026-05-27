open Lwt.Infix

module type DATA_API = sig
  type t
  val get_entity_definition_by_name : t -> string -> (Entdb_core.Entity_definition.t option, string) result Lwt.t
  val insert_entity_definition : t -> Entdb_core.Entity_definition.t -> (unit, string) result Lwt.t
  val put_entity_yojson : t -> string -> Yojson.Safe.t -> (unit, string) result Lwt.t
  val get_entity_data : t -> string -> (Yojson.Safe.t option, string) result Lwt.t
end

module Make (D : DATA_API) = struct

  let register_entity (t : D.t) (module E : Entdb_core.Entity_trait.S) =
    D.get_entity_definition_by_name t E.name >>= function
    | Error e -> Lwt.return (Error e)
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
        D.insert_entity_definition t definition

  let put_entity (type a) (t : D.t) (module E : Entdb_core.Entity_trait.S with type t = a) (data : a) =
    let json = E.yojson_of_t data in
    D.put_entity_yojson t E.name json

  let get_entity (type a) (t : D.t) (module E : Entdb_core.Entity_trait.S with type t = a) id_str =
    D.get_entity_data t id_str >>= function
    | Error e -> Lwt.return (Error e)
    | Ok None -> Lwt.return (Ok None)
    | Ok (Some json) -> (
        try Lwt.return (Ok (Some (E.t_of_yojson json)))
        with _ -> Lwt.return (Error "Failed to deserialize entity data"))
end
