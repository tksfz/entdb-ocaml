let () =
  if Array.length Sys.argv < 2 then (
    Printf.eprintf "Usage: gen_embed output.ml name=path ...\n";
    exit 1
  );
  let out_file = Sys.argv.(1) in
  let oc = open_out out_file in
  Printf.fprintf oc "let files : (string * string) list = [\n";
  for i = 2 to Array.length Sys.argv - 1 do
    let arg = Sys.argv.(i) in
    match String.split_on_char '=' arg with
    | [name; path] ->
        let ic = open_in_bin path in
        let n = in_channel_length ic in
        let data = Bytes.create n in
        really_input ic data 0 n;
        close_in ic;
        Printf.fprintf oc "  (%S, %S);\n" name (Bytes.to_string data)
    | _ ->
        Printf.eprintf "Expected name=path, got: %s\n" arg;
        exit 1
  done;
  Printf.fprintf oc "]\n\nlet find name = List.assoc_opt name files\n";
  close_out oc
