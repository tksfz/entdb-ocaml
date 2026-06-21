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

let cmi_dir = lazy (
  let tmp = Filename.temp_dir "entdb_cmis" "" in
  List.iter (fun (name, data) ->
    let oc = open_out_bin (Filename.concat tmp name) in
    output_string oc data;
    close_out oc
  ) Embedded_cmis.files;
  tmp
)

let init_embedded_findlib dir =
  let conf = Filename.concat dir "findlib.conf" in
  let oc = open_out conf in
  Printf.fprintf oc "destdir = %S\npath = %S\n" dir dir;
  close_out oc;
  Unix.putenv "OCAMLFIND_CONF" conf;
  Findlib.init ()

let run_source ~ppx file =
  try
    let lib_dir = Lazy.force cmi_dir in
    Topdirs.dir_directory lib_dir;
    init_embedded_findlib lib_dir;
    Toploop.initialize_toplevel_env ();
    if ppx then install_ppx_rewriter ();

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
