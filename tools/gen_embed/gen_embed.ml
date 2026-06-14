let () =
  if Array.length Sys.argv < 2 then (
    Printf.eprintf "Usage: gen_embed output.ml package ...\n";
    exit 1
  );
  let out_file = Sys.argv.(1) in
  Findlib.init ();
  let oc = open_out out_file in
  Printf.fprintf oc "let files : (string * string) list = [\n";
  for i = 2 to Array.length Sys.argv - 1 do
    let pkg = Sys.argv.(i) in
    let dir = Findlib.package_directory pkg in
    let entries = Sys.readdir dir in
    Array.sort String.compare entries;
    Array.iter (fun fname ->
      if Filename.check_suffix fname ".cmi" then begin
        let path = Filename.concat dir fname in
        let ic = open_in_bin path in
        let n = in_channel_length ic in
        let data = Bytes.create n in
        really_input ic data 0 n;
        close_in ic;
        Printf.fprintf oc "  (%S, %S);\n" fname (Bytes.to_string data)
      end
    ) entries
  done;
  Printf.fprintf oc "]\n\nlet find name = List.assoc_opt name files\n";
  close_out oc
