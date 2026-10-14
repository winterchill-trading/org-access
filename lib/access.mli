(** The operations a service exposes, over any {!Store.S}: each one loads what it needs,
    runs the pure decision ({!Authorize}, {!Team}, {!Invitation}, {!Approval}), writes the
    result with its audit entries, and retries when a concurrent write got there first.

    The functor is over a monad so the same code runs on [Async.Deferred] against a
    database and on [Monad.Ident] against {!Store_memory} in tests.

    Ids of new invitations and approvals come from the caller (services usually derive
    them from the request's idempotency key, so a retried request finds the record it
    already made and gets [Error Exists]).

    A resource of another organisation is reported as [Not_found], like a missing one, so
    ids cannot be probed across organisations. Refusals for reasons of access (role,
    verification, outsiders) are appended to the organisation's audit as [Access_denied]
    when [audit_denials] is set. *)

open! Core
open Money

module Config : sig
  type t =
    { model : Role_model.t
    ; team_policy : Team.Policy.t
    ; invitation_policy : Invitation.Policy.t
    ; new_token : unit -> Token.t (** {!Token.random} outside tests *)
    ; audit_denials : bool
    ; max_attempts : int
    (** tries of a versioned write before giving up with [Conflict] *)
    }

  (** The default model and policies, random tokens, denials audited, three attempts. *)
  val default : t
end

