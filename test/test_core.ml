module User_id = Entdb_data.Entity_id.Make(struct let type_id_prefix = "usr" end)
module Task_id = Entdb_data.Entity_id.Make(struct let type_id_prefix = "tsk" end)

let test_type_id_prefix () =
  let id = Entdb_data.Type_id.create_v7 "usr" in
  Alcotest.(check string) "prefix" "usr" (Entdb_data.Type_id.prefix id)

let test_type_id_round_trip () =
  let id = Entdb_data.Type_id.create_v7 "usr" in
  let s = Entdb_data.Type_id.to_string id in
  match Entdb_data.Type_id.of_string s with
  | Error e -> Alcotest.fail e
  | Ok id2 -> Alcotest.(check bool) "eq" true (Entdb_data.Type_id.eq id id2)

let test_type_id_rejects_malformed () =
  Alcotest.(check bool) "error" true
    (Result.is_error (Entdb_data.Type_id.of_string "not-a-typeid"))

let test_type_id_rejects_bare_uuid () =
  Alcotest.(check bool) "error" true
    (Result.is_error (Entdb_data.Type_id.of_string "550e8400-e29b-41d4-a716-446655440000"))

let test_entity_id_prefix () =
  let id = User_id.create () in
  Alcotest.(check string) "prefix" "usr" (User_id.prefix id)

let test_entity_id_type_id_prefix () =
  Alcotest.(check string) "type_id_prefix" "usr" User_id.type_id_prefix

let test_entity_id_round_trip () =
  let id = User_id.create () in
  let s = User_id.to_string id in
  match User_id.of_string s with
  | Error e -> Alcotest.fail e
  | Ok id2 -> Alcotest.(check bool) "eq" true (User_id.eq id id2)

let test_entity_id_rejects_wrong_prefix () =
  let s = Task_id.to_string (Task_id.create ()) in
  Alcotest.(check bool) "error" true (Result.is_error (User_id.of_string s))

let test_entity_id_yojson_round_trip () =
  let id = User_id.create () in
  let id2 = User_id.t_of_yojson (User_id.yojson_of_t id) in
  Alcotest.(check bool) "eq" true (User_id.eq id id2)

let test_entity_id_yojson_rejects_wrong_prefix () =
  let json = Task_id.yojson_of_t (Task_id.create ()) in
  let raised =
    match User_id.t_of_yojson json with
    | _ -> false
    | exception Yojson.Json_error _ -> true
  in
  Alcotest.(check bool) "raises" true raised

let test_entity_id_validate_ok () =
  Alcotest.(check bool) "ok" true (Result.is_ok (User_id.validate (User_id.create ())))

let () =
  Alcotest.run "entdb_core" [
    "type_id", [
      Alcotest.test_case "has correct prefix"     `Quick test_type_id_prefix;
      Alcotest.test_case "round-trip via string"  `Quick test_type_id_round_trip;
      Alcotest.test_case "rejects malformed"      `Quick test_type_id_rejects_malformed;
      Alcotest.test_case "rejects bare uuid"      `Quick test_type_id_rejects_bare_uuid;
    ];
    "entity_id", [
      Alcotest.test_case "create has correct prefix"       `Quick test_entity_id_prefix;
      Alcotest.test_case "type_id_prefix constant"         `Quick test_entity_id_type_id_prefix;
      Alcotest.test_case "round-trip via string"           `Quick test_entity_id_round_trip;
      Alcotest.test_case "of_string rejects wrong prefix"  `Quick test_entity_id_rejects_wrong_prefix;
      Alcotest.test_case "yojson round-trip"               `Quick test_entity_id_yojson_round_trip;
      Alcotest.test_case "yojson rejects wrong prefix"     `Quick test_entity_id_yojson_rejects_wrong_prefix;
      Alcotest.test_case "validate ok for valid id"        `Quick test_entity_id_validate_ok;
    ];
  ]
