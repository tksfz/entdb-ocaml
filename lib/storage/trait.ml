type error =
  | ConnectionError of string
  | QueryError of string
  | NotFound of string
  | SerializationError of string
  | Other of string

let error_to_string = function
  | ConnectionError msg -> Printf.sprintf "Connection Error: %s" msg
  | QueryError msg -> Printf.sprintf "Query Error: %s" msg
  | NotFound msg -> Printf.sprintf "Not Found: %s" msg
  | SerializationError msg -> Printf.sprintf "Serialization Error: %s" msg
  | Other msg -> Printf.sprintf "Error: %s" msg

module type S = sig
  type t

  val create_database : string -> (t, error) result Lwt.t
  val open_database : string -> (t, error) result Lwt.t

  val insert_entity_definition : t -> Entdb_data.Entity_definition.t -> (unit, error) result Lwt.t
  val get_entity_definition : t -> Entdb_data.Entity_definition.id -> (Entdb_data.Entity_definition.t option, error) result Lwt.t
  val get_entity_definition_by_prefix : t -> string -> (Entdb_data.Entity_definition.t option, error) result Lwt.t
  val get_entity_definition_by_name : t -> string -> (Entdb_data.Entity_definition.t option, error) result Lwt.t
  val get_all_entity_definitions : t -> (Entdb_data.Entity_definition.t list, error) result Lwt.t

  val insert_entity_data : t -> Entdb_data.Entity_data.t -> (unit, error) result Lwt.t
  val get_entity_data : t -> Entdb_data.Type_id.t -> (Entdb_data.Entity_data.t option, error) result Lwt.t
end
