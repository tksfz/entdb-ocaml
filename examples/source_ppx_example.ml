open Entdb_core
open Entdb_entity

type task = {
  id : task Entdb_core.Entity_id.t;
  title : string;
  status : string;
} [@@deriving yojson]

module Task = struct
  type t = task
  let name = "Task"
  let description = Some "A task entity defined in a source with ppx"
  let type_id_prefix = "tsk"
  let primary_key_field = "id"
  
  let yojson_of_t = yojson_of_task
  let t_of_yojson = task_of_yojson
end

let () = Entdb_sources.Harness.register (module Task)
let () = Printf.printf "Source (PPX): Task entity defined and registered.\n"
