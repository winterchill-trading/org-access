open! Core

module Note = struct
  type t =
    { at : Time_ns.Alternate_sexp.t
    ; actor : User_id.t option
    ; events : Audit.Event.t list
    }
  [@@deriving sexp_of]
end

module type S = sig
  type 'a io
  type t

  val create_organisation
    :  t
    -> Organisation.t
    -> founder:Member.t
    -> Note.t
    -> [ `Created | `Exists of Organisation.t ] io

  val organisation : t -> Org_id.t -> Organisation.t option io
  val save_organisation : t -> Organisation.t -> Note.t -> unit io
  val team : t -> Org_id.t -> Team.t option io

  val update_team
    :  t
    -> Org_id.t
    -> expected_version:int
    -> Team.Change.t list
    -> Note.t
    -> [ `Ok | `Conflict ] io

  val memberships : t -> User_id.t -> Member.t list io
  val insert_invitation : t -> Invitation.t -> Note.t -> [ `Ok | `Duplicate ] io

  val update_invitation
    :  t
    -> Invitation.t
    -> expected_version:int
    -> Note.t
    -> [ `Ok | `Conflict ] io

  val invitation : t -> Invitation_id.t -> Invitation.t option io
  val invitation_by_token : t -> Token.Hash.t -> Invitation.t option io
  val invitations : t -> Org_id.t -> Invitation.t list io
  val pending_for : t -> Email.t -> Invitation.t list io
  val insert_approval : t -> Approval.t -> Note.t -> [ `Ok | `Duplicate ] io

  val update_approval
    :  t
    -> Approval.t
    -> expected_version:int
    -> Note.t
    -> [ `Ok | `Conflict ] io

  val approval : t -> Approval_id.t -> Approval.t option io
  val approvals : t -> Org_id.t -> status:Approval.Status.t option -> Approval.t list io
  val append_audit : t -> Org_id.t -> Note.t -> unit io
  val audit : t -> Org_id.t -> after:int -> limit:int -> Audit.Entry.t list io
end
