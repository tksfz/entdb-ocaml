open Cmdliner
open Lwt.Infix
open Entdb_core
open Entdb_storage
open Entdb_data_api
open Entdb_entity_api
open Entdb_sources

module Api = Entdb_data_api.Api.Make(Entdb_storage.Sqlite)
module Source_runner = Entdb_sources.Runner.Make(Entdb_storage.Sqlite)

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

(* Pre-parse for dynamic commands *)
let pre_parse_args () =
  let dbfile = ref None in
  let source = ref None in
  let ppx = ref false in
  let rec parse i =
    if i < Array.length Sys.argv then
      let arg = Sys.argv.(i) in
      if String.starts_with ~prefix:"--dbfile=" arg then (
        dbfile := Some (String.sub arg 9 (String.length arg - 9));
        parse (i + 1)
      ) else if arg = "--dbfile" || arg = "-d" then (
        if i + 1 < Array.length Sys.argv then dbfile := Some Sys.argv.(i + 1);
        parse (i + 2)
      ) else if String.starts_with ~prefix:"--source=" arg then (
        source := Some (String.sub arg 9 (String.length arg - 9));
        parse (i + 1)
      ) else if arg = "--source" || arg = "-s" then (
        if i + 1 < Array.length Sys.argv then source := Some Sys.argv.(i + 1);
        parse (i + 2)
      ) else if arg = "--ppx" then (
        ppx := true;
        parse (i + 1)
      ) else parse (i + 1)
  in
  parse 1;
  (!dbfile, !source, !ppx)

let clean_argv () =
  let rec filter acc i =
    if i >= Array.length Sys.argv then Array.of_list (List.rev acc)
    else
      let arg = Sys.argv.(i) in
      if String.starts_with ~prefix:"--source=" arg then filter acc (i + 1)
      else if arg = "--source" || arg = "-s" then filter acc (i + 2)
      else if String.starts_with ~prefix:"--dbfile=" arg then filter acc (i + 1)
      else if arg = "--dbfile" || arg = "-d" then filter acc (i + 2)
      else filter (arg :: acc) (i + 1)
  in
  filter [] 0

let get_dynamic_entities dbfile source_opt ppx =
  let db_path_res =
    match dbfile with
    | Some p -> Ok p
    | None -> (match load_state () with Ok s -> Ok s.db_path | Error e -> Error e)
  in
  match db_path_res with
  | Error _ -> []
  | Ok db_path ->
      Lwt_main.run (
        Entdb_storage.Sqlite.open_database db_path >>= function
        | Error _ -> Lwt.return []
        | Ok storage ->
            let api = Api.create storage in
            (match source_opt with
             | Some f -> Source_runner.execute_and_register ~ppx api f >>= fun _ -> Lwt.return_unit
             | None -> Lwt.return_unit) >>= fun () ->
            
            Entdb_storage.Sqlite.get_all_entity_definitions storage >>= function
            | Error _ -> Lwt.return []
            | Ok defs -> Lwt.return (List.map (fun d -> d.Entdb_core.Entity_definition.name) defs)
      )

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

let run_source file dbfile ppx =
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
            Printf.printf "Running source %s...\n" file;
            Source_runner.execute_and_register ~ppx api file >>= function
            | Ok () -> Lwt.return (Printf.printf "Source completed and entities registered!\n")
            | Error e -> Lwt.return (Printf.printf "Error running source: %s\n" e)
  )

(* Cmdliner terms *)

let ppx_arg =
  let doc = "Enable PPX preprocessing for the source file" in
  Arg.(value & flag & info ["ppx"] ~doc)

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
  let doc = "Create and open schema database files" in
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
  let doc = "Add new entity types or manage existing ones" in
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
  let doc = "Low-level entity data CRUD" in
  let info = Cmd.info "entity-data" ~doc ~docs:Cmdliner.Manpage.s_none in
  let default = Term.(const entity_data_default_help $ const ()) in
  Cmd.group info ~default [put_entity_data_cmd; get_entity_data_cmd]

let source_file_arg =
  let doc = "OCaml source file" in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"SOURCE" ~doc)

let run_source_cmd =
  let doc = "Run an OCaml source and register entities" in
  let info = Cmd.info "run" ~doc in
  Cmd.v info Term.(const run_source $ source_file_arg $ dbfile_opt $ ppx_arg)

