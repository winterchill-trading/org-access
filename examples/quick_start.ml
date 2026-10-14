(* A business opens an organisation, invites an approver, and pays a supplier under a
   four-eyes rule, all against the in-memory store. *)

open! Core
open Money
open Org_access
module D = Role_model.Default
module Store = Store_memory.Make (Monad.Ident)
module Ops = Access.Make (Monad.Ident) (Store)

let at minutes =
  Time_ns.add
    (Time_ns.of_string_with_utc_offset "2027-03-01 09:00:00Z")
    (Time_ns.Span.of_int_min minutes)
;;

let ok = function
  | Ok x -> x
  | Error e -> raise_s [%message "unexpected" (e : Access.Error.t)]
;;

let user = User_id.of_string
let email = Email.of_string
let config = Access.Config.default
let org = Org_id.of_string "org-acme"

let () =
  let store = Store.create () in
  (* Ana opens the organisation and becomes its administrator. *)
  let (_ : Team.t) =
    Ops.create_organisation
      config
      store
      ~id:org
      ~name:"Acme Trading Ltd"
      ~creator:(user "ana")
      ~email:(email "ana@acme.example")
      ~at:(at 0)
      ()
    |> ok
  in
  (* She invites two approvers and adds an operator directly. *)
  List.iter [ "bea"; "cal" ] ~f:(fun name ->
    let (_ : Invitation.t), token =
      Ops.invite
        config
        store
        ~actor:(user "ana")
        ~org
        ~id:(Invitation_id.of_string ("inv-" ^ name))
        ~email:(email (name ^ "@acme.example"))
        ~role:D.approver
        ~at:(at 1)
        ()
      |> ok
    in
    (* The token travels in an e-mail link; only its hash is stored. *)
    let (_ : Member.t) =
      Ops.accept_link
        config
        store
        ~token
        ~user:(user name)
        ~email:(email (name ^ "@acme.example"))
        ~at:(at 5)
      |> ok
    in
    ());
  let (_ : Member.t) =
    Ops.add_member
      config
      store
      ~actor:(user "ana")
      ~org
      ~user:(user "olu")
      ~email:(email "olu@acme.example")
      ~role:D.operator
      ~at:(at 6)
      ()
    |> ok
  in
  (* Money actions wait for business verification. *)
  let create = Action.requires_verified D.create_payments in
  let decide () =
    Ops.authorize config store ~user:(user "olu") ~org create ~at:(at 7)
  in
  print_s [%message "before verification" ~_:(decide () : Authorize.Decision.t)];
  let (_ : Organisation.t) =
    Ops.set_verified store org true ~actor:None ~at:(at 8) |> ok
  in
  print_s [%message "after verification" ~_:(decide () : Authorize.Decision.t)];
  (* Olu prepares a payment above the four-eyes threshold. *)
  let policy = Approval_policy.four_eyes ~above:[ Amount.of_string "10000.00 EUR" ] in
  let approval =
    Ops.open_approval
      config
      store
      ~maker:(user "olu")
      ~org
      ~id:(Approval_id.of_string "apr-1")
      ~policy
      ~subject:"supplier invoice 2027-031"
      ~action:(Action.requires_verified D.approve_payments)
      ~amounts:[ Amount.of_string "12500.00 EUR" ]
      ~maker_action:create
      ~at:(at 9)
      ()
    |> ok
  in
  print_s [%message "opened" ~required:(approval.required : int)];
  List.iter [ "olu"; "bea"; "bea"; "cal" ] ~f:(fun name ->
    match
      Ops.approve
        config
        store
        ~user:(user name)
        ~org
        ~id:approval.id
        ~at:(at 10)
        ()
    with
    | Ok (_, progress) -> print_s [%message name (progress : Approval.Progress.t)]
    | Error e -> print_s [%message name ~refused:(Access.Error.code e : string)]);
  (* Everything above is in the organisation's audit, as one verifiable chain. *)
  let entries =
    Ops.audit config store ~user:(user "ana") ~org ~after:0 ~limit:100 ~at:(at 11) ()
    |> ok
  in
  List.iter entries ~f:(fun e ->
    printf
      "%2d %-4s %s\n"
      e.seq
      (Option.value_map e.actor ~default:"-" ~f:User_id.to_string)
      (Audit.Event.kind e.event));
  print_s [%message "chain" ~_:(Audit.verify org entries : (unit, Audit.Broken.t) result)]
;;
