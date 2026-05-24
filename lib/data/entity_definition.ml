open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type id = Type_id.t [@@deriving yojson]

let create_id () =
  Type_id.create_v7 "ent_entity"

type t = {
  id : id;
  name : string;
  description : string option;
  type_id_prefix : string;
  primary_key_field : string;
} [@@deriving yojson]
