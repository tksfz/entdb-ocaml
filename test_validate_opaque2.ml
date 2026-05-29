module Task = struct
  type id_t = string

  let validate_id (id: id_t) = Ok ()

  type t = {
    id : id_t; [@validate.custom fun id -> validate_id id]
  } [@@deriving validate]
end
