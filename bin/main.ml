open Cmdliner
open Lwt.Infix
open Entdb_core
open Entdb_storage
open Entdb_data
open Entdb_entity
open Entdb_script

module Api = Entdb_data.Api.Make(Entdb_storage.Sqlite)
module Script_runner = Entdb_script.Runner.Make(Entdb_storage.Sqlite)

type state = { db_path : string } [@@deriving yojson]

let save_state path =
  let state = { db_path = path } in
  let json = yojson_of_state state in
  let oc = open_out ".entdb-state" in
  Yojson.Safe.to_channel oc json;
  close_out oc;
  Ok ()

let load_state () =
  try
    let json = Yojson.Safe.from_file ".entdb-state" in
    Ok (state_of_yojson json)
  with _ ->
    Error "No database opened. Please run 'entdb schema open <file>' first."

let run_lwt f = Lwt_main.run f

(* Commands *)

let create_schema file =
  run_lwt (
    Printf.printf "Creating database at %s...\n" file;
    Entdb_storage.Sqlite.create_database file >>= function
    | Error e -> Lwt.return (Printf.printf "Error: %s\n" (Entdb_storage.Trait.error_to_string e))
    | Ok _ ->
        match save_state file with
        | Error e -> Lwt.return (Printf.printf "Error saving state: %s\n" e)
        | Ok () -> Lwt.return (Printf.printf "Database successfully created and set as active!\n")
  )

let open_schema file =
  run_lwt (
    Printf.printf "Opening database at %s...\n" file;
    Entdb_storage.Sqlite.open_database file >>= function
    | Error e -> Lwt.return (Printf.printf "Error: %s\n" (Entdb_storage.Trait.error_to_string e))
    | Ok _ ->
        match save_state file with
        | Error e -> Lwt.return (Printf.printf "Error saving state: %s\n" e)
        | Ok () -> Lwt.return (Printf.printf "Database successfully opened and set as active!\n")
  )

let add_entity file dbfile =
  run_lwt (
    let content_res =
      if file = "-" then
        let buf = Buffer.create 1024 in
        try
          while true do
            Buffer.add_string buf (input_line stdin);
            Buffer.add_char buf '\n'
          done;
          Ok (Buffer.contents buf)
        with End_of_file -> Ok (Buffer.contents buf)
      else
        try
          let ic = open_in file in
          let len = in_channel_length ic in
          let buf = really_input_string ic len in
          close_in ic;
          Ok buf
        with Sys_error e -> Error e
    in
    match content_res with
    | Error e -> Lwt.return (Printf.printf "Error reading file: %s\n" e)
    | Ok content -> (
        let db_path_res =
          match dbfile with
          | Some p -> Ok p
          | None -> (match load_state () with Ok s -> Ok s.db_path | Error e -> Error e)
        in
        match db_path_res with
        | Error e -> Lwt.return (Printf.printf "%s\n" e)
        | Ok db_path ->
            Printf.printf "Opening database at %s...\n" db_path;
            Entdb_storage.Sqlite.open_database db_path >>= function
            | Error e -> Lwt.return (Printf.printf "Error: %s\n" (Entdb_storage.Trait.error_to_string e))
            | Ok storage ->
                let api = Api.create storage in
                Printf.printf "Adding entity definition...\n";
                Api.add_entity_definition api content >>= function
                | Ok () -> Lwt.return (Printf.printf "Entity definition successfully added!\n")
                | Error e -> Lwt.return (Printf.printf "Error: %s\n" e)
    )
  )

let list_entities dbfile =
  run_lwt (
    let db_path_res =
      match dbfile with
      | Some p -> Ok p
      | None -> (match load_state () with Ok s -> Ok s.db_path | Error e -> Error e)
    in
    match db_path_res with
    | Error e -> Lwt.return (Printf.printf "%s\n" e)
    | Ok db_path ->
        Entdb_storage.Sqlite.open_database db_path >>= function
        | Error e -> Lwt.return (Printf.printf "Error: %s\n" (Entdb_storage.Trait.error_to_string e))
        | Ok storage ->
            let api = Api.create storage in
            Api.list_entity_definitions api >>= function
            | Ok json ->
                Lwt.return (Printf.printf "%s\n" (Yojson.Safe.pretty_to_string json))
            | Error e -> Lwt.return (Printf.printf "Error: %s\n" e)
  )

