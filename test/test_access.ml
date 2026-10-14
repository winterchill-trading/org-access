open! Core
open Money
open Org_access
open Fixtures
module D = Role_model.Default
module Memory = Store_memory.Make (Monad.Ident)
module A = Access.Make (Monad.Ident) (Memory)

let tokens = ref 0

let config =
  { Access.Config.default with
    new_token =
      (fun () ->
        incr tokens;
        token (100 + !tokens))
  }
;;

let show_error (e : Access.Error.t) = print_s [%message (e : Access.Error.t) ~code:(Access.Error.code e)]

let ok = function
  | Ok x -> x
  | Error e ->
    show_error e;
    failwith "unexpected error"
;;

let print_result f = function
  | Ok x -> f x
  | Error e -> show_error e
;;

let setup () =
  let s = Memory.create () in
  let (_ : Team.t) =
    A.create_organisation
      config
      s
      ~id:org_id
      ~name:"Example Trading Ltd"
      ~creator:(user "ana")
      ~email:(email "ana")
      ~at:t0
      ()
    |> ok
  in
  s
;;

let add s name role =
  A.add_member config s ~actor:(user "ana") ~org:org_id ~user:(user name) ~email:(email name) ~role ~at:(at 1) ()
  |> ok
  |> (ignore : Member.t -> unit)
;;

let print_audit s =
  let entries = Memory.all_audit s in
  List.iter entries ~f:(fun (e : Audit.Entry.t) ->
    print_s
      [%message
        ""
          ~_:(e.seq : int)
          ~_:(Option.value_map e.actor ~default:"-" ~f:User_id.to_string : string)
          ~_:(e.event : Audit.Event.t)]);
  print_s [%sexp (Audit.verify org_id entries : (unit, Audit.Broken.t) result)]
;;

let%expect_test "organisation, decisions and the denial audit" =
  let s = setup () in
  print_result
    (fun _ -> ())
    (A.create_organisation config s ~id:org_id ~name:"Again" ~creator:(user "zoe") ~email:(email "zoe") ~at:t0 ());
  add s "olu" D.operator;
  let decide name action =
    print_s [%sexp (A.authorize config s ~user:(user name) ~org:org_id action ~at:(at 2) : Authorize.Decision.t)]
  in
  decide "olu" (Action.requires_verified D.create_payments);
  decide "olu" (Action.requires D.manage_members);
  decide "zoe" Action.read;
  let (_ : Organisation.t) = A.set_verified s org_id true ~actor:None ~at:(at 3) |> ok in
  decide "olu" (Action.requires_verified D.create_payments);
  print_audit s;
  [%expect
    {|
    ((e Exists) (code exists))
    (Denied Verification_required)
    (Denied
     (Permission_missing (role operator) (permission members.manage)
      (required (admin))))
    (Denied Not_a_member)
    (Allowed (role operator))
    (1 ana (Organisation_created (name "Example Trading Ltd")))
    (2 ana (Member_added (user ana) (role admin) (invitation ())))
    (3 ana (Member_added (user olu) (role operator) (invitation ())))
    (4 olu
     (Access_denied
      (action ((permission (payments.create)) (needs_verification true)))
      (code verification_required)))
    (5 olu
     (Access_denied
      (action ((permission (members.manage)) (needs_verification false)))
      (code role_required)))
    (6 zoe
     (Access_denied (action ((permission ()) (needs_verification false)))
      (code not_a_member)))
    (7 - (Organisation_verified (verified true)))
    (Ok ())
    |}]
;;

