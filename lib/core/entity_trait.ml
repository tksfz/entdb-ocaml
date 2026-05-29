module type S = sig
  module Id : Entity_id.S
  type t
  val name : string
  val description : string option
  val type_id_prefix : string
  val primary_key_field : string
  val yojson_of_t : t -> Yojson.Safe.t
  val t_of_yojson : Yojson.Safe.t -> t
end
