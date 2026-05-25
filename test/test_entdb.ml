open Lwt.Infix

module Api = Entdb_data.Api.Make(Entdb_storage.Sqlite)

let run_test () =
  let db_path = "test_entdb.sqlite" in
  (if Sys.file_exists db_path then Sys.remove db_path);
  
  Entdb_storage.Sqlite.create_database db_path >>= function
  | Error e -> Lwt.fail_with (Entdb_storage.Trait.error_to_string e)
  | Ok storage ->
      let api = Api.create storage in
      
      let def_payload = "{ \"name\": \"User\", \"description\": \"System user\", \"prefix\": \"usr\", \"primary_key_field\": \"id\" }" in
      Api.add_entity_definition api def_payload >>= function
      | Error e -> Lwt.fail_with e
      | Ok () ->
          
      Api.list_entity_definitions api >>= function
      | Error e -> Lwt.fail_with e
      | Ok defs ->
          let open Yojson.Safe.Util in
          let defs_list = defs |> to_list in
          assert (List.length defs_list = 1);
          let first = List.hd defs_list in
          assert ((first |> member "name" |> to_string) = "User");
          
          let put_payload = "{ \"id\": \"usr_abc-123\", \"name\": \"Thom\", \"level\": 42 }" in
          Api.put_entity_data api "User" put_payload >>= function
          | Ok () -> Lwt.fail_with "Should have failed due to invalid type ID"
          | Error _ -> (* Expected error *)
             
          (* Test with real generated prefix ID. But we have to generate one. *)
          let valid_id = Entdb_core.Type_id.to_string (Entdb_core.Type_id.create_v7 "usr") in
          let valid_payload = Printf.sprintf "{ \"id\": \"%s\", \"name\": \"Thom\", \"level\": 42 }" valid_id in
          
          Api.put_entity_data api "User" valid_payload >>= function
          | Error e -> Lwt.fail_with e
          | Ok () ->
              
          Api.get_entity_data api valid_id >>= function
          | Error e -> Lwt.fail_with e
          | Ok None -> Lwt.fail_with "Data not found"
          | Ok (Some json) ->
              assert ((json |> member "name" |> to_string) = "Thom");
              assert ((json |> member "level" |> to_int) = 42);
              Lwt.return_unit

let () =
  Lwt_main.run (run_test ())
