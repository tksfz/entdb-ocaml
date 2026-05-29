open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module type PREFIX = sig
  val type_id_prefix : string
end

module type S = sig
  type t

  val type_id_prefix : string
  val yojson_of_t : t -> Yojson.Safe.t
  val t_of_yojson : Yojson.Safe.t -> t
  val to_string : t -> string
  val of_string : string -> (t, string) result
  val prefix : t -> string
  val eq : t -> t -> bool
  val create : unit -> t
  val validate : t -> (unit, string) result
end

module Make (P : PREFIX) : S = struct
  type t = Type_id.t

  let type_id_prefix = P.type_id_prefix

  let yojson_of_t id = Type_id.yojson_of_t id
  let t_of_yojson json = Type_id.t_of_yojson json

  let to_string id = Type_id.to_string id
  let prefix id = Type_id.prefix id

  let eq = Type_id.eq

  let create () = Type_id.create_v7 P.type_id_prefix

  let validate id =
    let p = Type_id.prefix id in
    if String.equal p P.type_id_prefix then
      Ok ()
    else
      Error (Printf.sprintf "Invalid TypeId prefix: expected '%s', got '%s'" P.type_id_prefix p)

  let of_string str =
    match Type_id.of_string str with
    | Ok id -> (
        match validate id with
        | Ok () -> Ok id
        | Error e -> Error e)
    | Error e -> Error e
end
