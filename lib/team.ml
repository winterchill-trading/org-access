open! Core

module Change = struct
  type t =
    | Put of Member.Stable.V1.t
    | Remove of User_id.Stable.V1.t
  [@@deriving bin_io, sexp, compare, equal]
end

module Policy = struct
  type t = { single_membership : bool } [@@deriving sexp, compare, equal]

  let default = { single_membership = false }
end

module Error = struct
  type t =
    | Denied of Reason.t
    | Unknown_role of Role.t
    | Already_member
    | Member_elsewhere of Org_id.t
    | Not_member
    | Own_membership
    | Last_custodian
    | Invitation_not_accepted
    | Invalid of string
  [@@deriving sexp, compare, equal]

  let code = function
    | Denied reason -> Reason.code reason
    | Unknown_role _ -> "unknown_role"
    | Already_member -> "member_exists"
    | Member_elsewhere _ -> "member_elsewhere"
    | Not_member -> "not_member"
    | Own_membership -> "own_membership"
    | Last_custodian -> "last_admin"
    | Invitation_not_accepted -> "invitation_not_accepted"
    | Invalid _ -> "invalid"
  ;;
end

type t =
  { organisation : Organisation.t
  ; members : Member.t list
  ; version : int
  }
[@@deriving sexp_of, compare, equal]

let sort model members =
  let rank (m : Member.t) =
    (* Unknown roles sort last; they only appear when a model changed under stored data. *)
    Option.value (Role_model.rank model m.role) ~default:Int.max_value
  in
  List.sort members ~compare:(fun (a : Member.t) b ->
    Comparable.lexicographic
      [ (fun a b -> Int.compare (rank a) (rank b))
      ; (fun (a : Member.t) b -> String.compare (Member.label a) (Member.label b))
      ; (fun (a : Member.t) b -> User_id.compare a.user b.user)
      ]
      a
      b)
;;

let of_members model organisation members ~version =
  { organisation; members = sort model members; version }
;;

let find t user = List.find t.members ~f:(fun m -> User_id.equal m.user user)

let holds_custodian model (m : Member.t) =
  Role_model.allows model m.role (Role_model.custodian model)
;;

let custodians model t = List.filter t.members ~f:(holds_custodian model)

let apply model t changes =
  let members =
    List.fold changes ~init:t.members ~f:(fun members (change : Change.t) ->
      match change with
      | Put m -> m :: List.filter members ~f:(fun x -> not (User_id.equal x.user m.user))
      | Remove user -> List.filter members ~f:(fun x -> not (User_id.equal x.user user)))
  in
  let t' = { t with members = sort model members; version = t.version + 1 } in
  if List.is_empty (custodians model t')
  then Error Error.Last_custodian
  else Ok (t', changes)
;;

let check_role model role =
  if Role_model.mem model role then Ok () else Error (Error.Unknown_role role)
;;

let authorize_actor model t ~actor =
  match
    Authorize.decide
      model
      ~organisation:t.organisation
      ~membership:actor
      (Action.requires (Role_model.custodian model))
  with
  | Denied reason -> Error (Error.Denied reason)
  | Allowed _ -> Ok (Option.value_exn actor)
;;

let check_elsewhere ~(policy : Policy.t) t ~other_memberships =
  if not policy.single_membership
  then Ok ()
  else (
    match
      List.find other_memberships ~f:(fun (m : Member.t) ->
        not (Org_id.equal m.org t.organisation.id))
    with
    | Some m -> Error (Error.Member_elsewhere m.org)
    | None -> Ok ())
;;

let invalid e = Error (Error.Invalid (Core.Error.to_string_hum e))

let found model (organisation : Organisation.t) ~email ?display_name ~at () =
  match
    List.find (Role_model.roles model) ~f:(fun role ->
      Role_model.allows model role (Role_model.custodian model))
  with
  | None ->
    (* [Role_model.create] guarantees a role holding the custodian permission. *)
    assert false
  | Some role ->
    (match
       Member.create
         ~org:organisation.id
         ~user:organisation.created_by
         ~email
         ?display_name
         ~role
         ~added_at:at
         ~added_by:None
         ()
     with
     | Error e -> invalid e
     | Ok member -> Ok ({ organisation; members = [ member ]; version = 0 }, [ Change.Put member ]))
;;

let add
  ?(policy = Policy.default)
  model
  t
  ~actor
  ~user
  ~email
  ?display_name
  ~role
  ~other_memberships
  ~at
  ()
  =
  let open Result.Let_syntax in
  let%bind (actor : Member.t) = authorize_actor model t ~actor in
  let%bind () = check_role model role in
  let%bind () =
    if Option.is_some (find t user)
       || List.exists t.members ~f:(fun m -> Email.equal m.email email)
    then Error Error.Already_member
    else Ok ()
  in
  let%bind () = check_elsewhere ~policy t ~other_memberships in
  let%bind member =
    match
      Member.create
        ~org:t.organisation.id
        ~user
        ~email
        ?display_name
        ~role
        ~added_at:at
        ~added_by:(Some actor.user)
        ()
    with
    | Ok m -> Ok m
    | Error e -> invalid e
  in
  apply model t [ Put member ]
;;

let change_role model t ~actor ~user ~role =
  let open Result.Let_syntax in
  let%bind (actor : Member.t) = authorize_actor model t ~actor in
  let%bind () = check_role model role in
  let%bind (member : Member.t) =
    match find t user with
    | None -> Error Error.Not_member
    | Some m -> Ok m
  in
  let%bind () =
    if User_id.equal actor.user user then Error Error.Own_membership else Ok ()
  in
  if Role.equal member.role role
  then Ok (t, [])
  else apply model t [ Put { member with role } ]
;;

let remove model t ~actor ~user =
  let open Result.Let_syntax in
  let%bind (actor : Member.t) = authorize_actor model t ~actor in
  let%bind () =
    if User_id.equal actor.user user then Error Error.Own_membership else Ok ()
  in
  match find t user with
  | None -> Ok (t, [])
  | Some _ -> apply model t [ Remove user ]
;;

let leave model t ~user =
  match find t user with
  | None -> Error Error.Not_member
  | Some _ -> apply model t [ Remove user ]
;;

let join ?(policy = Policy.default) model t ~(invitation : Invitation.t) ~user ~other_memberships ~at
  =
  let open Result.Let_syntax in
  let%bind () =
    match invitation.status, invitation.accepted_by with
    | Accepted, Some accepted_by
      when User_id.equal accepted_by user && Org_id.equal invitation.org t.organisation.id ->
      Ok ()
    | _ -> Error Error.Invitation_not_accepted
  in
  let%bind () = check_role model invitation.role in
  let%bind () = if Option.is_some (find t user) then Error Error.Already_member else Ok () in
  let%bind () = check_elsewhere ~policy t ~other_memberships in
  let member : Member.t =
    { org = t.organisation.id
    ; user
    ; email = invitation.email
    ; display_name = invitation.display_name
    ; role = invitation.role
    ; added_at = at
    ; added_by = Some invitation.invited_by
    }
  in
  apply model t [ Put member ]
;;
