open! Core
open Money
open Org_access
open Fixtures
module D = Role_model.Default

let model = Role_model.default
let policy = Approval_policy.four_eyes ~above:[ Amount.of_string "10000.00 EUR" ]
let action = Action.requires_verified D.approve_payments
let org = organisation ()
let ana = member "ana" D.admin
let bea = member "bea" D.approver
let cal = member "cal" D.approver
let olu = member "olu" D.operator
let vic = member "vic" D.viewer
let team = [ ana; bea; cal; olu; vic ]

let open_ ?(maker = olu) ?(members = team) amounts =
  Approval.open_
    model
    policy
    ~id:(Approval_id.of_string "apr-1")
    ~organisation:org
    ~maker
    ~subject:"payout-batch:42"
    ~action
    ~amounts:(List.map amounts ~f:Amount.of_string)
    ~members
    ~at:t0
    ()
;;

let show_error e = print_s [%message (e : Approval.Error.t) ~code:(Approval.Error.code e)]

let approve ?note t m =
  match Approval.approve t model ~organisation:org ~membership:(Some m) ?note ~at:(at 5) () with
  | Ok (t, progress) ->
    print_s [%sexp (progress : Approval.Progress.t)];
    t
  | Error e ->
    show_error e;
    t
;;

let%expect_test "two distinct checkers above the threshold" =
  let t = open_ [ "6000.00 EUR"; "6000.00 EUR" ] |> Result.ok |> Option.value_exn in
  print_s [%message "" ~required:(t.required : int) ~remaining:(Approval.remaining t : int)];
  let t = approve t olu in
  let t = approve t vic in
  let t = approve t bea in
  let t = approve t bea in
  print_s [%sexp (Approval.can_approve t model ~organisation:org ~membership:(Some cal) : bool)];
  let t = approve ~note:"  checked   the invoices " t cal in
  let t = approve t ana in
  print_s [%sexp (t : Approval.t)];
  [%expect
    {|
    ((required 2) (remaining 2))
    ((e
      (Denied
       (Permission_missing (role operator) (permission payments.approve)
        (required (approver)))))
     (code role_required))
    ((e
      (Denied
       (Permission_missing (role viewer) (permission payments.approve)
        (required (approver)))))
     (code role_required))
    (Recorded (approvals 1) (required 2))
    ((e Already_approved) (code already_approved))
    true
    Completed
    ((e (Not_pending Approved)) (code not_pending))
    ((id apr-1) (org org-1) (subject payout-batch:42)
     (action ((permission (payments.approve)) (needs_verification true)))
     (maker olu) (amounts ("6000.00 EUR" "6000.00 EUR")) (required 2)
     (approvals
      (((by bea) (at "2027-03-01 09:05:00Z") (note ()))
       ((by cal) (at "2027-03-01 09:05:00Z") (note ("checked the invoices")))))
     (status Approved) (decision ()) (created_at "2027-03-01 09:00:00Z")
     (version 2))
    |}]
;;

let%expect_test "an admin who makes a request cannot check it" =
  let t = open_ ~maker:ana [ "50.00 EUR" ] |> Result.ok |> Option.value_exn in
  let t = approve t ana in
  let (_ : Approval.t) = approve t bea in
  [%expect
    {|
    ((e Own_request) (code own_request))
    Completed
    |}]
;;

let%expect_test "opening refuses a request nobody could approve" =
  let show r = Result.iter_error r ~f:show_error in
  show (open_ ~members:[ olu; bea; vic ] [ "20000.00 EUR" ]);
  (* The maker is excluded even when they hold the permission. *)
  show (open_ ~maker:bea ~members:[ olu; bea; cal ] [ "20000.00 EUR" ]);
  show (open_ ~maker:(member ~org:other_org_id "zed" D.admin) [ "1.00 EUR" ]);
  show (open_ ~members:[ olu; bea ] [ "1.00 EUR" ]);
  [%expect
    {|
    ((e (Not_enough_approvers (required 2) (eligible 1)))
     (code not_enough_approvers))
    ((e (Not_enough_approvers (required 2) (eligible 1)))
     (code not_enough_approvers))
    ((e (Denied Other_organisation)) (code other_organisation))
    |}]
;;

let%expect_test "unverified organisation" =
  let t = open_ [ "1.00 EUR" ] |> Result.ok |> Option.value_exn in
  Approval.approve
    t
    model
    ~organisation:(organisation ~verified:false ())
    ~membership:(Some bea)
    ~at:(at 1)
    ()
  |> Result.iter_error ~f:show_error;
  [%expect
    {| ((e (Denied Verification_required)) (code verification_required)) |}]
