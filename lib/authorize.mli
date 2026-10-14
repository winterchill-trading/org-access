(** The authorization decision: may this user do this action on a resource of this
    organisation?

    {!decide} is a pure function of its arguments, with no clock, store or randomness, so
    a decision can be replayed from the audit and tested exhaustively. The checks run in a
    fixed order and the first failure is the reason:

    + the user has a membership ([Not_a_member]);
    + the membership is in the resource's organisation ([Other_organisation]);
    + the organisation is active ([Organisation_suspended]);
    + the member's role is in the model ([Unknown_role]);
    + the role holds the action's permission, if it names one ([Permission_missing]);
    + the organisation is verified, if the action needs it ([Verification_required]).

    Membership comes before everything else so that a user outside the organisation learns
    nothing about it, not even that it is suspended. *)

open! Core

module Decision : sig
  type t =
    | Allowed of { role : Role.t }
    | Denied of Reason.t
  [@@deriving sexp, compare, equal]

  (** [true] for [Allowed]. *)
  val is_allowed : t -> bool

  (** [Error] carries the reason as a sexp. *)
  val to_or_error : t -> unit Or_error.t
end

(** [decide model ~organisation ~membership action].

    [organisation] is the one the resource belongs to (for an organisation-wide action,
    the caller's own). [membership] is the caller's membership, wherever it is, or [None]
    when they have none. *)
val decide
  :  Role_model.t
  -> organisation:Organisation.t
  -> membership:Member.t option
  -> Action.t
  -> Decision.t

(** [scope ~membership org] is the first two checks alone: [Ok member] when [membership]
    is in [org]. For list queries, which filter by organisation instead of deciding per
    row. *)
val scope : membership:Member.t option -> Org_id.t -> (Member.t, Reason.t) result
