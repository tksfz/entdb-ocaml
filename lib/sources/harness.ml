open Entdb_entity

let registered_entities : (module Trait.S) list ref = ref []

let register (module E : Trait.S) =
  registered_entities := (module E : Trait.S) :: !registered_entities

let get_registered () =
  let res = !registered_entities in
  registered_entities := [];
  List.rev res
