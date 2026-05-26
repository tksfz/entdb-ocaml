open Entdb_core
open Entdb_entity

(* Scripts run in EntDB have access to Entdb_core and Entdb_entity modules.
   They can define new entities and register them using Entdb_sources.Harness.register. *)

type user = {
  id : string;
  name : string;
  email : string;
}

module User = struct
  type t = user
  let name = "User"
  let description = Some "A user entity defined in a source"
  let type_id_prefix = "usr"
  let primary_key_field = "id"
  
  (* Manual JSON conversion (PPX support in sources is a future improvement) *)
  let yojson_of_t t = 
    `Assoc [
      ("id", `String t.id); 
      ("name", `String t.name);
      ("email", `String t.email)
    ]
    
  let t_of_yojson json =
    let open Yojson.Safe.Util in
    { id = json |> member "id" |> to_string;
      name = json |> member "name" |> to_string;
      email = json |> member "email" |> to_string }
end

(* Register the entity so the harness can add it to the database *)
let () = Entdb_sources.Harness.register (module User)

let () = Printf.printf "Source: User entity defined and registered.\n"
