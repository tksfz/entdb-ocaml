module type S = sig
  module Id : Entdb_data.Entity_id.S
  type t
  val name : string
  val description : string option
  val primary_key_field : string
  val yojson_of_t : t -> Yojson.Safe.t
  val t_of_yojson : Yojson.Safe.t -> t
end
