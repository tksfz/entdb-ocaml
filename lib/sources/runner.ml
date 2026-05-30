open Lwt.Infix

let install_ppx_rewriter () =
  let original_parse_use_file = !Toploop.parse_use_file in
  Toploop.parse_use_file := (fun lexbuf ->
    let phrases = original_parse_use_file lexbuf in
    List.map (fun ph ->
      match ph with
      | Parsetree.Ptop_def str ->
          let ppx_str = Ppxlib.Selected_ast.Of_ocaml.copy_structure str in
          let ppx_str_mapped = Ppxlib.Driver.map_structure ppx_str in
          let str_mapped = Ppxlib.Selected_ast.To_ocaml.copy_structure ppx_str_mapped in
          Parsetree.Ptop_def str_mapped
      | Parsetree.Ptop_dir _ as dir -> dir
    ) phrases
  )

let run_source ~ppx file =
  try
    (* Initialize findlib to find external package paths *)
    Findlib.init ();
    
    (* Initialize the toplevel environment *)
    Toploop.initialize_toplevel_env ();
    
    if ppx then install_ppx_rewriter ();
    
    (* Add Dune build paths for our libraries so source can 'open' them.
       We point to the .objs/byte directories where the .cmi files live. *)
    let cwd = Sys.getcwd () in
    let internal_libs = [
      "_build/default/lib/data/.entdb_data.objs/byte";
      "_build/default/lib/entity/.entdb_entity.objs/byte";
      "_build/default/lib/storage/.entdb_storage.objs/byte";
      "_build/default/lib/data_api/.entdb_data_api.objs/byte";
      "_build/default/lib/entity_api/.entdb_entity_api.objs/byte";
      "_build/default/lib/sources/.entdb_sources.objs/byte";
    ] in
    List.iter (fun d -> 
      let path = Filename.concat cwd d in
      if Sys.file_exists path && Sys.is_directory path then
        Topdirs.dir_directory path
    ) internal_libs;
    
    (* Add common external library paths *)
    let external_libs = ["yojson"; "uuidm"; "lwt"; "ppx_yojson_conv_lib"; "validate"] in
    List.iter (fun lib ->
      try Topdirs.dir_directory (Findlib.package_directory lib)
      with _ -> ()
    ) external_libs;
    
    let null_fmt = Format.make_formatter (fun _ _ _ -> ()) (fun () -> ()) in
    let success = Toploop.use_file null_fmt file in
    if success then
      Ok (Harness.get_registered ())
    else
      Error "Source execution failed (see stderr for details)"
  with e ->
    Error (Printf.sprintf "Exception during source execution: %s" (Printexc.to_string e))

module Make (S : Entdb_storage.Trait.S) = struct
  module Data_api = Entdb_data_api.Api.Make(S)
  module Entity_api = Entdb_entity_api.Api.Make(Data_api)

  let execute_and_register ?(ppx=false) api_handle source_file =
    match run_source ~ppx source_file with
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
let _ = Ppx_yojson_conv.yojson_of