let%expect_test "team management through the store" =
  let s = setup () in
  add s "bea" D.admin;
  add s "olu" D.operator;
  let change actor name role =
    print_result
      (fun (m : Member.t) -> print_s [%sexp (m.role : Role.t)])
      (A.change_role config s ~actor:(user actor) ~org:org_id ~user:(user name) ~role ~at:(at 2))
  in
  change "olu" "bea" D.viewer;
  change "zoe" "bea" D.viewer;
  change "ana" "ana" D.viewer;
  change "ana" "olu" D.approver;
  change "bea" "ana" D.viewer;
  print_result (fun () -> print_endline "left") (A.leave config s ~user:(user "bea") ~org:org_id ~at:(at 3));
  print_result (fun () -> print_endline "removed") (A.remove_member config s ~actor:(user "ana") ~org:org_id ~user:(user "bea") ~at:(at 3));
  print_result (fun () -> print_endline "removed") (A.remove_member config s ~actor:(user "bea") ~org:org_id ~user:(user "olu") ~at:(at 3));
  print_result
    (fun (t : Team.t) -> print_s [%sexp (List.map t.members ~f:(fun m -> m.user, m.role) : (User_id.t * Role.t) list)])
    (A.team config s ~user:(user "olu") ~org:org_id ~at:(at 4));
  [%expect
    {|
    ((e
      (Team
       (Denied
        (Permission_missing (role operator) (permission members.manage)
         (required (admin))))))
     (code role_required))
    ((e Not_found) (code not_found))
    ((e (Team Own_membership)) (code own_membership))
    approver
    viewer
    ((e (Team Last_custodian)) (code last_admin))
    ((e
      (Team
       (Denied
        (Permission_missing (role viewer) (permission members.manage)
         (required (admin))))))
     (code role_required))
    removed
    ((e Not_found) (code not_found))
    |}]
;;

let%expect_test "invitations end to end" =
  let s = setup () in
  let bea_inv, bea_token =
    A.invite config s ~actor:(user "ana") ~org:org_id ~id:(Invitation_id.of_string "inv-bea") ~email:(email "bea") ~role:D.approver ~display_name:"Bea" ~at:(at 1) ()
    |> ok
  in
  print_s [%sexp (bea_inv.token_hash : Token.Hash.t)];
  print_s [%sexp (Token.matches bea_token bea_inv.token_hash : bool)];
  let preview token at =
    print_s
      [%sexp
        (A.preview s ~token ~at
         |> Option.map ~f:(fun ((o : Organisation.t), (i : Invitation.t)) -> o.name, i.role, i.email)
         : (string * Role.t * Email.t) option)]
  in
  preview bea_token (at 2);
  preview (token 1) (at 2);
  preview bea_token (at (15 * 24 * 60));
  (* A duplicate id, and a second invitation to the same address. *)
  print_result (fun _ -> ())
    (A.invite config s ~actor:(user "ana") ~org:org_id ~id:(Invitation_id.of_string "inv-bea") ~email:(email "eve") ~role:D.viewer ~at:(at 1) ());
  print_result (fun _ -> ())
    (A.invite config s ~actor:(user "ana") ~org:org_id ~id:(Invitation_id.of_string "inv-2") ~email:(email "bea") ~role:D.viewer ~at:(at 1) ());
  let accept ?(email = email "bea") token =
    print_result
      (fun (m : Member.t) -> print_s [%message "member" ~_:(m.user : User_id.t) ~_:(m.role : Role.t) ~_:(m.display_name : string option)])
      (A.accept_link config s ~token ~user:(user "bea") ~email ~at:(at 3))
  in
  accept ~email:(Fixtures.email "eve") bea_token;
  accept bea_token;
  accept bea_token;
  (* Resend rotates the link: the first one stops working. *)
  let (_ : Invitation.t * Token.t) =
    A.invite config s ~actor:(user "ana") ~org:org_id ~id:(Invitation_id.of_string "inv-cal") ~email:(email "cal") ~role:D.viewer ~at:(at 4) ()
    |> ok
  in
  let first_cal_token = token (100 + !tokens) in
  let _, new_token =
    A.resend config s ~actor:(user "ana") ~org:org_id ~id:(Invitation_id.of_string "inv-cal") ~at:(at 5) |> ok
  in
  preview first_cal_token (at 6);
  preview new_token (at 6);
  (* Signing in with the invited address accepts the oldest usable invitation. *)
  print_result
    (fun m -> print_s [%sexp (Option.map m ~f:(fun (m : Member.t) -> m.user, m.role) : (User_id.t * Role.t) option)])
    (A.accept_pending config s ~user:(user "cal") ~email:(email "cal") ~at:(at 7));
  print_result
    (fun m -> print_s [%sexp (Option.is_none m : bool)])
    (A.accept_pending config s ~user:(user "dan") ~email:(email "dan") ~at:(at 7));
  (* Revoke is idempotent until accepted. *)
  let (_ : Invitation.t * Token.t) =
    A.invite config s ~actor:(user "ana") ~org:org_id ~id:(Invitation_id.of_string "inv-dan") ~email:(email "dan") ~role:D.viewer ~at:(at 8) ()
    |> ok
  in
  let revoke id =
    print_result
      (fun (i : Invitation.t) -> print_s [%sexp (i.status : Invitation.Status.t)])
      (A.revoke config s ~actor:(user "ana") ~org:org_id ~id:(Invitation_id.of_string id) ~at:(at 9))
  in
  revoke "inv-dan";
  revoke "inv-dan";
  revoke "inv-bea";
  revoke "inv-zzz";
  print_result (fun _ -> ())
    (A.revoke config s ~actor:(user "bea") ~org:org_id ~id:(Invitation_id.of_string "inv-dan") ~at:(at 9));
  print_audit s;
  [%expect
    {|
    a45a494f491cb5c3093a565b243a0611074015ef455178668763adc8592b991f
    true
    (("Example Trading Ltd" approver bea@example.com))
    ()
    ()
    ((e Exists) (code exists))
    ((e (Invitation Already_invited)) (code invitation_pending))
    ((e (Invitation Email_mismatch)) (code email_mismatch))
    (member bea approver (Bea))
    ((e (Invitation (Not_pending Accepted))) (code invitation_not_pending))
    ()
    (("Example Trading Ltd" viewer cal@example.com))
    ((cal viewer))
    true
    Revoked
    Revoked
    ((e (Invitation (Not_pending Accepted))) (code invitation_not_pending))
    ((e Not_found) (code not_found))
    ((e
      (Denied
       (Permission_missing (role approver) (permission members.manage)
        (required (admin)))))
     (code role_required))
    (1 ana (Organisation_created (name "Example Trading Ltd")))
    (2 ana (Member_added (user ana) (role admin) (invitation ())))
    (3 ana
     (Invitation_sent (invitation inv-bea) (email bea@example.com)
      (role approver) (resend false)))
    (4 bea (Member_added (user bea) (role approver) (invitation (inv-bea))))
    (5 bea (Invitation_accepted (invitation inv-bea) (user bea)))
    (6 ana
     (Invitation_sent (invitation inv-cal) (email cal@example.com) (role viewer)
      (resend false)))
    (7 ana
     (Invitation_sent (invitation inv-cal) (email cal@example.com) (role viewer)
      (resend true)))
    (8 cal (Member_added (user cal) (role viewer) (invitation (inv-cal))))
    (9 cal (Invitation_accepted (invitation inv-cal) (user cal)))
    (10 ana
     (Invitation_sent (invitation inv-dan) (email dan@example.com) (role viewer)
      (resend false)))
    (11 ana (Invitation_revoked (invitation inv-dan)))
    (12 bea
     (Access_denied
      (action ((permission (members.manage)) (needs_verification false)))
      (code role_required)))
    (Ok ())
    |}]
