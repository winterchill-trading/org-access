(** Where organisations, members, invitations, approvals and the audit live.

    Libraries never persist: a service implements this signature over its database, and
    {!Store_memory} serves tests, examples and offline modes. {!Store_conformance} checks
    an implementation against the rules below.

    Rules every implementation keeps:

    - Each write that changes access state takes the audit {!Note} describing it and
      appends those entries in the same atomic step, chained after the organisation's
      latest entry with {!Audit.next}. A change is never stored without its audit, and the
      audit is never edited or deleted.
    - Team, invitation and approval updates are compare-and-set on a version: the write
      happens only if the stored version is still [expected_version], and then the stored
      version becomes [expected_version + 1] (teams) or the new value's [version]
      (invitations and approvals). Otherwise nothing is written and the answer is
      [`Conflict]. That is what stops two concurrent approvals from both being counted as
      the last one, or two administrators from demoting each other.
    - Inserting an invitation fails with [`Duplicate] when its id or token hash exists, or
      when the organisation already has a [Pending] invitation for the address. Inserting
      an approval fails with [`Duplicate] when its id exists. *)

open! Core

module Note : sig
  (** The audit entries one write appends. *)
  type t =
    { at : Time_ns.t
    ; actor : User_id.t option
    ; events : Audit.Event.t list
    }
  [@@deriving sexp_of]
end

module type S = sig
  type 'a io
  type t

  (** {2 Organisations and teams} *)

  (** Stores a new organisation and its founding member (team version 0). [`Exists] when
      the id is taken, with the stored organisation. *)
  val create_organisation
    :  t
    -> Organisation.t
    -> founder:Member.t
    -> Note.t
    -> [ `Created | `Exists of Organisation.t ] io

  (** The organisation's record. *)
  val organisation : t -> Org_id.t -> Organisation.t option io

  (** Replaces an organisation's record (name, status, verification); last writer wins. *)
  val save_organisation : t -> Organisation.t -> Note.t -> unit io

  (** The organisation, its members in any order, and the team version. *)
  val team : t -> Org_id.t -> Team.t option io

  (** Applies member changes if the team version is [expected_version]. *)
  val update_team
    :  t
    -> Org_id.t
    -> expected_version:int
    -> Team.Change.t list
    -> Note.t
    -> [ `Ok | `Conflict ] io

  (** A user's memberships, in every organisation. *)
  val memberships : t -> User_id.t -> Member.t list io

  (** {2 Invitations} *)

  val insert_invitation : t -> Invitation.t -> Note.t -> [ `Ok | `Duplicate ] io

  (** Replaces the invitation if the stored one has version [expected_version]. *)
  val update_invitation
    :  t
    -> Invitation.t
    -> expected_version:int
    -> Note.t
    -> [ `Ok | `Conflict ] io

  (** One invitation by id. *)
  val invitation : t -> Invitation_id.t -> Invitation.t option io
  (** The invitation whose current token has this hash. *)
  val invitation_by_token : t -> Token.Hash.t -> Invitation.t option io

  (** An organisation's invitations, every status, newest first. *)
  val invitations : t -> Org_id.t -> Invitation.t list io

  (** [Pending] invitations to one address in every organisation, oldest first. *)
  val pending_for : t -> Email.t -> Invitation.t list io

  (** {2 Approvals} *)

  val insert_approval : t -> Approval.t -> Note.t -> [ `Ok | `Duplicate ] io

  (** Replaces the approval if the stored one has version [expected_version]. *)
  val update_approval
    :  t
    -> Approval.t
    -> expected_version:int
    -> Note.t
    -> [ `Ok | `Conflict ] io

  (** One approval request by id. *)
  val approval : t -> Approval_id.t -> Approval.t option io

  (** An organisation's approvals, newest first, optionally with one status only. *)
  val approvals : t -> Org_id.t -> status:Approval.Status.t option -> Approval.t list io

  (** {2 Audit} *)

  (** Appends entries that go with no other write (a refused request). *)
  val append_audit : t -> Org_id.t -> Note.t -> unit io

  (** Up to [limit] entries with [seq > after], oldest first. *)
  val audit : t -> Org_id.t -> after:int -> limit:int -> Audit.Entry.t list io
end