;;

let%expect_test "reject and cancel" =
  let t = open_ [ "20000.00 EUR" ] |> Result.ok |> Option.value_exn in
  let show r =
    match r with
    | Ok (t : Approval.t) ->
      print_s
        [%message
          "" ~status:(t.status : Approval.Status.t) ~decision:(t.decision : Approval.Vote.t option)]
    | Error e -> show_error e
  in
  let t1 = approve t bea in
  show (Approval.reject t1 model ~organisation:org ~membership:(Some olu) ~at:(at 9) ());
  show
    (Approval.reject
       t1
       model
       ~organisation:org
       ~membership:(Some bea)
       ~note:"wrong IBAN"
       ~at:(at 9)
       ());
  show (Approval.cancel t model ~organisation:org ~membership:(Some bea) ~at:(at 9) ());
  show
    (Approval.cancel
       t
       model
       ~organisation:org
       ~membership:(Some ana)
       ~override:D.manage_members
       ~at:(at 9)
       ());
  show (Approval.cancel t model ~organisation:org ~membership:(Some olu) ~at:(at 9) ());
  [%expect
    {|
    (Recorded (approvals 1) (required 2))
    ((e
      (Denied
       (Permission_missing (role operator) (permission payments.approve)
        (required (approver)))))
     (code role_required))
    ((status Rejected)
     (decision (((by bea) (at "2027-03-01 09:09:00Z") (note ("wrong IBAN"))))))
    ((e Not_canceller) (code not_canceller))
    ((status Cancelled)
     (decision (((by ana) (at "2027-03-01 09:09:00Z") (note ())))))
    ((status Cancelled)
     (decision (((by olu) (at "2027-03-01 09:09:00Z") (note ())))))
    |}]
;;

(* Random members try random transitions on one request. Whatever happens: approvals are
   distinct, never from the maker, only from members allowed to approve; the request is
   approved exactly when it has [required] of them; the version counts the successful
   transitions; a finished request never changes again. *)
let%test_unit "approval invariants" =
  let members =
    List.concat_map [ D.admin; D.approver; D.operator; D.viewer ] ~f:(fun role ->
      List.init 2 ~f:(fun i -> member (sprintf "%s%d" (Role.to_string role) i) role))
  in
  let gen =
    let open Quickcheck.Generator.Let_syntax in
    let%bind maker = Quickcheck.Generator.of_list members in
    let%bind cents = Int.gen_incl 0 3_000_000 in
    let%map steps =
      List.gen_with_length
        12
        (Quickcheck.Generator.both
           (Quickcheck.Generator.of_list members)
           (Int.gen_incl 0 9))
    in
    maker, cents, steps
  in
  Quickcheck.test
    gen
    ~sexp_of:[%sexp_of: Member.t * int * (Member.t * int) list]
    ~f:(fun (maker, cents, steps) ->
      match
        Approval.open_
          model
          policy
          ~id:(Approval_id.of_string "q")
          ~organisation:org
          ~maker
          ~subject:"s"
          ~action
          ~amounts:[ Amount.of_minor_units_int Currency.eur cents ]
          ~at:t0
          ()
      with
      | Error _ -> assert false
      | Ok t ->
        let final, successes =
          List.fold steps ~init:(t, 0) ~f:(fun (t, n) (m, dice) ->
            let membership = Some m in
            let result =
              if dice < 7
              then
                Approval.approve t model ~organisation:org ~membership ~at:t0 ()
                |> Result.map ~f:fst
              else if dice < 8
              then Approval.reject t model ~organisation:org ~membership ~at:t0 ()
              else
                Approval.cancel
                  t
                  model
                  ~organisation:org
                  ~membership
                  ~override:D.manage_members
                  ~at:t0
                  ()
            in
            match t.status, result with
            | Pending, Ok t' -> t', n + 1
            | (Approved | Rejected | Cancelled), Ok _ -> assert false
            | _, Error _ -> t, n)
        in
        let voters = List.map final.approvals ~f:(fun v -> v.by) in
        assert (not (List.contains_dup voters ~compare:User_id.compare));
        assert (not (List.mem voters final.maker ~equal:User_id.equal));
        List.iter voters ~f:(fun v ->
          let m = List.find_exn members ~f:(fun m -> User_id.equal m.user v) in
          assert (Role_model.allows model m.role D.approve_payments));
        [%test_result: bool]
          (Approval.Status.equal final.status Approved)
          ~expect:(List.length voters >= final.required);
        [%test_result: int] final.version ~expect:successes)
;;
