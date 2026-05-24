type t = {
  prefix : string;
  uuid : Uuidm.t;
}

let create_v7 prefix =
  (* Since Uuidm doesn't have v7 natively, we'll use v4 for now to approximate the ID generation. *)
  let uuid = Uuidm.v4_gen (Random.State.make_self_init ()) () in
  { prefix; uuid }

let to_string t =
  Printf.sprintf "%s_%s" t.prefix (Uuidm.to_string ~upper:false t.uuid |> String.map (function '-' -> '_' | c -> c))

let of_string s =
  let len = String.length s in
  (* UUID with underscores has 32 chars + 4 underscores = 36 chars. *)
  if len > 37 && s.[len - 37] = '_' then
    let prefix = String.sub s 0 (len - 37) in
    let uuid_part = String.sub s (len - 36) 36 in
    let uuid_str = String.map (function '_' -> '-' | c -> c) uuid_part in
    match Uuidm.of_string uuid_str with
    | Some uuid -> Ok { prefix; uuid }
    | None -> Error "Invalid UUID format in TypeId"
  else
    Error "Invalid TypeId format"

let prefix t = t.prefix

let eq t1 t2 =
  String.equal t1.prefix t2.prefix && Uuidm.equal t1.uuid t2.uuid

let yojson_of_t t =
  Yojson.Safe.from_string ("\"" ^ (to_string t) ^ "\"")

let t_of_yojson = function
  | `String s ->
      (match of_string s with
       | Ok t -> t
       | Error e -> Yojson.json_error e)
  | _ -> Yojson.json_error "Expected string for TypeId"
