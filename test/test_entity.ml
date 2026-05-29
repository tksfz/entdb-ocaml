open Lwt.Infix

let run = Lwt_main.run

module Task = struct
  module Id = Entdb_data.Entity_id.Make(struct let type_id_prefix = "tsk" end)

  type t = {
    id : Id.t;
    title : string;
  } [@@deriving yojson]

  let name = "Task"
  let description = None
  let primary_key_field = "id"
end

module Data_api = Entdb_data_api.Api.Make(Entdb_storage.Sqlite)
module Entity_api = Entdb_entity_api.Api.Make(Data_api)

let make_api () =
  let path = Filename.temp_file "test_entdb_entity" ".sqlite" in
  Sys.remove path;
  run (
    Entdb_storage.Sqlite.create_database path >>= function
    | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
    | Ok storage -> Lwt.return (Data_api.create storage))

let test_register_entity () =
  let api = make_api () in
  run (
    Entity_api.register_entity api (module Task) >>= function
    | Error e -> Lwt.fail_with e
    | Ok () ->
        Data_api.get_entity_definition_by_name api "Task" >>= function
        | Error e -> Lwt.fail_with e
        | Ok None -> Lwt.fail_with "Task definition not found"
        | Ok (Some def) ->
            Alcotest.(check string) "name" "Task" def.Entdb_data.Entity_definition.name;
            Alcotest.(check string) "prefix" "tsk" def.Entdb_data.Entity_definition.type_id_prefix;
            Lwt.return_unit)

let test_register_entity_idempotent () =
  let api = make_api () in
  run (
    Entity_api.register_entity api (module Task) >>= function
    | Error e -> Lwt.fail_with e
    | Ok () ->
        Entity_api.register_entity api (module Task) >>= function
        | Error e -> Lwt.fail_with e
        | Ok () -> Lwt.return_unit)

let test_put_get_entity () =
  let api = make_api () in
  run (
    Entity_api.register_entity api (module Task) >>= function
    | Error e -> Lwt.fail_with e
    | Ok () ->
        let id = Task.Id.create () in
        let task = Task.{ id; title = "Write tests" } in
        Entity_api.put_entity api (module Task) task >>= function
        | Error e -> Lwt.fail_with e
        | Ok () ->
            Entity_api.get_entity api (module Task) id >>= function
            | Error e -> Lwt.fail_with e
            | Ok None -> Lwt.fail_with "task not found"
            | Ok (Some retrieved) ->
                Alcotest.(check string) "title" "Write tests" retrieved.Task.title;
                Lwt.return_unit)

let () =
  Alcotest.run "entdb_entity" [
    "api", [
      Alcotest.test_case "register entity"            `Quick test_register_entity;
      Alcotest.test_case "register entity idempotent" `Quick test_register_entity_idempotent;
      Alcotest.test_case "put and get entity"         `Quick test_put_get_entity;
    ];
  ]
