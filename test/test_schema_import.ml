open Lwt.Infix

let run = Lwt_main.run

module Data_api = Entdb_data_api.Api.Make(Entdb_storage.Sqlite)

let make_api () =
  let path = Filename.temp_file "test_entdb_schema_import" ".sqlite" in
  Sys.remove path;
  run (
    Entdb_storage.Sqlite.create_database path >>= function
    | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
    | Ok storage -> Lwt.return (Data_api.create storage))

let write_tmp_file content =
  let path = Filename.temp_file "test_schema_source" ".ml" in
  let oc = open_out path in
  output_string oc content;
  close_out oc;
  path

let test_check_new_source () =
  let api = make_api () in
  let path = write_tmp_file "let () = ()" in
  run (
    Data_api.check_schema_source api path >>= function
    | Error e -> Lwt.fail_with e
    | Ok `Already_imported -> Lwt.fail_with "expected New, got Already_imported"
    | Ok (`New ss) ->
        Alcotest.(check string) "filename" (Filename.basename path) ss.Entdb_data.Schema_source.filename;
        Alcotest.(check string) "source" "let () = ()" ss.Entdb_data.Schema_source.source;
        Sys.remove path;
        Lwt.return_unit)

let test_check_already_imported () =
  let api = make_api () in
  let path = write_tmp_file "let x = 42" in
  run (
    Data_api.check_schema_source api path >>= function
    | Error e -> Lwt.fail_with e
    | Ok `Already_imported -> Lwt.fail_with "expected New on first check"
    | Ok (`New ss) ->
        Data_api.store_schema_source api ss >>= function
        | Error e -> Lwt.fail_with e
        | Ok () ->
            Data_api.check_schema_source api path >>= function
            | Error e -> Lwt.fail_with e
            | Ok `Already_imported -> Sys.remove path; Lwt.return_unit
            | Ok (`New _) -> Lwt.fail_with "expected Already_imported on second check")

let test_check_does_not_store () =
  (* Key run-before-store guarantee: check alone must not persist the source *)
  let api = make_api () in
  let path = write_tmp_file "let z = 99" in
  run (
    Data_api.check_schema_source api path >>= function
    | Error e -> Lwt.fail_with e
    | Ok `Already_imported -> Lwt.fail_with "expected New"
    | Ok (`New _) ->
        (* intentionally skip store_schema_source to simulate a failed run *)
        Data_api.get_all_schema_sources api >>= function
        | Error e -> Lwt.fail_with e
        | Ok sources ->
            Alcotest.(check int) "nothing stored after check alone" 0 (List.length sources);
            Sys.remove path;
            Lwt.return_unit)

let test_store_persists () =
  let api = make_api () in
  let path = write_tmp_file "let w = true" in
  run (
    Data_api.check_schema_source api path >>= function
    | Error e -> Lwt.fail_with e
    | Ok `Already_imported -> Lwt.fail_with "expected New"
    | Ok (`New ss) ->
        Data_api.store_schema_source api ss >>= function
        | Error e -> Lwt.fail_with e
        | Ok () ->
            Data_api.get_all_schema_sources api >>= function
            | Error e -> Lwt.fail_with e
            | Ok sources ->
                Alcotest.(check int) "one source stored" 1 (List.length sources);
                let stored = List.hd sources in
                Alcotest.(check string) "source content" "let w = true" stored.Entdb_data.Schema_source.source;
                Sys.remove path;
                Lwt.return_unit)

let test_missing_file_error () =
  let api = make_api () in
  run (
    Data_api.check_schema_source api "/nonexistent/path/schema.ml" >>= function
    | Error _ -> Lwt.return_unit
    | Ok _ -> Lwt.fail_with "expected Error for missing file")

let () =
  Alcotest.run "entdb_schema_import" [
    "check_schema_source", [
      Alcotest.test_case "new source returns New"          `Quick test_check_new_source;
      Alcotest.test_case "duplicate returns Already_imported" `Quick test_check_already_imported;
      Alcotest.test_case "check alone does not store"      `Quick test_check_does_not_store;
      Alcotest.test_case "missing file returns Error"      `Quick test_missing_file_error;
    ];
    "store_schema_source", [
      Alcotest.test_case "store persists the record"       `Quick test_store_persists;
    ];
  ]
