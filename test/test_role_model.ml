open! Core
open Org_access
module D = Role_model.Default

let%expect_test "default model matrix" =
  let model = Role_model.default in
  List.iter (Role_model.roles model) ~f:(fun role ->
    print_s
      [%message
        ""
          (role : Role.t)
          ~rank:(Role_model.rank model role : int option)
          ~permissions:(Role_model.permissions_of model role : Permission.t list)]);
  print_s [%message "" ~custodian:(Role_model.custodian model : Permission.t)];
  [%expect
    {|
    ((role admin) (rank (0))
     (permissions
      (accounting.manage addresses.manage cards.manage cost_centres.manage export
       members.manage payees.manage payments.approve payments.create
       policy.manage rules.manage schedules.manage verification.manage)))
    ((role approver) (rank (1)) (permissions (export payments.approve)))
    ((role operator) (rank (2))
     (permissions
      (accounting.manage addresses.manage cards.manage cost_centres.manage export
       payees.manage payments.create rules.manage schedules.manage)))
    ((role viewer) (rank (3)) (permissions (export)))
    (custodian members.manage)
    |}]
;;

let%expect_test "lowest role holding a permission" =
  let model = Role_model.default in
  List.iter
    [ D.export; D.approve_payments; D.create_payments; D.manage_members ]
    ~f:(fun p ->
      print_s
        [%message
          "" ~_:(p : Permission.t) ~_:(Role_model.lowest_role_with model p : Role.t option)]);
  (* An undeclared permission is held only by [All] roles. *)
  let undeclared = Permission.of_string "something.else" in
  print_s [%sexp (Role_model.lowest_role_with model undeclared : Role.t option)];
  print_s [%sexp (Role_model.allows model D.admin undeclared : bool)];
  print_s [%sexp (Role_model.allows model (Role.of_string "ghost") D.export : bool)];
  [%expect
    {|
    (export (viewer))
    (payments.approve (approver))
    (payments.create (operator))
    (members.manage (admin))
    (admin)
    true
    false
    |}]
;;

let%expect_test "model validation" =
  let p = Permission.of_string in
  let r = Role.of_string in
  let try_ ~permissions ~custodian roles =
    print_s
      [%sexp
        (Role_model.create ~permissions ~custodian roles |> Or_error.map ~f:ignore
         : unit Or_error.t)]
  in
  try_ ~permissions:[ p "a" ] ~custodian:(p "a") [];
  try_ ~permissions:[ p "a" ] ~custodian:(p "a") [ r "x", All; r "x", Only [] ];
  try_ ~permissions:[ p "a" ] ~custodian:(p "a") [ r "x", All; r "y", Only [ p "b" ] ];
  try_ ~permissions:[ p "a" ] ~custodian:(p "c") [ r "x", All ];
  try_ ~permissions:[ p "a"; p "b" ] ~custodian:(p "a") [ r "x", Only [ p "b" ] ];
  try_ ~permissions:[ p "a" ] ~custodian:(p "a") [ r "x", Only [ p "a" ] ];
  [%expect
    {|
    (Error "role model has no roles")
    (Error ("role listed twice" (role x)))
    (Error ("role grants an undeclared permission" (undeclared ((y b)))))
    (Error ("custodian permission is not declared" (custodian c)))
    (Error ("no role holds the custodian permission" (custodian a)))
    (Ok ())
    |}]
;;

let%expect_test "decoding a model runs the checks" =
  let sexp =
    Sexp.of_string "((roles ((x (Only (b))))) (permissions (a b)) (custodian a))"
  in
  print_s
    [%sexp
      (Or_error.try_with (fun () -> Role_model.Stable.V1.t_of_sexp sexp)
       |> Or_error.map ~f:ignore
       : unit Or_error.t)];
  let round_trip =
    Role_model.Stable.V1.t_of_sexp (Role_model.Stable.V1.sexp_of_t Role_model.default)
  in
  print_s [%sexp (Role_model.equal round_trip Role_model.default : bool)];
  [%expect
    {|
    (Error ("no role holds the custodian permission" (custodian a)))
    true
    |}]
;;
