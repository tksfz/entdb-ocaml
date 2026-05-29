open Entdb_data
open Entdb_entity_api

module Task = struct
  module Id = Entdb_data.Entity_id.Make(struct let type_id_prefix = "tsk" end)

  type t = {
    id : Id.t;
    title : string;
    status : string;
  } [@@deriving yojson]

  let name = "Task"
  let description = Some "A task entity defined in a source with ppx"
  let primary_key_field = "id"
end

let () = Entdb_sources.Harness.register (module Task)
let () = Printf.printf "Source (PPX): Task entity defined and registered.\n"