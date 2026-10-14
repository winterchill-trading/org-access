(** The append-only access audit: who changed membership, roles, invitations and
    approvals, and which requests were refused.

    Each organisation has its own chain of entries numbered from 1. Every entry stores the
    digest of the one before it and its own digest, a SHA-256 over the entry's stable
    binary form, so deleting, reordering or editing a stored entry breaks {!verify} from
    that point on. The chain is evidence of tampering, not protection against it: someone
    who can rewrite the whole table can rebuild the chain too, which is why services also
    export the latest digest somewhere else (a log line, a daily report). *)

open! Core

module Event : sig
  type t =
    | Organisation_created of { name : string }
    | Organisation_status_changed of { status : Organisation.Status.t }
    | Organisation_verified of { verified : bool }
    | Member_added of
        { user : User_id.t
        ; role : Role.t
        ; invitation : Invitation_id.t option
        }
    | Role_changed of
        { user : User_id.t
        ; from : Role.t
        ; to_ : Role.t
        }
    | Member_removed of
        { user : User_id.t
        ; role : Role.t
        ; left : bool (** they left on their own *)
        }
    | Invitation_sent of
        { invitation : Invitation_id.t
        ; email : Email.t
        ; role : Role.t
        ; resend : bool
        }
    | Invitation_revoked of { invitation : Invitation_id.t }
    | Invitation_accepted of
        { invitation : Invitation_id.t
        ; user : User_id.t
        }
    | Approval_policy_changed of { policy : Approval_policy.t }
    | Approval_opened of
        { approval : Approval_id.t
        ; subject : string
        ; required : int
        }
    | Approval_approved of
        { approval : Approval_id.t
        ; approvals : int
        ; required : int
        }
    | Approval_rejected of { approval : Approval_id.t }
    | Approval_cancelled of { approval : Approval_id.t }
    | Access_denied of
        { action : Action.t
        ; code : string (** the refusal's reason code *)
        }
  [@@deriving sexp, compare, equal]

  (** A short snake_case name: [member_added], [access_denied], ... *)
  val kind : t -> string
end

module Digest : sig
  (** SHA-256, as 64 hex characters. *)
  type t [@@deriving sexp, compare, equal, hash]

  val to_hex : t -> string

  (** The [prev] of an organisation's first entry: the digest of its id, so two
      organisations' chains never share a digest. *)
  val genesis : Org_id.t -> t
end

module Entry : sig
  type t =
    { org : Org_id.t
    ; seq : int (** 1 for the organisation's first entry *)
    ; at : Time_utc.t
    ; actor : User_id.t option (** [None] for the system (an expiry sweep, a provider) *)
    ; event : Event.t
    ; prev : Digest.t
    ; digest : Digest.t
    }
  [@@deriving sexp, compare, equal]
end

(** The entry that follows [last] (the organisation's latest entry, [None] for the
    first). Fails when [last] belongs to another organisation. *)
val next
  :  last:Entry.t option
  -> org:Org_id.t
  -> at:Time_ns.t
  -> actor:User_id.t option
  -> Event.t
  -> Entry.t Or_error.t

module Broken : sig
  type t =
    | Wrong_organisation of { seq : int }
    | Gap of
        { expected : int
        ; found : int
        }
    | Prev_mismatch of { seq : int }
    | Digest_mismatch of { seq : int }
  [@@deriving sexp, compare, equal]
end

(** Checks a run of consecutive entries, oldest first. Without [after] the run must
    start at the organisation's first entry; with it, the run continues that entry (for
    checking a page at a time). *)
val verify : ?after:Entry.t -> Org_id.t -> Entry.t list -> (unit, Broken.t) result

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module Event : sig
    module V1 : sig
      type t = Event.t [@@deriving bin_io, sexp, compare, equal]
    end
  end

  module Entry : sig
    module V1 : sig
      type t = Entry.t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end
