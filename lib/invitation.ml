open! Core

module Status = struct
  type t =
    | Pending
    | Accepted
    | Revoked
  [@@deriving bin_io, sexp, compare, equal, hash, enumerate]
end

module Shown = struct
  type t =
    | Pending
    | Expired
    | Accepted
    | Revoked
  [@@deriving sexp, compare, equal, hash, enumerate]

  let to_string = function
    | Pending -> "pending"
    | Expired -> "expired"
    | Accepted -> "accepted"
    | Revoked -> "revoked"
  ;;
end

module Policy = struct
  type t =
    { lifetime : Time_ns.Span.t
    ; max_pending : int
    }
  [@@deriving sexp, compare, equal]

  let default = { lifetime = Time_ns.Span.of_day 14.; max_pending = 50 }
end

type t =
  { id : Invitation_id.Stable.V1.t
  ; org : Org_id.Stable.V1.t
  ; email : Email.Stable.V1.t
  ; role : Role.Stable.V1.t
  ; display_name : string option
  ; invited_by : User_id.Stable.V1.t
  ; created_at : Time_utc.t
  ; expires_at : Time_utc.t
  ; token_hash : Token.Hash.Stable.V1.t
  ; status : Status.t
  ; accepted_by : User_id.Stable.V1.t option
  ; closed_at : Time_utc.t option
  ; sent_count : int
  ; last_sent_at : Time_utc.t
  ; version : int
  }
[@@deriving bin_io, sexp, compare, equal]

module Error = struct
  type t =
    | Unknown_role of Role.t
    | Already_member
    | Already_invited
    | Too_many_pending of { max : int }
    | Not_pending of Shown.t
    | Expired
    | Wrong_token
    | Email_mismatch
    | Invalid of string
  [@@deriving sexp, compare, equal]

  let code = function
    | Unknown_role _ -> "unknown_role"
    | Already_member -> "already_member"
    | Already_invited -> "invitation_pending"
    | Too_many_pending _ -> "too_many_invitations"
    | Not_pending _ -> "invitation_not_pending"
    | Expired -> "invitation_expired"
    | Wrong_token -> "invalid_token"
    | Email_mismatch -> "email_mismatch"
    | Invalid _ -> "invalid"
  ;;
end

module Proof = struct
  type t =
    | Token of Token.t
    | Verified_email
end

let expired t ~now = Time_ns.( >= ) now t.expires_at

let shown t ~now : Shown.t =
  match t.status with
  | Accepted -> Accepted
  | Revoked -> Revoked
  | Pending -> if expired t ~now then Expired else Pending
;;

let usable t ~now = Shown.equal (shown t ~now) Pending

let create
  ?(policy = Policy.default)
  model
  ~id
  ~org
  ~email
  ~role
  ?(display_name = "")
  ~invited_by
  ~token
  ~members
  ~invitations
  ~at
  ()
  =
  let open Result.Let_syntax in
  let%bind () =
    if Role_model.mem model role then Ok () else Error (Error.Unknown_role role)
  in
  let%bind display_name =
    Text.check_optional ~what:"display name" ~max:70 display_name
    |> Result.map_error ~f:(fun e -> Error.Invalid (Core.Error.to_string_hum e))
  in
  let%bind () =
    if List.exists members ~f:(fun (m : Member.t) ->
         Org_id.equal m.org org && Email.equal m.email email)
    then Error Error.Already_member
    else Ok ()
  in
  let pending =
    List.filter invitations ~f:(fun i ->
      Org_id.equal i.org org && Status.equal i.status Pending)
  in
  let%bind () =
    if List.exists pending ~f:(fun i -> Email.equal i.email email)
    then Error Error.Already_invited
    else Ok ()
  in
  let%map () =
    let live = List.count pending ~f:(fun i -> not (expired i ~now:at)) in
    if live >= policy.max_pending
    then Error (Error.Too_many_pending { max = policy.max_pending })
    else Ok ()
  in
  { id
  ; org
  ; email
  ; role
  ; display_name
  ; invited_by
  ; created_at = at
  ; expires_at = Time_ns.add at policy.lifetime
  ; token_hash = Token.hash token
  ; status = Pending
  ; accepted_by = None
  ; closed_at = None
  ; sent_count = 1
  ; last_sent_at = at
  ; version = 0
  }
;;

let not_pending t ~now = Error (Error.Not_pending (shown t ~now))

let resend ?(policy = Policy.default) t ~token ~at =
  match t.status with
  | Accepted | Revoked -> not_pending t ~now:at
  | Pending ->
    Ok
      { t with
        token_hash = Token.hash token
      ; expires_at = Time_ns.add at policy.lifetime
      ; sent_count = t.sent_count + 1
      ; last_sent_at = at
      ; version = t.version + 1
      }
;;

let revoke t ~at =
  match t.status with
  | Revoked -> Ok t
  | Accepted -> not_pending t ~now:at
  | Pending ->
    Ok { t with status = Revoked; closed_at = Some at; version = t.version + 1 }
;;

let accept t ~(proof : Proof.t) ~user ~email ~at =
  match t.status with
  | Accepted | Revoked -> not_pending t ~now:at
  | Pending ->
    if expired t ~now:at
    then Error Error.Expired
    else (
      let proof_holds =
        match proof with
        | Token token -> Token.matches token t.token_hash
        | Verified_email -> true
      in
      (* The token is checked before the address so a wrong link does not reveal
         which address it was meant for. *)
      if not proof_holds
      then Error Error.Wrong_token
      else if not (Email.equal email t.email)
      then Error Error.Email_mismatch
      else
        Ok
          { t with
            status = Accepted
          ; accepted_by = Some user
          ; closed_at = Some at
          ; version = t.version + 1
          })
;;

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
