(** An invitation for someone to join an organisation with a given role.

    The invitation is addressed to an e-mail address and carries a secret {!Token} sent in
    a link; only the token's hash is stored. It is accepted once, by a signed-in user
    whose verified address is the invited one, and then never again. It lapses at
    [expires_at] (14 days by default); a lapsed invitation shows as [Expired] but stays
    stored as pending so an administrator can resend it. Resending rotates the token and
    restarts the validity: the old link stops working at once.

    {v
      Pending --accept (token or verified e-mail, before expiry)--> Accepted
      Pending --revoke--> Revoked
      Pending --resend--> Pending (new token, new expiry)
      Pending, past expires_at: shown as Expired; resend or revoke still work
    v}

    Creating the membership on acceptance is {!Team.join}'s job; {!Access} does both in
    one step. *)

open! Core

module Status : sig
  (** What is stored. *)
  type t =
    | Pending
    | Accepted
    | Revoked
  [@@deriving sexp, compare, equal, hash, enumerate]
end

module Shown : sig
  (** What a client sees: [Pending] past its expiry is [Expired]. *)
  type t =
    | Pending
    | Expired
    | Accepted
    | Revoked
  [@@deriving sexp, compare, equal, hash, enumerate]

  (** [pending], [expired], [accepted], [revoked]. *)
  val to_string : t -> string
end

module Policy : sig
  type t =
    { lifetime : Time_ns.Span.t (** how long a sent link works *)
    ; max_pending : int (** unexpired pending invitations per organisation *)
    }
  [@@deriving sexp, compare, equal]

  (** 14 days, 50 pending. *)
  val default : t
end

type t =
  { id : Invitation_id.t
  ; org : Org_id.t
  ; email : Email.t
  ; role : Role.t
  ; display_name : string option
  ; invited_by : User_id.t
  ; created_at : Time_utc.t
  ; expires_at : Time_utc.t
  ; token_hash : Token.Hash.t
  ; status : Status.t
  ; accepted_by : User_id.t option
  ; closed_at : Time_utc.t option (** when it was accepted or revoked *)
  ; sent_count : int
  ; last_sent_at : Time_utc.t
  ; version : int (** 0 when created, then one more per change *)
  }
[@@deriving sexp, compare, equal]

module Error : sig
  type t =
    | Unknown_role of Role.t
    | Already_member (** the address belongs to a member already *)
    | Already_invited (** a pending invitation exists for the address; resend it *)
    | Too_many_pending of { max : int }
    | Not_pending of Shown.t
    | Expired
    | Wrong_token
    | Email_mismatch (** the accepting user's address is not the invited one *)
    | Invalid of string (** a display name out of bounds *)
  [@@deriving sexp, compare, equal]

  (** [unknown_role], [already_member], [invitation_pending], [too_many_invitations],
      [invitation_not_pending], [invitation_expired], [invalid_token], [email_mismatch],
      [invalid]. *)
  val code : t -> string
end

(** How an accepting user shows the invitation is theirs. *)
module Proof : sig
  type t =
    | Token of Token.t (** they followed the link *)
    | Verified_email
    (** they signed in with a one-time code sent to the invited address; the service must
        only pass this after verifying the address itself *)
end

(** A new pending invitation for [email] with [role], sent now, whose link carries
    [token]. [members] and [invitations] are the organisation's current members and stored
    invitations (all statuses): the address must not belong to a member, must have no
    pending invitation (expired or not), and the organisation must have fewer than
    [max_pending] unexpired pending ones. *)
val create
  :  ?policy:Policy.t
  -> Role_model.t
  -> id:Invitation_id.t
  -> org:Org_id.t
  -> email:Email.t
  -> role:Role.t
  -> ?display_name:string
  -> invited_by:User_id.t
  -> token:Token.t
  -> members:Member.t list
  -> invitations:t list
  -> at:Time_ns.t
  -> unit
  -> (t, Error.t) result

(** What the invitation shows at [now]. *)
val shown : t -> now:Time_ns.t -> Shown.t

(** Pending and not expired at [now]: the link works. *)
val usable : t -> now:Time_ns.t -> bool

(** Sends again with a new token and a fresh lifetime. Works on a pending invitation,
    expired or not. *)
val resend : ?policy:Policy.t -> t -> token:Token.t -> at:Time_ns.t -> (t, Error.t) result

(** Revokes a pending invitation, expired or not. Revoking a revoked invitation returns it
    unchanged (the same request retried); an accepted one fails. *)
val revoke : t -> at:Time_ns.t -> (t, Error.t) result

(** Accepts for [user], who signed in as [email]. Fails unless the invitation is usable,
    [email] is the invited address and the proof holds. The second acceptance of the same
    invitation fails with [Not_pending Accepted]: the token is single-use. *)
val accept
  :  t
  -> proof:Proof.t
  -> user:User_id.t
  -> email:Email.t
  -> at:Time_ns.t
  -> (t, Error.t) result

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