;;

let policy = Approval_policy.four_eyes ~above:[ Amount.of_string "10000.00 EUR" ]
let approve_action = Action.requires_verified D.approve_payments

let approvals_setup () =
  let s = setup () in
  add s "bea" D.approver;
  add s "cal" D.approver;
  add s "olu" D.operator;
  let (_ : Organisation.t) = A.set_verified s org_id true ~actor:None ~at:(at 1) |> ok in
  s
;;

let open_ s ?(maker = "olu") ?(id = "apr-1") amount =
  A.open_approval
    config
    s
    ~maker:(user maker)
    ~org:org_id
    ~id:(Approval_id.of_string id)
    ~policy
    ~subject:"payout-batch:42"
    ~action:approve_action
    ~amounts:[ Amount.of_string amount ]
    ~maker_action:(Action.requires_verified D.create_payments)
    ~at:(at 2)
    ()
;;

let approve s ?(id = "apr-1") name =
  print_result
    (fun ((a : Approval.t), progress) ->
      print_s [%message "" ~_:(progress : Approval.Progress.t) ~version:(a.version : int)])
    (A.approve config s ~user:(user name) ~org:org_id ~id:(Approval_id.of_string id) ~at:(at 3) ())
;;

let%expect_test "approvals end to end" =
  let s = approvals_setup () in
  print_result (fun _ -> ()) (open_ s ~maker:"bea" "20000.00 EUR");
  let a = open_ s "20000.00 EUR" |> ok in
  print_s [%message "" ~required:(a.required : int)];
  print_result (fun _ -> ()) (open_ s "1.00 EUR");
  approve s "olu";
  approve s "bea";
  approve s "bea";
  approve s "zoe";
  approve s ~id:"apr-404" "cal";
  approve s "cal";
  print_result
    (fun (a : Approval.t) -> print_s [%sexp (a.status : Approval.Status.t)])
    (A.cancel config s ~user:(user "olu") ~org:org_id ~id:(Approval_id.of_string "apr-1") ~at:(at 4) ());
  let (_ : Approval.t) = open_ s ~id:"apr-2" "50.00 EUR" |> ok in
  print_result
    (fun (a : Approval.t) -> print_s [%sexp (a.status : Approval.Status.t)])
    (A.reject config s ~user:(user "cal") ~org:org_id ~id:(Approval_id.of_string "apr-2") ~note:"duplicate" ~at:(at 4) ());
  [%expect
    {|
    ((e
      (Denied
       (Permission_missing (role approver) (permission payments.create)
        (required (operator)))))
     (code role_required))
    (required 2)
    ((e Exists) (code exists))
    ((e
      (Approval
       (Denied
        (Permission_missing (role operator) (permission payments.approve)
         (required (approver))))))
     (code role_required))
    ((Recorded (approvals 1) (required 2)) (version 1))
    ((e (Approval Already_approved)) (code already_approved))
    ((e Not_found) (code not_found))
    ((e Not_found) (code not_found))
    (Completed (version 2))
    ((e (Approval (Not_pending Approved))) (code not_pending))
    Rejected
    |}]
