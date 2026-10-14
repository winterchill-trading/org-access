(** The members of one organisation and the pure operations that change them.

    Every operation by a member checks that the actor passes {!Authorize.decide} for the
    model's custodian permission (managing the team), then keeps two rules:

    - nobody changes or removes their own membership through team management (they would
      lock themselves out halfway through an edit); {!leave} is the explicit way out;
    - at least one member keeps the custodian permission, so the organisation can always
      be administered.

    An operation returns the new team and the {!Change}s to persist. A team carries the
    [version] it was loaded at; a store applies the changes only if its version is still
    that one ({!Store.S.update_team}), so two administrators demoting each other at the
    same moment cannot both succeed and leave nobody in charge. *)

open! Core

module Change : sig
  type t =
    | Put of Member.t (** insert or replace *)
    | Remove of User_id.t
  [@@deriving sexp, compare, equal]
end

module Policy : sig
  type t = { single_membership : bool (** a user may belong to one organisation only *) }
  [@@deriving sexp, compare, equal]

  (** Users may belong to several organisations. *)
  val default : t
end

module Error : sig
  type t =
    | Denied of Reason.t (** the actor may not manage the team *)
    | Unknown_role of Role.t
    | Already_member
    | Member_elsewhere of Org_id.t (** with [single_membership] *)
    | Not_member
    | Own_membership
    | Last_custodian
    (** the change would leave nobody holding the custodian permission *)
    | Invitation_not_accepted (** {!join} needs an accepted invitation for this user *)
    | Invalid of string
  [@@deriving sexp, compare, equal]

  (** The denial's own code for [Denied]; otherwise [unknown_role], [member_exists],
      [member_elsewhere], [not_member], [own_membership], [last_admin],
      [invitation_not_accepted], [invalid]. *)
  val code : t -> string
end

type t =
  { organisation : Organisation.t
  ; members : Member.t list (** most privileged role first, then by label *)
  ; version : int
  }
[@@deriving sexp_of, compare, equal]

(** A team as loaded from a store. *)
val of_members : Role_model.t -> Organisation.t -> Member.t list -> version:int -> t

(** The first team of a new organisation: its creator, with the most privileged role that
    holds the custodian permission. Version 0. *)
val found
  :  Role_model.t
  -> Organisation.t
  -> email:Email.t
  -> ?display_name:string
  -> at:Time_ns.t
  -> unit
  -> (t * Change.t list, Error.t) result

val find : t -> User_id.t -> Member.t option

(** Members whose role holds the custodian permission. *)
val custodians : Role_model.t -> t -> Member.t list

(** Adds [user] with [role]. [other_memberships] are the user's memberships anywhere,
    checked under [single_membership]. *)
val add
  :  ?policy:Policy.t
  -> Role_model.t
  -> t
  -> actor:Member.t option
  -> user:User_id.t
  -> email:Email.t
  -> ?display_name:string
  -> role:Role.t
  -> other_memberships:Member.t list
  -> at:Time_ns.t
  -> unit
  -> (t * Change.t list, Error.t) result

(** Changes a member's role. Setting the role they have is a no-op with no changes. *)
val change_role
  :  Role_model.t
  -> t
  -> actor:Member.t option
  -> user:User_id.t
  -> role:Role.t
  -> (t * Change.t list, Error.t) result

(** Removes a member. Removing a user who is not a member is a no-op with no changes, so a
    retried request succeeds. *)
val remove
  :  Role_model.t
  -> t
  -> actor:Member.t option
  -> user:User_id.t
  -> (t * Change.t list, Error.t) result

(** A member leaves on their own; refused for the last custodian. *)
val leave : Role_model.t -> t -> user:User_id.t -> (t * Change.t list, Error.t) result

(** Adds the user who accepted [invitation], with its role and display name. *)
val join
  :  ?policy:Policy.t
  -> Role_model.t
  -> t
  -> invitation:Invitation.t
  -> user:User_id.t
  -> other_memberships:Member.t list
  -> at:Time_ns.t
  -> (t * Change.t list, Error.t) result
