open Entdb_core
open Entdb_entity

module Task = struct
  module Id = Entdb_core.Entity_id.Make(struct let type_id_prefix = "tsk" end)

  type t = {
    id : Id.t; [@validate.custom fun id -> match Id.validate id with Ok () -> Ok () | Error e -> Error (Validate.BaseError {code=e; params=[]})]
    title : string; [@min_length 3]
    status : string;
  } [@@deriving yojson, validate]

  let name = "Task"
  let description = Some "A task entity defined in a source with ppx validate"
  let type_id_prefix = "tsk"
  let primary_key_field = "id"
end

let () = Entdb_sources.Harness.register (module Task)
let () = Printf.printf "Source (Validate): Task entity defined and registered.\n"