;;

(* A store whose approval writes lose the race a set number of times, as if another
   approver had just written. *)
module Racy = struct
  include Memory

  let lose = ref 0

  let update_approval t a ~expected_version note =
    if !lose > 0
    then (
      decr lose;
      `Conflict)
    else update_approval t a ~expected_version note
  ;;
end

module R = Access.Make (Monad.Ident) (Racy)

let%expect_test "concurrent approvals retry, then give up" =
  let s = approvals_setup () in
  let (_ : Approval.t) = open_ s "20000.00 EUR" |> ok in
  Racy.lose := 2;
  print_result
    (fun ((a : Approval.t), _) -> print_s [%sexp (List.length a.approvals : int)])
    (R.approve config s ~user:(user "bea") ~org:org_id ~id:(Approval_id.of_string "apr-1") ~at:(at 3) ());
  Racy.lose := 3;
  print_result
    (fun _ -> ())
    (R.approve config s ~user:(user "cal") ~org:org_id ~id:(Approval_id.of_string "apr-1") ~at:(at 3) ());
  [%expect
    {|
    1
    ((e Conflict) (code conflict))
    |}]
;;

(* A store that crashes once after the membership is written and before the invitation
   is marked accepted. *)
module Crashy = struct
  include Memory

  let crash = ref false

  let update_invitation t i ~expected_version note =
    if !crash
    then (
      crash := false;
      failwith "crash")
    else update_invitation t i ~expected_version note
  ;;
end

module C = Access.Make (Monad.Ident) (Crashy)

let%expect_test "an interrupted acceptance is finished by the next attempt" =
  let s = setup () in
  let _, tok =
    C.invite config s ~actor:(user "ana") ~org:org_id ~id:(Invitation_id.of_string "inv-bea") ~email:(email "bea") ~role:D.approver ~at:(at 1) ()
    |> ok
  in
  Crashy.crash := true;
  (match C.accept_link config s ~token:tok ~user:(user "bea") ~email:(email "bea") ~at:(at 2) with
   | exception Failure msg -> print_endline msg
   | _ -> print_endline "no crash");
  let status () =
    match Crashy.invitation s (Invitation_id.of_string "inv-bea") with
    | Some i -> print_s [%sexp (i.status : Invitation.Status.t)]
    | None -> ()
  in
  status ();
  print_result
    (fun (m : Member.t) -> print_s [%sexp (m.role : Role.t)])
    (C.accept_link config s ~token:tok ~user:(user "bea") ~email:(email "bea") ~at:(at 3));
  status ();
  [%expect
    {|
    crash
    Pending
    approver
    Accepted
    |}]
;;
