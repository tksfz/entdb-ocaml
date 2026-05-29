module type Entity = sig
  type id_t
  val validate_id : id_t -> (unit, string) result
end
