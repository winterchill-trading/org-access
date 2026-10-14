open! Core
open Money

module Status = struct
  type t =
    | Pending
    | Approved
    | Rejected
    | Cancelled
  [@@deriving bin_io, sexp, compare, equal, hash, enumerate]

  let to_string = function
    | Pending -> "pending"
    | Approved -> "approved"
    | Rejected -> "rejected"
    | Cancelled -> "cancelled"
  ;;
end

module Vote = struct
  type t =
    { by : User_id.Stable.V1.t
    ; at : Time_utc.t
    ; note : string option
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t =
  { id : Approval_id.Stable.V1.t
  ; org : Org_id.Stable.V1.t
  ; subject : string
  ; action : Action.Stable.V1.t
  ; maker : User_id.Stable.V1.t
  ; amounts : Amount.Stable.V1.t list
  ; required : int
  ; approvals : Vote.t list
  ; status : Status.t
  ; decision : Vote.t option
  ; created_at : Time_utc.t
  ; version : int
  }
[@@deriving bin_io, sexp, compare, equal]

module Error = struct
  type t =
    | Denied of Reason.Stable.V1.t
    | Own_request
    | Already_approved
    | Not_pending of Status.t
    | Not_enough_approvers of
        { required : int
        ; eligible : int
        }
    | Not_canceller
    | Invalid of string
  [@@deriving sexp, compare, equal]

  let code = function
    | Denied reason -> Reason.code reason
    | Own_request -> "own_request"
    | Already_approved -> "already_approved"
    | Not_pending _ -> "not_pending"
    | Not_enough_approvers _ -> "not_enough_approvers"
    | Not_canceller -> "not_canceller"
    | Invalid _ -> "invalid"
  ;;
end

module Progress = struct
  type t =
    | Recorded of
        { approvals : int
        ; required : int
        }
    | Completed
  [@@deriving sexp, compare, equal]
end

let invalid e = Error (Error.Invalid (Core.Error.to_string_hum e))

let check_note note =
  match note with
  | None -> Ok None
  | Some note ->
    (match Text.check_optional ~what:"note" ~max:200 note with
     | Ok note -> Ok note
     | Error e -> invalid e)
;;

let is_checker model ~organisation ~(membership : Member.t option) ~maker action =
  match Authorize.decide model ~organisation ~membership action with
  | Denied reason -> Error (Error.Denied reason)
  | Allowed _ ->
    (* [decide] returned [Allowed], so [membership] is [Some]. *)
    let member = Option.value_exn membership in
    if User_id.equal member.user maker then Error Error.Own_request else Ok member
;;

let open_
  model
  policy
  ~id
  ~(organisation : Organisation.t)
  ~(maker : Member.t)
  ~subject
  ~action
  ~amounts
  ?members
  ~at
  ()
  =
  let open Result.Let_syntax in
  let%bind (_ : Member.t) =
    Authorize.scope ~membership:(Some maker) organisation.id
    |> Result.map_error ~f:(fun reason -> Error.Denied reason)
  in
  let%bind subject =
    match Text.check ~what:"subject" ~max:128 subject with
    | Ok s -> Ok s
    | Error e -> invalid e
  in
  let required = Approval_policy.required_for policy amounts in
  let%map () =
    match members with
    | None -> Ok ()
    | Some members ->
      let eligible =
        List.count members ~f:(fun m ->
          Result.is_ok
            (is_checker model ~organisation ~membership:(Some m) ~maker:maker.user action))
      in
      if eligible < required
      then Error (Error.Not_enough_approvers { required; eligible })
      else Ok ()
  in
  { id
  ; org = organisation.id
  ; subject
  ; action
  ; maker = maker.user
  ; amounts
  ; required
  ; approvals = []
  ; status = Pending
  ; decision = None
  ; created_at = at
  ; version = 0
  }
;;

let pending t =
  match t.status with
  | Pending -> Ok ()
  | status -> Error (Error.Not_pending status)
;;

let check_scope t (organisation : Organisation.t) =
  (* A request is only ever acted on within its own organisation; a mismatch is a
     programming error in the caller, reported like a foreign resource. *)
  if Org_id.equal t.org organisation.id
  then Ok ()
  else Error (Error.Denied Other_organisation)
;;

let has_approved t user = List.exists t.approvals ~f:(fun v -> User_id.equal v.by user)

let approve t model ~organisation ~membership ?note ~at () =
  let open Result.Let_syntax in
  let%bind () = check_scope t organisation in
  let%bind () = pending t in
  let%bind member = is_checker model ~organisation ~membership ~maker:t.maker t.action in
  let%bind () =
    if has_approved t member.user then Error Error.Already_approved else Ok ()
  in
  let%map note = check_note note in
  let approvals = t.approvals @ [ { Vote.by = member.user; at; note } ] in
  let count = List.length approvals in
  if count >= t.required
  then
    { t with approvals; status = Approved; version = t.version + 1 }, Progress.Completed
  else
    ( { t with approvals; version = t.version + 1 }
    , Progress.Recorded { approvals = count; required = t.required } )
;;

let reject t model ~organisation ~membership ?note ~at () =
  let open Result.Let_syntax in
  let%bind () = check_scope t organisation in
  let%bind () = pending t in
  let%bind member = is_checker model ~organisation ~membership ~maker:t.maker t.action in
  let%map note = check_note note in
  { t with
    status = Rejected
  ; decision = Some { by = member.user; at; note }
  ; version = t.version + 1
  }
;;

let cancel t model ~organisation ~membership ?override ?note ~at () =
  let open Result.Let_syntax in
  let%bind () = check_scope t organisation in
  let%bind () = pending t in
  let%bind member =
    Authorize.scope ~membership t.org |> Result.map_error ~f:(fun r -> Error.Denied r)
  in
  let%bind () =
    let is_maker = User_id.equal member.user t.maker in
    let may_override =
      match override with
      | None -> false
      | Some permission ->
        Authorize.Decision.is_allowed
          (Authorize.decide model ~organisation ~membership (Action.requires permission))
    in
    if is_maker || may_override then Ok () else Error Error.Not_canceller
  in
  let%map note = check_note note in
  { t with
    status = Cancelled
  ; decision = Some { by = member.user; at; note }
  ; version = t.version + 1
  }
;;

let remaining t =
  match t.status with
  | Approved -> 0
  | Pending | Rejected | Cancelled -> Int.max 0 (t.required - List.length t.approvals)
;;

let can_approve t model ~organisation ~membership =
  Result.is_ok (check_scope t organisation)
  && Result.is_ok (pending t)
  &&
  match is_checker model ~organisation ~membership ~maker:t.maker t.action with
  | Ok member -> not (has_approved t member.user)
  | Error _ -> false
;;

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
