type id_t = string

type task = {
  id : id_t; [@validate.custom fun _ -> Ok ()]
} [@@deriving validate]
