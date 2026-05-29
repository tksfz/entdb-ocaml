open Entdb_core
open Entdb_entity

module User = struct
  module Id = Entdb_core.Entity_id.Make(struct let type_id_prefix = "usr" end)
  
  type t = {
    id : Id.t;
    name : string;
    email : string;
  }

  let name = "User"
  let description = Some "A user entity defined in a source"
  let type_id_prefix = "usr"
  let primary_key_field = "id"
  
  let yojson_of_t t = 
    `Assoc [
      ("id", Id.yojson_of_t t.id); 
      ("name", `String t.name);
      ("email", `String t.email)
    ]
    
  let t_of_yojson json =
    let open Yojson.Safe.Util in
    { id = Id.t_of_yojson (json |> member "id");
      name = json |> member "name" |> to_string;
      email = json |> member "email" |> to_string }
end

let () = Entdb_sources.Harness.register (module User)

let () = Printf.printf "Source: User entity defined and registered.\n"