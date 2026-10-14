open! Core

module Make (M : Monad.S) = struct
  type 'a io = 'a M.t

  type team_row =
    { mutable organisation : Organisation.t
    ; mutable members : Member.t User_id.Map.t
    ; mutable version : int
    }

  type t =
    { teams : team_row Org_id.Table.t
    ; invitations : Invitation.t Invitation_id.Table.t
    ; approvals : Approval.t Approval_id.Table.t
    ; audit : Audit.Entry.t list Org_id.Table.t (* newest first *)
    ; mutable clock : int
        (* insertion order, for "newest first" listings that do not depend on timestamps *)
    ; order : int String.Table.t
    }

  let create () =
    { teams = Org_id.Table.create ()
    ; invitations = Invitation_id.Table.create ()
    ; approvals = Approval_id.Table.create ()
    ; audit = Org_id.Table.create ()
    ; clock = 0
    ; order = String.Table.create ()
    }
  ;;

  let stamp t key =
    t.clock <- t.clock + 1;
    Hashtbl.set t.order ~key ~data:t.clock
  ;;

  let order t key = Hashtbl.find t.order key |> Option.value ~default:0

  let append t org (note : Store.Note.t) =
    let entries = Hashtbl.find t.audit org |> Option.value ~default:[] in
    let entries =
      List.fold note.events ~init:entries ~f:(fun entries event ->
        let e =
          Audit.next ~last:(List.hd entries) ~org ~at:note.at ~actor:note.actor event
          |> Or_error.ok_exn
        in
        e :: entries)
    in
    Hashtbl.set t.audit ~key:org ~data:entries
  ;;

  let create_organisation t (organisation : Organisation.t) ~(founder : Member.t) note =
    M.return
      (match Hashtbl.find t.teams organisation.id with
       | Some row -> `Exists row.organisation
       | None ->
         Hashtbl.set
           t.teams
           ~key:organisation.id
           ~data:
             { organisation
             ; members = User_id.Map.singleton founder.user founder
             ; version = 0
             };
         append t organisation.id note;
         `Created)
  ;;

  let organisation t id =
    M.return (Hashtbl.find t.teams id |> Option.map ~f:(fun row -> row.organisation))
  ;;

  let save_organisation t (organisation : Organisation.t) note =
    (match Hashtbl.find t.teams organisation.id with
     | Some row -> row.organisation <- organisation
     | None ->
       Hashtbl.set
         t.teams
         ~key:organisation.id
         ~data:{ organisation; members = User_id.Map.empty; version = 0 });
    append t organisation.id note;
    M.return ()
  ;;

  let team t id =
    M.return
      (Hashtbl.find t.teams id
       |> Option.map ~f:(fun row ->
         { Team.organisation = row.organisation
         ; members = Map.data row.members
         ; version = row.version
         }))
  ;;

  let update_team t id ~expected_version changes note =
    M.return
      (match Hashtbl.find t.teams id with
       | Some row when row.version = expected_version ->
         row.members
         <- List.fold
              changes
              ~init:row.members
              ~f:(fun members (change : Team.Change.t) ->
                match change with
                | Put m -> Map.set members ~key:m.user ~data:m
                | Remove user -> Map.remove members user);
         row.version <- row.version + 1;
         append t id note;
         `Ok
       | _ -> `Conflict)
  ;;

  let memberships t user =
    M.return
      (Hashtbl.data t.teams
       |> List.filter_map ~f:(fun row -> Map.find row.members user)
       |> List.sort ~compare:(fun (a : Member.t) b -> Org_id.compare a.org b.org))
  ;;

  let invitation_key id = "i:" ^ Invitation_id.to_string id
  let approval_key id = "a:" ^ Approval_id.to_string id

  let insert_invitation t (i : Invitation.t) note =
    let clash =
      Hashtbl.mem t.invitations i.id
      || Hashtbl.exists t.invitations ~f:(fun j ->
        Token.Hash.equal j.token_hash i.token_hash
        || (Org_id.equal j.org i.org
            && Email.equal j.email i.email
            && Invitation.Status.equal j.status Pending))
    in
    M.return
      (if clash
       then `Duplicate
       else (
         Hashtbl.set t.invitations ~key:i.id ~data:i;
         stamp t (invitation_key i.id);
         append t i.org note;
         `Ok))
  ;;

  let update_invitation t (i : Invitation.t) ~expected_version note =
    M.return
      (match Hashtbl.find t.invitations i.id with
       | Some stored when stored.version = expected_version ->
         Hashtbl.set t.invitations ~key:i.id ~data:i;
         append t i.org note;
         `Ok
       | _ -> `Conflict)
  ;;

  let invitation t id = M.return (Hashtbl.find t.invitations id)

  let invitation_by_token t hash =
    M.return
      (Hashtbl.data t.invitations
       |> List.find ~f:(fun (i : Invitation.t) -> Token.Hash.equal i.token_hash hash))
  ;;

  let newest_first t key l =
    List.sort l ~compare:(fun a b -> Int.compare (order t (key b)) (order t (key a)))
  ;;

  let invitations t org =
    Hashtbl.data t.invitations
    |> List.filter ~f:(fun (i : Invitation.t) -> Org_id.equal i.org org)
    |> newest_first t (fun (i : Invitation.t) -> invitation_key i.id)
    |> M.return
  ;;

  let pending_for t email =
    Hashtbl.data t.invitations
    |> List.filter ~f:(fun (i : Invitation.t) ->
      Email.equal i.email email && Invitation.Status.equal i.status Pending)
    |> newest_first t (fun (i : Invitation.t) -> invitation_key i.id)
    |> List.rev
    |> M.return
  ;;

  let insert_approval t (a : Approval.t) note =
    M.return
      (if Hashtbl.mem t.approvals a.id
       then `Duplicate
       else (
         Hashtbl.set t.approvals ~key:a.id ~data:a;
         stamp t (approval_key a.id);
         append t a.org note;
         `Ok))
  ;;

  let update_approval t (a : Approval.t) ~expected_version note =
    M.return
      (match Hashtbl.find t.approvals a.id with
       | Some stored when stored.version = expected_version ->
         Hashtbl.set t.approvals ~key:a.id ~data:a;
         append t a.org note;
         `Ok
       | _ -> `Conflict)
  ;;

  let approval t id = M.return (Hashtbl.find t.approvals id)

  let approvals t org ~status =
    Hashtbl.data t.approvals
    |> List.filter ~f:(fun (a : Approval.t) ->
      Org_id.equal a.org org && Option.for_all status ~f:(Approval.Status.equal a.status))
    |> newest_first t (fun (a : Approval.t) -> approval_key a.id)
    |> M.return
  ;;

  let append_audit t org note =
    append t org note;
    M.return ()
  ;;

  let audit t org ~after ~limit =
    Hashtbl.find t.audit org
    |> Option.value ~default:[]
    |> List.rev
    |> List.filter ~f:(fun (e : Audit.Entry.t) -> e.seq > after)
    |> fun l -> List.take l limit |> M.return
  ;;

  let all_audit t =
    Hashtbl.to_alist t.audit
    |> List.sort ~compare:(fun (a, _) (b, _) -> Org_id.compare a b)
    |> List.concat_map ~f:(fun (_, entries) -> List.rev entries)
  ;;
end