let source_default_help () =
  Printf.printf "Usage: entdb source COMMAND [OPTIONS]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  run           Run an OCaml source and register entities\n\n";
  Printf.printf "Run `entdb source COMMAND --help` for more information on a command.\n"

let source_cmd =
  let doc = "Source management" in
  let info = Cmd.info "source" ~doc ~docs:Cmdliner.Manpage.s_none in
  let default = Term.(const source_default_help $ const ()) in
  Cmd.group info ~default [run_source_cmd]

(* Dynamic Entity Commands *)

let make_dynamic_entity_cmd entity_name =
  let doc = Printf.sprintf "Commands for entity %s" entity_name in
  let info = Cmd.info (String.lowercase_ascii entity_name) ~doc in
  
  let put_cmd =
    let doc = Printf.sprintf "Put data for %s" entity_name in
    let info = Cmd.info "put" ~doc in
    Cmd.v info Term.(const put_entity_data $ const entity_name $ in_file_arg $ dbfile_opt)
  in
  
  let get_cmd =
    let doc = Printf.sprintf "Get data for %s by ID" entity_name in
    let info = Cmd.info "get" ~doc in
    Cmd.v info Term.(const get_entity_data $ id_arg $ dbfile_opt)
  in
  
  let default_help () =
    Printf.printf "Usage: entdb entity %s COMMAND [OPTIONS]\n\n" (String.lowercase_ascii entity_name);
    Printf.printf "Commands:\n";
    Printf.printf "  put           Put data for %s from a JSON blob\n" entity_name;
    Printf.printf "  get           Get data for %s by ID\n\n" entity_name;
    Printf.printf "Run `entdb entity %s COMMAND --help` for more information on a command.\n" (String.lowercase_ascii entity_name)
  in
  let default = Term.(const default_help $ const ()) in
  
  Cmd.group info ~default [put_cmd; get_cmd]

let make_dynamic_entities_group names =
  let doc = "High-level entity data operations" in
  let info = Cmd.info "entity" ~doc in
  let subcmds = List.map make_dynamic_entity_cmd names in
  let default_help () =
    Printf.printf "Usage: entdb entity COMMAND [OPTIONS]\n\n";
    Printf.printf "Commands:\n";
    List.iter (fun name ->
      Printf.printf "  %-14s Commands for entity %s\n" (String.lowercase_ascii name) name
    ) names;
    Printf.printf "\nRun `entdb entity COMMAND --help` for more information on a command.\n"
  in
  let default = Term.(const default_help $ const ()) in
  Cmd.group info ~default subcmds

let default_help _names show_all =
  Printf.printf "EntDB - A database for agents\n\n";
  Printf.printf "Usage: entdb COMMAND [OPTIONS]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  %-14s Create and open schema database files\n" "schema";
  Printf.printf "  %-14s Add new entity types or manage existing ones\n" "entities";
  if show_all then (
    Printf.printf "  %-14s Low-level entity data CRUD\n" "entity-data";
    Printf.printf "  %-14s Source management\n" "source";
  );
  Printf.printf "  %-14s High-level entity data operations\n" "entity";
  Printf.printf "  %-14s Show help about commands\n" "help";
  Printf.printf "\nRun `entdb COMMAND --help` for more information on a command.\n"

let make_help_cmd dynamic_names =
  let doc = "Show help about commands" in
  let info = Cmd.info "help" ~doc in
  let show_all_arg =
    let doc = "Show all commands including plumbing commands" in
    Arg.(value & flag & info ["a"; "all"] ~doc)
  in
  let run show_all () = default_help dynamic_names show_all in
  Cmd.v info Term.(const run $ show_all_arg $ const ())

let () =
  let dbfile, source_opt, ppx = pre_parse_args () in
  let dynamic_names = get_dynamic_entities dbfile source_opt ppx in
  let new_argv = clean_argv () in
  
  let doc = "EntDB CLI" in
  let info = Cmd.info "entdb" ~doc in
  let run_default () = default_help dynamic_names false in
  let default = Term.(const run_default $ const ()) in
  
  let help_cmd = make_help_cmd dynamic_names in
  let base_cmds = [schema_cmd; entities_cmd; entity_data_cmd; source_cmd; help_cmd] in
  let all_cmds = make_dynamic_entities_group dynamic_names :: base_cmds in
  
  let cmd = Cmd.group info ~default all_cmds in
  exit (Cmd.eval ~argv:new_argv cmd)
