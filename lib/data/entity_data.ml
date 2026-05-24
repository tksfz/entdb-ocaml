open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type json = Yojson.Safe.t

let yojson_of_json (j : json) = j
let json_of_yojson (j : json) = j

type t = {
  id : Type_id.t;
  entity_definition_id : Entity_definition.id;
  data : json;
} [@@deriving yojson]

let create (definition : Entity_definition.t) data =
  {
    id = Type_id.create_v7 definition.type_id_prefix;
    entity_definition_id = definition.id;
    data;
  }
