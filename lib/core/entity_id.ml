open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type 'a t = Type_id.t

let yojson_of_t _yojson_of_a id = Type_id.yojson_of_t id
let t_of_yojson _a_of_yojson json = Type_id.t_of_yojson json

let to_string id = Type_id.to_string id
let of_string str = Type_id.of_string str
let prefix id = Type_id.prefix id

let eq = Type_id.eq

let create (type a) (module E : Entity_trait.S with type t = a) =
  Type_id.create_v7 E.type_id_prefix
