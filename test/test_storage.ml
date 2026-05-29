open Lwt.Infix

let run = Lwt_main.run

let make_db () =
  let path = Filename.temp_file "test_entdb_storage" ".sqlite" in
  Sys.remove path;
  run (
    Entdb_storage.Sqlite.create_database path >>= function
    | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
    | Ok conn -> Lwt.return conn)

let sample_def () : Entdb_core.Entity_definition.t =
  Entdb_core.Entity_definition.{
    id = create_id ();
    name = "User";
    description = Some "A user";
    type_id_prefix = "usr";
    primary_key_field = "id";
  }

let test_create_database () =
  let _ = make_db () in ()

let test_definition_round_trip () =
  let conn = make_db () in
  let def = sample_def () in
  run (
    Entdb_storage.Sqlite.insert_entity_definition conn def >>= function
    | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
    | Ok () ->
        Entdb_storage.Sqlite.get_entity_definition_by_name conn "User" >>= function
        | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
        | Ok None -> Lwt.fail_with "definition not found"
        | Ok (Some retrieved) ->
            Alcotest.(check string) "name" "User" retrieved.Entdb_core.Entity_definition.name;
            Alcotest.(check string) "prefix" "usr" retrieved.Entdb_core.Entity_definition.type_id_prefix;
            Lwt.return_unit)

let test_definition_not_found () =
  let conn = make_db () in
  run (
    Entdb_storage.Sqlite.get_entity_definition_by_name conn "Nonexistent" >>= function
    | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
    | Ok None -> Lwt.return_unit
    | Ok (Some _) -> Lwt.fail_with "should not have found anything")

let test_entity_data_round_trip () =
  let conn = make_db () in
  let def = sample_def () in
  run (
    Entdb_storage.Sqlite.insert_entity_definition conn def >>= function
    | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
    | Ok () ->
        let data = Entdb_core.Entity_data.create def (`Assoc [("name", `String "Thom")]) in
        Entdb_storage.Sqlite.insert_entity_data conn data >>= function
        | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
        | Ok () ->
            Entdb_storage.Sqlite.get_entity_data conn data.Entdb_core.Entity_data.id >>= function
            | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
            | Ok None -> Lwt.fail_with "entity data not found"
            | Ok (Some retrieved) ->
                let name = Yojson.Safe.Util.(retrieved.Entdb_core.Entity_data.data |> member "name" |> to_string) in
                Alcotest.(check string) "name" "Thom" name;
                Lwt.return_unit)

let test_entity_data_not_found () =
  let conn = make_db () in
  let missing_id = Entdb_core.Type_id.create_v7 "usr" in
  run (
    Entdb_storage.Sqlite.get_entity_data conn missing_id >>= function
    | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
    | Ok None -> Lwt.return_unit
    | Ok (Some _) -> Lwt.fail_with "should not have found anything")

let () =
  Alcotest.run "entdb_storage" [
    "entity_definition", [
      Alcotest.test_case "create database"        `Quick test_create_database;
      Alcotest.test_case "round-trip"             `Quick test_definition_round_trip;
      Alcotest.test_case "not found returns none" `Quick test_definition_not_found;
    ];
    "entity_data", [
      Alcotest.test_case "round-trip"             `Quick test_entity_data_round_trip;
      Alcotest.test_case "not found returns none" `Quick test_entity_data_not_found;
    ];
  ]
