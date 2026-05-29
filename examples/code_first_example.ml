open Lwt.Infix

module Task = struct
  module Id = Entdb_core.Entity_id.Make(struct let type_id_prefix = "tsk" end)
  
  type t = {
    id : Id.t;
    title : string;
    status : string;
  } [@@deriving yojson]

  let name = "Task"
  let description = Some "A code-defined task entity"
  let primary_key_field = "id"
end

module Data_api = Entdb_data.Api.Make(Entdb_storage.Sqlite)
module Entity_api = Entdb_entity.Api.Make(Data_api)

let run_example () =
  let db_path = "example_code_first.sqlite" in
  (if Sys.file_exists db_path then Sys.remove db_path);

  Entdb_storage.Sqlite.create_database db_path >>= function
  | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
  | Ok storage ->
      let api = Data_api.create storage in

      Printf.printf "Registering Task entity...\n";
      Entity_api.register_entity api (module Task) >>= function
      | Error e -> Lwt.fail_with e
      | Ok () ->

      let my_id = Task.Id.create () in
      let my_task = Task.{ id = my_id; title = "Implement OCaml traits"; status = "doing" } in
      
      Printf.printf "Inserting task %s...\n" (Task.Id.to_string my_id);
      Entity_api.put_entity api (module Task) my_task >>= function
      | Error e -> Lwt.fail_with e
      | Ok () ->

      Printf.printf "Retrieving task %s...\n" (Task.Id.to_string my_id);
      Entity_api.get_entity api (module Task) my_id >>= function
      | Error e -> Lwt.fail_with e
      | Ok None -> Lwt.fail_with "Task not found"
      | Ok (Some retrieved_task) ->
          Printf.printf "Retrieved Task: %s (Status: %s)\n" 
            retrieved_task.Task.title retrieved_task.Task.status;
          Lwt.return_unit

let () =
  Lwt_main.run (run_example ())