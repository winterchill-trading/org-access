open! Core
open Money

(* The functor argument below shadows the [Store] module. *)
module Note = Store.Note

module Make (M : Monad.S) (Store : Store.S with type 'a io := 'a M.t) = struct
  open M.Let_syntax

  let t0 = Time_ns.of_int_ns_since_epoch 1_800_000_000_000_000_000
  let org_id = Org_id.of_string "conformance-org"
  let user s = User_id.of_string ("conformance-" ^ s)
  let email s = Email.of_string (s ^ "@conformance.example")
  let admin = Role_model.Default.admin
  let viewer = Role_model.Default.viewer

  let member name role : Member.t =
    { org = org_id
    ; user = user name
    ; email = email name
    ; display_name = None
    ; role
    ; added_at = t0
    ; added_by = None
    }
  ;;

  let note events : Note.t = { at = t0; actor = Some (user "ana"); events }
  let event name : Audit.Event.t = Organisation_created { name }

  let invitation ~id ~seed ~who : Invitation.t =
    let token = Token.generate (fun n -> String.make n (Char.of_int_exn seed)) in
    { id = Invitation_id.of_string ("conformance-" ^ id)
    ; org = org_id
    ; email = email who
    ; role = viewer
    ; display_name = None
    ; invited_by = user "ana"
    ; created_at = t0
    ; expires_at = Time_ns.add t0 Time_ns.Span.day
    ; token_hash = Token.hash token
    ; status = Pending
    ; accepted_by = None
    ; closed_at = None
    ; sent_count = 1
    ; last_sent_at = t0
    ; version = 0
    }
  ;;

  let approval ~id : Approval.t =
    { id = Approval_id.of_string ("conformance-" ^ id)
    ; org = org_id
    ; subject = "conformance"
    ; action = Action.requires Role_model.Default.approve_payments
    ; maker = user "bea"
    ; amounts = [ Amount.of_minor_units_int Currency.eur 100 ]
    ; required = 1
    ; approvals = []
    ; status = Pending
    ; decision = None
    ; created_at = t0
    ; version = 0
    }
  ;;

  let check store =
    let failures = Queue.create () in
    let expect ok what sexp = if not ok then Queue.enqueue failures (what, sexp) in
    let organisation =
      Organisation.create
        ~id:org_id
        ~name:"Conformance Ltd"
        ~created_by:(user "ana")
        ~at:t0
      |> Or_error.ok_exn
    in
    let ana = member "ana" admin in
    (* Organisation and founder. *)
    let%bind created =
      Store.create_organisation store organisation ~founder:ana (note [ event "created" ])
    in
    expect
      (match created with
       | `Created -> true
       | `Exists _ -> false)
      "first create_organisation"
      [%sexp "expected `Created"];
    let%bind again =
      Store.create_organisation store organisation ~founder:ana (note [ event "again" ])
    in
    expect
      (match again with
       | `Exists o -> Organisation.equal o organisation
       | `Created -> false)
      "second create_organisation"
      [%sexp "expected `Exists with the stored organisation"];
    let%bind team = Store.team store org_id in
    expect
      (match team with
       | Some team ->
         team.version = 0
         && List.equal Member.equal team.members [ ana ]
         && Organisation.equal team.organisation organisation
       | None -> false)
      "team after create"
      [%sexp (team : Team.t option)];
    (* Versioned team updates. *)
    let bea = member "bea" viewer in
    let%bind first =
      Store.update_team store org_id ~expected_version:0 [ Put bea ] (note [ event "t1" ])
    in
    let%bind stale =
      Store.update_team
        store
        org_id
        ~expected_version:0
        [ Remove (user "ana") ]
        (note [ event "lost" ])
    in
    expect
      (Poly.equal first `Ok && Poly.equal stale `Conflict)
      "team compare-and-set"
      [%sexp "expected `Ok then `Conflict for the same expected version"];
    let%bind second =
      Store.update_team
        store
        org_id
        ~expected_version:1
        [ Put { bea with role = admin }; Remove (user "nobody") ]
        (note [ event "t2" ])
    in
    let%bind team = Store.team store org_id in
    expect
      (Poly.equal second `Ok
       &&
       match team with
       | Some team ->
         team.version = 2
         && List.length team.members = 2
         && List.exists team.members ~f:(fun m ->
           User_id.equal m.user bea.user && Role.equal m.role admin)
       | None -> false)
      "team after updates"
      [%sexp (team : Team.t option)];
    let%bind memberships = Store.memberships store (user "bea") in
    expect
      (List.length memberships = 1)
      "memberships"
      [%sexp (memberships : Member.t list)];
    (* Invitations. *)
    let i1 = invitation ~id:"inv-1" ~seed:1 ~who:"cal" in
    let%bind r1 = Store.insert_invitation store i1 (note [ event "i1" ]) in
    let%bind same_id =
      Store.insert_invitation store { i1 with email = email "dan" } (note [ event "x" ])
    in
    let%bind same_email =
      Store.insert_invitation
        store
        (invitation ~id:"inv-2" ~seed:2 ~who:"cal")
        (note [ event "x" ])
    in
    let%bind same_token =
      Store.insert_invitation
        store
        (invitation ~id:"inv-3" ~seed:1 ~who:"dan")
        (note [ event "x" ])
    in
    expect
      (Poly.equal r1 `Ok
       && Poly.equal same_id `Duplicate
       && Poly.equal same_email `Duplicate
       && Poly.equal same_token `Duplicate)
      "invitation uniqueness"
      [%sexp "expected `Ok, then `Duplicate for id, pending address and token hash"];
    let%bind by_token = Store.invitation_by_token store i1.token_hash in
    expect
      (Option.equal Invitation.equal by_token (Some i1))
      "invitation_by_token"
      [%sexp (by_token : Invitation.t option)];
    let revoked = { i1 with status = Revoked; closed_at = Some t0; version = 1 } in
    let%bind u1 =
      Store.update_invitation store revoked ~expected_version:0 (note [ event "i2" ])
    in
    let%bind u2 =
      Store.update_invitation store revoked ~expected_version:0 (note [ event "x" ])
    in
    expect
      (Poly.equal u1 `Ok && Poly.equal u2 `Conflict)
      "invitation compare-and-set"
      [%sexp "expected `Ok then `Conflict"];
    let i4 = invitation ~id:"inv-4" ~seed:4 ~who:"cal" in
    let%bind r4 = Store.insert_invitation store i4 (note [ event "i4" ]) in
    expect
      (Poly.equal r4 `Ok)
      "a revoked invitation frees the address"
      [%sexp "expected `Ok"];
    let i5 = invitation ~id:"inv-5" ~seed:5 ~who:"eve" in
    let%bind (_ : [ `Ok | `Duplicate ]) =
      Store.insert_invitation store i5 (note [ event "i5" ])
    in
    let%bind listed = Store.invitations store org_id in
    expect
      (List.equal
         Invitation_id.equal
         (List.map listed ~f:(fun i -> i.id))
         [ i5.id; i4.id; i1.id ])
      "invitations newest first"
      [%sexp (List.map listed ~f:(fun i -> i.id) : Invitation_id.t list)];
    let%bind pending = Store.pending_for store (email "cal") in
    expect
      (List.equal Invitation_id.equal (List.map pending ~f:(fun i -> i.id)) [ i4.id ])
      "pending_for"
      [%sexp (List.map pending ~f:(fun i -> i.id) : Invitation_id.t list)];
    (* Approvals. *)
    let a1 = approval ~id:"apr-1" in
    let a2 = approval ~id:"apr-2" in
    let%bind ra = Store.insert_approval store a1 (note [ event "a1" ]) in
    let%bind rdup = Store.insert_approval store a1 (note [ event "x" ]) in
    let%bind (_ : [ `Ok | `Duplicate ]) =
      Store.insert_approval store a2 (note [ event "a2" ])
    in
    let voted =
      { a1 with
        approvals = [ { by = user "ana"; at = t0; note = None } ]
      ; status = Approved
      ; version = 1
      }
    in
    let%bind c1 =
      Store.update_approval store voted ~expected_version:0 (note [ event "a3" ])
    in
    let%bind c2 =
      Store.update_approval store voted ~expected_version:0 (note [ event "x" ])
    in
    expect
      (Poly.equal ra `Ok
       && Poly.equal rdup `Duplicate
       && Poly.equal c1 `Ok
       && Poly.equal c2 `Conflict)
      "approval insert and compare-and-set"
      [%sexp "expected `Ok `Duplicate `Ok `Conflict"];
    let%bind all = Store.approvals store org_id ~status:None in
    let%bind pending = Store.approvals store org_id ~status:(Some Pending) in
    let%bind stored = Store.approval store a1.id in
    expect
      (List.equal Approval_id.equal (List.map all ~f:(fun a -> a.id)) [ a2.id; a1.id ]
       && List.equal Approval_id.equal (List.map pending ~f:(fun a -> a.id)) [ a2.id ]
       && Option.equal Approval.equal stored (Some voted))
      "approval listings"
      [%sexp (all : Approval.t list)];
    (* Organisation record and free-standing audit entries. *)
    let%bind () =
      Store.save_organisation
        store
        (Organisation.set_verified organisation true)
        (note [ event "verified" ])
    in
    let%bind () =
      Store.append_audit store org_id (note [ event "denied-1"; event "denied-2" ])
    in
    let%bind stored = Store.organisation store org_id in
    expect
      (Option.value_map stored ~default:false ~f:(fun o -> o.verified))
      "save_organisation"
      [%sexp (stored : Organisation.t option)];
    (* The audit holds exactly the successful writes' notes, in order, as one chain. *)
    let%bind entries = Store.audit store org_id ~after:0 ~limit:1000 in
    let names =
      List.map entries ~f:(fun e ->
        match e.event with
        | Organisation_created { name } -> name
        | other -> Audit.Event.kind other)
    in
    let expected =
      [ "created"; "t1"; "t2"; "i1"; "i2"; "i4"; "i5"; "a1"; "a2"; "a3"; "verified" ]
      @ [ "denied-1"; "denied-2" ]
    in
    expect
      (List.equal String.equal names expected)
      "audit holds every successful write and nothing else"
      [%sexp (names : string list)];
    expect
      (Result.is_ok (Audit.verify org_id entries))
      "audit chain verifies"
      [%sexp (Audit.verify org_id entries : (unit, Audit.Broken.t) result)];
    let%bind page = Store.audit store org_id ~after:3 ~limit:2 in
    expect
      (List.equal Int.equal (List.map page ~f:(fun e -> e.seq)) [ 4; 5 ])
      "audit paging"
      [%sexp (List.map page ~f:(fun e -> e.seq) : int list)];
    return
      (match Queue.to_list failures with
       | [] -> Ok ()
       | failures ->
         Or_error.error_s
           [%message "store conformance failed" (failures : (string * Sexp.t) list)])
  ;;
end
