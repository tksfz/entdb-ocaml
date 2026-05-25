open Lwt.Infix

(* 1. Define your entity struct (record) *)
type task = {
  id : string;
  title : string;
  status : string;
} [@@deriving yojson]

(* 2. Create the Entity module (The "Trait" implementation) *)
module Task = struct
  type t = task [@@deriving yojson]
  let name = "Task"
  let description = Some "A code-defined task entity"
  let type_id_prefix = "tsk"
  let primary_key_field = "id"
end

module Data_api = Entdb_data.Api.Make(Entdb_storage.Sqlite)
module Entity_api = Entdb_entity.Api.Make(Entdb_storage.Sqlite)

let run_example () =
  let db_path = "example_code_first.sqlite" in
  (if Sys.file_exists db_path then Sys.remove db_path);

  Entdb_storage.Sqlite.create_database db_path >>= function
  | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
  | Ok storage ->
      let api = Data_api.create storage in

      (* 3. Register the entity in the database automatically *)
      Printf.printf "Registering Task entity...\n";
      Entity_api.register_entity api (module Task) >>= function
      | Error e -> Lwt.fail_with e
      | Ok () ->

      (* 4. Insert data using the type-safe put_entity *)
      let my_id = Entdb_core.Type_id.to_string (Entdb_core.Type_id.create_v7 Task.type_id_prefix) in
      let my_task = { id = my_id; title = "Implement OCaml traits"; status = "doing" } in
      
      Printf.printf "Inserting task %s...\n" my_id;
      Entity_api.put_entity api (module Task) my_task >>= function
      | Error e -> Lwt.fail_with e
      | Ok () ->

      (* 5. Retrieve data using the type-safe get_entity *)
      Printf.printf "Retrieving task %s...\n" my_id;
      Entity_api.get_entity api (module Task) my_id >>= function
      | Error e -> Lwt.fail_with e
      | Ok None -> Lwt.fail_with "Task not found"
      | Ok (Some retrieved_task) ->
          Printf.printf "Retrieved Task: %s (Status: %s)\n" 
            retrieved_task.title retrieved_task.status;
          Lwt.return_unit

let () =
  Lwt_main.run (run_example ())
