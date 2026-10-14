open! Core
open Org_access
open Fixtures
module D = Role_model.Default

let decide ?(organisation = Fixtures.organisation ()) membership action =
  Authorize.decide Role_model.default ~organisation ~membership action
;;

let show d =
  print_s
    [%sexp
      (d : Authorize.Decision.t)
      , ((match d with
          | Allowed _ -> "allowed"
          | Denied r -> Reason.code r)
         : string)]
;;

let%expect_test "the checks in order" =
  let approver = member "bea" D.approver in
  show (decide None Action.read);
  show (decide (Some (member ~org:other_org_id "zoe" D.admin)) Action.read);
  show
    (decide
       ~organisation:(organisation ~status:Suspended ())
       (Some (member "ana" D.admin))
       Action.read);
  show (decide (Some (member "old" (Role.of_string "owner"))) Action.read);
  show (decide (Some approver) (Action.requires D.manage_members));
  show (decide (Some approver) (Action.requires_verified D.create_payments));
  show
    (decide
       ~organisation:(organisation ~verified:false ())
       (Some approver)
       (Action.requires_verified D.approve_payments));
  show
    (decide
       ~organisation:(organisation ~verified:false ())
       (Some (member "ana" D.admin))
       (Action.requires D.manage_members));
  show (decide (Some approver) (Action.requires_verified D.approve_payments));
  show (decide (Some (member "vic" D.viewer)) Action.read);
  [%expect
    {|
    ((Denied Not_a_member) not_a_member)
    ((Denied Other_organisation) other_organisation)
    ((Denied Organisation_suspended) organisation_suspended)
    ((Denied (Unknown_role owner)) unknown_role)
    ((Denied
      (Permission_missing (role approver) (permission members.manage)
       (required (admin))))
     role_required)
    ((Denied
      (Permission_missing (role approver) (permission payments.create)
       (required (operator))))
     role_required)
    ((Denied Verification_required) verification_required)
    ((Allowed (role admin)) allowed)
    ((Allowed (role approver)) allowed)
    ((Allowed (role viewer)) allowed)
    |}]
;;

let%expect_test "an outsider learns nothing about a suspended organisation" =
  show
    (decide
       ~organisation:(organisation ~status:Suspended ~verified:false ())
       (Some (member ~org:other_org_id "zoe" D.admin))
       (Action.requires_verified D.approve_payments));
  [%expect {| ((Denied Other_organisation) other_organisation) |}]
;;

let%expect_test "codes" =
  print_s [%sexp (Reason.all_codes : string list)];
  [%expect
    {|
    (not_a_member other_organisation organisation_suspended unknown_role
     role_required verification_required)
    |}]
;;

(* Over every role of the default model, every declared permission and every state of the
   organisation: [decide] allows exactly when the model allows and the organisation's
   flags permit, and a denial for another organisation never depends on the action. *)
let%test_unit "decide agrees with the model" =
  let model = Role_model.default in
  let roles = Role_model.roles model in
  let actions =
    Action.read
    :: List.concat_map (Role_model.permissions model) ~f:(fun p ->
      [ Action.requires p; Action.requires_verified p ])
  in
  let gen =
    let open Quickcheck.Generator.Let_syntax in
    let%map role = Quickcheck.Generator.of_list roles
    and action = Quickcheck.Generator.of_list actions
    and verified = Bool.quickcheck_generator
    and suspended = Bool.quickcheck_generator
    and same_org = Bool.quickcheck_generator in
    role, action, verified, suspended, same_org
  in
  Quickcheck.test
    gen
    ~sexp_of:[%sexp_of: Role.t * Action.t * bool * bool * bool]
    ~f:(fun (role, (action : Action.t), verified, suspended, same_org) ->
      let organisation =
        organisation ~verified ~status:(if suspended then Suspended else Active) ()
      in
      let org = if same_org then org_id else other_org_id in
      let d = decide ~organisation (Some (member ~org "m" role)) action in
      let expected =
        same_org
        && (not suspended)
        && Option.for_all action.permission ~f:(Role_model.allows model role)
        && ((not action.needs_verification) || verified)
      in
      [%test_result: bool] (Authorize.Decision.is_allowed d) ~expect:expected;
      if not same_org
      then [%test_result: Authorize.Decision.t] d ~expect:(Denied Other_organisation))
;;
