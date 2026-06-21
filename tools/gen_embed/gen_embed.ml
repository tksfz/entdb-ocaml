let is_existing_dir path =
  try Sys.is_directory path
  with Sys_error _ -> false

let is_existing_file path =
  try Sys.file_exists path && not (Sys.is_directory path)
  with Sys_error _ -> false

let embed_suffixes = [".cmi"]

let should_embed fname =
  List.exists (fun sfx -> Filename.check_suffix fname sfx) embed_suffixes

let embed_file path oc =
  let fname = Filename.basename path in
  if should_embed fname then begin
    let ic = open_in_bin path in
    let n = in_channel_length ic in
    let data = Bytes.create n in
    really_input ic data 0 n;
    close_in ic;
    Printf.fprintf oc "  (%S, %S);\n" fname (Bytes.to_string data)
  end

let embed_dir dir oc =
  let entries = Sys.readdir dir in
  Array.sort String.compare entries;
  Array.iter (fun fname ->
    embed_file (Filename.concat dir fname) oc
  ) entries

let embed_package pkg oc =
  let dir = Findlib.package_directory pkg in
  embed_dir dir oc

let () =
  if Array.length Sys.argv < 2 then (
    Printf.eprintf "Usage: gen_embed output.ml (--dir PATH | package) ...\n";
    exit 1
  );
  let out_file = Sys.argv.(1) in
  Findlib.init ();
  let oc = open_out out_file in
  Printf.fprintf oc "let files : (string * string) list = [\n";
  let rec process i =
    if i >= Array.length Sys.argv then ()
    else match Sys.argv.(i) with
    | "--dir" ->
        if i + 1 >= Array.length Sys.argv then (
          Printf.eprintf "gen_embed: --dir requires a path\n";
          exit 1
        );
        embed_dir Sys.argv.(i + 1) oc;
        process (i + 2)
    | arg when is_existing_dir arg ->
        embed_dir arg oc;
        process (i + 1)
    | arg when is_existing_file arg ->
        embed_file arg oc;
        process (i + 1)
    | pkg ->
        embed_package pkg oc;
        process (i + 1)
  in
  process 2;
  Printf.fprintf oc "]\n\nlet find name = List.assoc_opt name files\n";
  close_out oc
