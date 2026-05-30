module User = struct
  module Id = Entdb_data.Entity_id.Make(struct let type_id_prefix = "usr" end)

  type t = {
    id : Id.t;
    name : string;
  }

  let name = "User"
  let description = None
  let primary_key_field = "id"

  let yojson_of_t t =
    `Assoc [("id", Id.yojson_of_t t.id); ("name", `String t.name)]

  let t_of_yojson json =
    let open Yojson.Safe.Util in
    { id = Id.t_of_yojson (json |> member "id");
      name = json |> member "name" |> to_string }
end

let test_register_and_retrieve () =
  Entdb_sources.Harness.register (module User);
  let registered = Entdb_sources.Harness.get_registered () in
  Alcotest.(check int) "count" 1 (List.length registered);
  let (module E : Entdb_entity.Entity_trait.S) = List.hd registered in
  Alcotest.(check string) "name" "User" E.name

let test_get_registered_clears () =
  Entdb_sources.Harness.register (module User);
  let _ = Entdb_sources.Harness.get_registered () in
  let registered = Entdb_sources.Harness.get_registered () in
  Alcotest.(check int) "empty after get" 0 (List.length registered)

let () =
  Alcotest.run "entdb_sources" [
    "harness", [
      Alcotest.test_case "register and retrieve"       `Quick test_register_and_retrieve;
      Alcotest.test_case "get_registered clears registry" `Quick test_get_registered_clears;
    ];
  ]