let put_entity_data entity file dbfile =
  run_lwt (
    let content_res =
      if file = "-" then
        let buf = Buffer.create 1024 in
        try
          while true do
            Buffer.add_string buf (input_line stdin);
            Buffer.add_char buf '\n'
          done;
          Ok (Buffer.contents buf)
        with End_of_file -> Ok (Buffer.contents buf)
      else
        try
          let ic = open_in file in
          let len = in_channel_length ic in
          let buf = really_input_string ic len in
          close_in ic;
          Ok buf
        with Sys_error e -> Error e
    in
    match content_res with
    | Error e -> Lwt.return (Printf.printf "Error reading file: %s\n" e)
    | Ok content -> (
        let db_path_res =
          match dbfile with
          | Some p -> Ok p
          | None -> (match load_state () with Ok s -> Ok s.db_path | Error e -> Error e)
        in
        match db_path_res with
        | Error e -> Lwt.return (Printf.printf "%s\n" e)
        | Ok db_path ->
            Printf.printf "Opening database at %s...\n" db_path;
            Entdb_storage.Sqlite.open_database db_path >>= function
            | Error e -> Lwt.return (Printf.printf "Error: %s\n" (Entdb_storage.Trait.error_to_string e))
            | Ok storage ->
                let api = Api.create storage in
                Printf.printf "Putting entity data...\n";
                Api.put_entity_data api entity content >>= function
                | Ok () -> Lwt.return (Printf.printf "Entity data successfully stored!\n")
                | Error e -> Lwt.return (Printf.printf "Error: %s\n" e)
    )
  )

let get_entity_data id dbfile =
  run_lwt (
    let db_path_res =
      match dbfile with
      | Some p -> Ok p
      | None -> (match load_state () with Ok s -> Ok s.db_path | Error e -> Error e)
    in
    match db_path_res with
    | Error e -> Lwt.return (Printf.printf "%s\n" e)
    | Ok db_path ->
        Printf.printf "Opening database at %s...\n" db_path;
        Entdb_storage.Sqlite.open_database db_path >>= function
        | Error e -> Lwt.return (Printf.printf "Error: %s\n" (Entdb_storage.Trait.error_to_string e))
        | Ok storage ->
            let api = Api.create storage in
            Api.get_entity_data api id >>= function
            | Ok (Some json) ->
                Lwt.return (Printf.printf "%s\n" (Yojson.Safe.pretty_to_string json))
            | Ok None ->
                Lwt.return (Printf.printf "Entity data not found for id: %s\n" id)
            | Error e -> Lwt.return (Printf.printf "Error: %s\n" e)
  )

let run_script file dbfile =
  run_lwt (
    let db_path_res =
      match dbfile with
      | Some p -> Ok p
      | None -> (match load_state () with Ok s -> Ok s.db_path | Error e -> Error e)
    in
    match db_path_res with
    | Error e -> Lwt.return (Printf.printf "%s\n" e)
    | Ok db_path ->
        Printf.printf "Opening database at %s...\n" db_path;
        Entdb_storage.Sqlite.open_database db_path >>= function
        | Error e -> Lwt.return (Printf.printf "Error: %s\n" (Entdb_storage.Trait.error_to_string e))
        | Ok storage ->
            let api = Api.create storage in
            Printf.printf "Running script %s...\n" file;
            Script_runner.execute_and_register api file >>= function
            | Ok () -> Lwt.return (Printf.printf "Script completed and entities registered!\n")
            | Error e -> Lwt.return (Printf.printf "Error running script: %s\n" e)
  )

(* Cmdliner terms *)

let file_arg =
  let doc = "Database file path" in
  Arg.(value & pos 0 string "entdb.sqlite" & info [] ~docv:"FILE" ~doc)

let create_cmd =
  let doc = "Create a new database schema" in
  let info = Cmd.info "create" ~doc in
  Cmd.v info Term.(const create_schema $ file_arg)

let open_cmd =
  let doc = "Open an existing database schema" in
  let info = Cmd.info "open" ~doc in
  Cmd.v info Term.(const open_schema $ file_arg)

let schema_default_help () =
  Printf.printf "Usage: entdb schema COMMAND [OPTIONS]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  create        Create a new database schema\n";
  Printf.printf "  open          Open an existing database schema\n\n";
  Printf.printf "Run `entdb schema COMMAND --help` for more information on a command.\n"

