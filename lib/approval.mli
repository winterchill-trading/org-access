(** A maker-checker approval: a request one member makes that other members must approve
    before it takes effect.

    The maker opens the request with the amounts it moves; the {!Approval_policy} fixes
    how many approvals it needs at that moment, and later policy changes do not move the
    goal of an open request. Each approval comes from a distinct member who passes
    {!Authorize.decide} for the request's action and is not the maker. When the count
    reaches the requirement the request is [Approved]; one rejection ends it as
    [Rejected]; the maker (or a member holding the cancel-override permission) may
    [Cancel] it while it is pending.

    Every transition is a pure function returning the new value with its [version]
    increased by one. A store saves it only if the stored version is still the one the
    transition started from, so two approvers clicking at once cannot both be counted as
    the last approval, and neither vote is lost (see {!Store.S.update_approval}).

    Approvals already recorded stay counted if the approver later leaves the organisation
    or changes role: they were entitled when they approved, and the audit shows it. *)

open! Core
open Money

module Status : sig
  type t =
    | Pending
    | Approved
    | Rejected
    | Cancelled
  [@@deriving bin_io, sexp, compare, equal, hash, enumerate]

  (** [pending], [approved], [rejected], [cancelled]. *)
  val to_string : t -> string
end

module Vote : sig
  type t =
    { by : User_id.t
    ; at : Time_utc.t
    ; note : string option (** up to 200 bytes *)
    }
  [@@deriving sexp, compare, equal]
end

type t =
  { id : Approval_id.t
  ; org : Org_id.t
  ; subject : string
  (** what is being approved, in the service's words: ["payout-batch:42"]; 1 to 128 bytes *)
  ; action : Action.t (** what an approver must be allowed to do *)
  ; maker : User_id.t
  ; amounts : Amount.t list
  ; required : int
  ; approvals : Vote.t list (** oldest first, distinct voters *)
  ; status : Status.t
  ; decision : Vote.t option (** who rejected or cancelled, and why *)
  ; created_at : Time_utc.t
  ; version : int (** 0 when opened, then one more per transition *)
  }
[@@deriving sexp, compare, equal]

module Error : sig
  type t =
    | Denied of Reason.t (** the member fails {!Authorize.decide} for the action *)
    | Own_request (** the maker cannot approve or reject their own request *)
    | Already_approved (** this member has approved already *)
    | Not_pending of Status.t
    | Not_enough_approvers of
        { required : int
        ; eligible : int
        }
    (** fewer members than [required], maker excluded, could ever approve *)
    | Not_canceller (** cancelling needs the maker or the override permission *)
    | Invalid of string (** a subject or note out of bounds *)
  [@@deriving sexp, compare, equal]

  (** The denial's own code for [Denied]; otherwise [own_request], [already_approved],
      [not_pending], [not_enough_approvers], [not_canceller], [invalid]. *)
  val code : t -> string
end

(** The outcome of a successful {!approve}. *)
module Progress : sig
  type t =
    | Recorded of
        { approvals : int
        ; required : int
        }
    | Completed
  [@@deriving sexp, compare, equal]
end

(** Opens a request by [maker], who must be a member of [organisation] (the maker's own
    right to make it is the service's earlier {!Authorize.decide} call). [required] is
    {!Approval_policy.required_for} [amounts].

    When [members] (the organisation's current members) is given, opening fails with
    [Not_enough_approvers] if fewer of them than [required], the maker excluded, pass
    {!Authorize.decide} for [action]: such a request could never be approved. *)
val open_
  :  Role_model.t
  -> Approval_policy.t
  -> id:Approval_id.t
  -> organisation:Organisation.t
  -> maker:Member.t
  -> subject:string
  -> action:Action.t
  -> amounts:Amount.t list
  -> ?members:Member.t list
  -> at:Time_ns.t
  -> unit
  -> (t, Error.t) result

(** Records [membership]'s approval. Fails unless the request is pending, the member
    passes {!Authorize.decide} for the request's action in [organisation], is not the
    maker and has not approved yet. *)
val approve
  :  t
  -> Role_model.t
  -> organisation:Organisation.t
  -> membership:Member.t option
  -> ?note:string
  -> at:Time_ns.t
  -> unit
  -> (t * Progress.t, Error.t) result

(** Ends a pending request as [Rejected]. Same eligibility as {!approve}, except that a
    member who already approved may still reject (they may have spotted a problem). *)
val reject
  :  t
  -> Role_model.t
  -> organisation:Organisation.t
  -> membership:Member.t option
  -> ?note:string
  -> at:Time_ns.t
  -> unit
  -> (t, Error.t) result

(** Ends a pending request as [Cancelled]. Allowed to the maker, and to a member whose
    role holds [override] (for example a team administrator cleaning up after a maker
    who left), both while a member of [organisation]. *)
val cancel
  :  t
  -> Role_model.t
  -> organisation:Organisation.t
  -> membership:Member.t option
  -> ?override:Permission.t
  -> ?note:string
  -> at:Time_ns.t
  -> unit
  -> (t, Error.t) result

(** Approvals still missing; 0 once approved. *)
val remaining : t -> int

(** Whether [user] may still approve: what a client uses to show the button. *)
val can_approve
  :  t
  -> Role_model.t
  -> organisation:Organisation.t
  -> membership:Member.t option
  -> bool

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
