open Entdb_entity_api

let registered_entities : (module Entdb_core.Entity_trait.S) list ref = ref []

let register (module E : Entdb_core.Entity_trait.S) =
  registered_entities := (module E : Entdb_core.Entity_trait.S) :: !registered_entities

let get_registered () =
  let res = !registered_entities in
  registered_entities := [];
  List.rev res