let schema_cmd =
  let doc = "Schema management" in
  let info = Cmd.info "schema" ~doc in
  let default = Term.(const schema_default_help $ const ()) in
  Cmd.group info ~default [create_cmd; open_cmd]

let dbfile_opt =
  let doc = "Database file path (overrides currently open database)" in
  Arg.(value & opt (some string) None & info ["d"; "dbfile"] ~docv:"DBFILE" ~doc)

let in_file_arg =
  let doc = "JSON file containing Entity Definition, or '-' for stdin" in
  Arg.(value & pos 0 string "-" & info [] ~docv:"FILE" ~doc)

let add_entity_cmd =
  let doc = "Add a new entity definition from a JSON blob" in
  let info = Cmd.info "add" ~doc in
  Cmd.v info Term.(const add_entity $ in_file_arg $ dbfile_opt)

let list_entities_cmd =
  let doc = "List all entity definitions" in
  let info = Cmd.info "list" ~doc in
  Cmd.v info Term.(const list_entities $ dbfile_opt)

let entities_default_help () =
  Printf.printf "Usage: entdb entities COMMAND [OPTIONS]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  add           Add a new entity definition from a JSON blob\n";
  Printf.printf "  list          List all entity definitions\n\n";
  Printf.printf "Run `entdb entities COMMAND --help` for more information on a command.\n"

let entities_cmd =
  let doc = "Entity definition management" in
  let info = Cmd.info "entities" ~doc in
  let default = Term.(const entities_default_help $ const ()) in
  Cmd.group info ~default [add_entity_cmd; list_entities_cmd]

let entity_name_arg =
  let doc = "Name of the entity definition" in
  Arg.(required & opt (some string) None & info ["e"; "entity"] ~docv:"ENTITY" ~doc)

let put_entity_data_cmd =
  let doc = "Put entity data from a JSON blob" in
  let info = Cmd.info "put" ~doc in
  Cmd.v info Term.(const put_entity_data $ entity_name_arg $ in_file_arg $ dbfile_opt)

let id_arg =
  let doc = "Entity ID" in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"ID" ~doc)

let get_entity_data_cmd =
  let doc = "Get entity data by ID" in
  let info = Cmd.info "get" ~doc in
  Cmd.v info Term.(const get_entity_data $ id_arg $ dbfile_opt)

let entity_data_default_help () =
  Printf.printf "Usage: entdb entity-data COMMAND [OPTIONS]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  put           Put entity data from a JSON blob\n";
  Printf.printf "  get           Get entity data by ID\n\n";
  Printf.printf "Run `entdb entity-data COMMAND --help` for more information on a command.\n"

let entity_data_cmd =
  let doc = "Entity data management" in
  let info = Cmd.info "entity-data" ~doc in
  let default = Term.(const entity_data_default_help $ const ()) in
  Cmd.group info ~default [put_entity_data_cmd; get_entity_data_cmd]

let script_file_arg =
  let doc = "OCaml script file" in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"SCRIPT" ~doc)

let run_script_cmd =
  let doc = "Run an OCaml script and register entities" in
  let info = Cmd.info "run" ~doc in
  Cmd.v info Term.(const run_script $ script_file_arg $ dbfile_opt)

let script_default_help () =
  Printf.printf "Usage: entdb script COMMAND [OPTIONS]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  run           Run an OCaml script and register entities\n\n";
  Printf.printf "Run `entdb script COMMAND --help` for more information on a command.\n"

let script_cmd =
  let doc = "Script management" in
  let info = Cmd.info "script" ~doc in
  let default = Term.(const script_default_help $ const ()) in
  Cmd.group info ~default [run_script_cmd]

let default_help () =
  Printf.printf "EntDB - A database for agents\n\n";
  Printf.printf "Usage: entdb COMMAND [OPTIONS]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  schema        Schema management\n";
  Printf.printf "  entities      Entity definition management\n";
  Printf.printf "  entity-data   Entity data management\n";
  Printf.printf "  script        Script management\n\n";
  Printf.printf "Run `entdb COMMAND --help` for more information on a command.\n"

let cmd =
  let doc = "EntDB CLI" in
  let info = Cmd.info "entdb" ~doc in
  let default = Term.(const default_help $ const ()) in
  Cmd.group info ~default [schema_cmd; entities_cmd; entity_data_cmd; script_cmd]

let () = exit (Cmd.eval cmd)