module Error : sig
  type t =
    | Not_found
    | Exists (** an organisation, invitation or approval with this id exists already *)
    | Denied of Reason.t
    | Team of Team.Error.t
    | Invitation of Invitation.Error.t
    | Approval of Approval.Error.t
    | Conflict (** concurrent writes won every attempt; the request may be retried *)
  [@@deriving sexp_of, compare, equal]

  (** The inner error's code; [not_found], [exists] and [conflict] otherwise. *)
  val code : t -> string
end

module Make (M : Monad.S) (S : Store.S with type 'a io := 'a M.t) : sig
  (** {2 Organisations} *)

  (** Creates an organisation with [creator] as its first member, in the model's most
      privileged role holding the custodian permission. *)
  val create_organisation
    :  Config.t
    -> S.t
    -> id:Org_id.t
    -> name:string
    -> creator:User_id.t
    -> email:Email.t
    -> ?display_name:string
    -> at:Time_ns.t
    -> unit
    -> (Team.t, Error.t) result M.t

  (** Records the outcome of business verification. [actor] is [None] when it comes from a
      verification provider. *)
  val set_verified
    :  S.t
    -> Org_id.t
    -> bool
    -> actor:User_id.t option
    -> at:Time_ns.t
    -> (Organisation.t, Error.t) result M.t

  (** Suspends or reactivates an organisation (an operator's action, outside the
      organisation's own roles). *)
  val set_status
    :  S.t
    -> Org_id.t
    -> Organisation.Status.t
    -> actor:User_id.t option
    -> at:Time_ns.t
    -> (Organisation.t, Error.t) result M.t

  (** {2 Decisions} *)

  (** Loads the organisation and the user's memberships and decides. A refusal is audited
      (see the module comment). An unknown organisation is [Denied Other_organisation] for
      a user with a membership elsewhere, [Not_a_member] otherwise. *)
  val authorize
    :  Config.t
    -> S.t
    -> user:User_id.t
    -> org:Org_id.t
    -> Action.t
    -> at:Time_ns.t
    -> Authorize.Decision.t M.t

  (** The team, for a member of it (any role). *)
  val team
    :  Config.t
    -> S.t
    -> user:User_id.t
    -> org:Org_id.t
    -> at:Time_ns.t
    -> (Team.t, Error.t) result M.t

  (** {2 Team management} *)

  val add_member
    :  Config.t
    -> S.t
    -> actor:User_id.t
    -> org:Org_id.t
    -> user:User_id.t
    -> email:Email.t
    -> ?display_name:string
    -> role:Role.t
    -> at:Time_ns.t
    -> unit
    -> (Member.t, Error.t) result M.t

  (** Changes a member's role; setting the role they have writes nothing. *)
  val change_role
    :  Config.t
    -> S.t
    -> actor:User_id.t
    -> org:Org_id.t
    -> user:User_id.t
    -> role:Role.t
    -> at:Time_ns.t
    -> (Member.t, Error.t) result M.t

  (** Succeeds, writing nothing, when [user] is not a member. *)
  val remove_member
    :  Config.t
    -> S.t
    -> actor:User_id.t
    -> org:Org_id.t
    -> user:User_id.t
    -> at:Time_ns.t
    -> (unit, Error.t) result M.t

  (** The member leaves the organisation; refused for the last custodian. *)
  val leave
    :  Config.t
    -> S.t
    -> user:User_id.t
    -> org:Org_id.t
    -> at:Time_ns.t
    -> (unit, Error.t) result M.t

  (** {2 Invitations} *)

  (** Creates and stores an invitation; returns it with the token to put in the link (the
      only time the token exists outside the e-mail). *)
  val invite
    :  Config.t
    -> S.t
    -> actor:User_id.t
    -> org:Org_id.t
    -> id:Invitation_id.t
    -> email:Email.t
    -> role:Role.t
    -> ?display_name:string
    -> at:Time_ns.t
    -> unit
    -> (Invitation.t * Token.t, Error.t) result M.t

  (** Rotates the token and restarts the validity. *)
  val resend
    :  Config.t
    -> S.t
    -> actor:User_id.t
    -> org:Org_id.t
    -> id:Invitation_id.t
    -> at:Time_ns.t
    -> (Invitation.t * Token.t, Error.t) result M.t

  (** Revokes a pending invitation; revoking a revoked one writes nothing. *)
  val revoke
    :  Config.t
    -> S.t
    -> actor:User_id.t
    -> org:Org_id.t
    -> id:Invitation_id.t
    -> at:Time_ns.t
    -> (Invitation.t, Error.t) result M.t

  (** What a public invitation page shows before sign-in: [None] for anything but a usable
      invitation, so the page cannot tell an expired link from a wrong one. *)
  val preview
    :  S.t
    -> token:Token.t
    -> at:Time_ns.t
    -> (Organisation.t * Invitation.t) option M.t

  (** Accepts the invitation behind a link for a signed-in [user] whose address is
      [email], making them a member.

      The membership is written first and the invitation marked accepted second, so a
      crash in between leaves a member with a pending invitation, which the next attempt
      finishes; never an accepted invitation without its member. *)
  val accept_link
    :  Config.t
    -> S.t
    -> token:Token.t
    -> user:User_id.t
    -> email:Email.t
    -> at:Time_ns.t
    -> (Member.t, Error.t) result M.t

  (** Accepts the oldest usable invitation to [email], for a sign-in that proved the
      address. [Ok None] when there is none. *)
  val accept_pending
    :  Config.t
    -> S.t
    -> user:User_id.t
    -> email:Email.t
    -> at:Time_ns.t
    -> (Member.t option, Error.t) result M.t

  (** {2 Approvals} *)

  (** Opens a request by [maker]. With [maker_action], the maker must pass
      {!Authorize.decide} for it first (creating a payment, say). Fails with
      [Not_enough_approvers] when the current team could never approve it. *)
  val open_approval
    :  Config.t
    -> S.t
    -> maker:User_id.t
    -> org:Org_id.t
    -> id:Approval_id.t
    -> policy:Approval_policy.t
    -> subject:string
    -> action:Action.t
    -> amounts:Amount.t list
    -> ?maker_action:Action.t
    -> at:Time_ns.t
    -> unit
    -> (Approval.t, Error.t) result M.t

  (** Records the user's approval; the result says whether the request is now approved. *)
  val approve
    :  Config.t
    -> S.t
    -> user:User_id.t
    -> org:Org_id.t
    -> id:Approval_id.t
    -> ?note:string
    -> at:Time_ns.t
    -> unit
    -> (Approval.t * Approval.Progress.t, Error.t) result M.t

  (** Ends a pending request as rejected. *)
  val reject
    :  Config.t
    -> S.t
    -> user:User_id.t
    -> org:Org_id.t
    -> id:Approval_id.t
    -> ?note:string
    -> at:Time_ns.t
    -> unit
    -> (Approval.t, Error.t) result M.t

  (** The maker, or a member holding the model's custodian permission, may cancel. *)
  val cancel
    :  Config.t
    -> S.t
    -> user:User_id.t
    -> org:Org_id.t
    -> id:Approval_id.t
    -> ?note:string
    -> at:Time_ns.t
    -> unit
    -> (Approval.t, Error.t) result M.t

  (** {2 Audit} *)

  (** A page of the organisation's audit for a member holding [permission] (the custodian
      permission by default). *)
  val audit
    :  Config.t
    -> S.t
    -> user:User_id.t
    -> org:Org_id.t
    -> ?permission:Permission.t
    -> after:int
    -> limit:int
    -> at:Time_ns.t
    -> unit
    -> (Audit.Entry.t list, Error.t) result M.t
end
