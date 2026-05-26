open Lwt.Infix

let run_source file =
  try
    (* Initialize findlib to find external package paths *)
    Findlib.init ();
    
    (* Initialize the toplevel environment *)
    Toploop.initialize_toplevel_env ();
    
    (* Add Dune build paths for our libraries so source can 'open' them.
       We point to the .objs/byte directories where the .cmi files live. *)
    let cwd = Sys.getcwd () in
    let internal_libs = [
      "_build/default/lib/core/.entdb_core.objs/byte";
      "_build/default/lib/storage/.entdb_storage.objs/byte";
      "_build/default/lib/data/.entdb_data.objs/byte";
      "_build/default/lib/entity/.entdb_entity.objs/byte";
      "_build/default/lib/sources/.entdb_sources.objs/byte";
    ] in
    List.iter (fun d -> 
      let path = Filename.concat cwd d in
      if Sys.file_exists path && Sys.is_directory path then
        Topdirs.dir_directory path
    ) internal_libs;
    
    (* Add common external library paths *)
    let external_libs = ["yojson"; "uuidm"; "lwt"] in
    List.iter (fun lib ->
      try Topdirs.dir_directory (Findlib.package_directory lib)
      with _ -> ()
    ) external_libs;
    
    let success = Toploop.use_file Format.std_formatter file in
    if success then
      Ok (Harness.get_registered ())
    else
      Error "Source execution failed (see stderr for details)"
  with e ->
    Error (Printf.sprintf "Exception during source execution: %s" (Printexc.to_string e))

module Make (S : Entdb_storage.Trait.S) = struct
  module Data_api = Entdb_data.Api.Make(S)
  module Entity_api = Entdb_entity.Api.Make(Data_api)

  let execute_and_register api_handle source_file =
    match run_source source_file with
    | Error e -> Lwt.return (Error e)
    | Ok entities ->
        let rec register_all = function
          | [] -> Lwt.return (Ok ())
          | e :: rest ->
              Entity_api.register_entity api_handle e >>= function
              | Error msg -> Lwt.return (Error msg)
              | Ok () -> register_all rest
        in
        register_all entities
end
