(** The roles an organisation can hand out and what each one may do.

    A model lists its roles from the most to the least privileged. Each role either holds
    every permission ([All], an administrator) or a named set. The model also declares
    every permission the service asks for, so a typo in a role's set is caught when the
    model is built rather than showing up as a permanent refusal.

    One declared permission is the {e custodian} permission, usually the one that lets a
    member manage the team. {!Team} keeps at least one member holding it at all times, so
    an organisation can never lock itself out by demoting or removing its last
    administrator.

    {[
      let model =
        Role_model.create_exn
          ~permissions:[ manage_members; approve; create ]
          ~custodian:manage_members
          [ admin, All; approver, Only [ approve ]; operator, Only [ create ] ]
    ]} *)

open! Core

module Grants : sig
  type t =
    | All (** every permission, declared or not *)
    | Only of Permission.t list (** exactly these *)
  [@@deriving sexp, compare, equal]
end

type t [@@deriving sexp_of, compare, equal]

(** Builds a model. Fails when there are no roles, a role appears twice, a role's set names
    an undeclared permission, or no role holds the custodian permission. *)
val create
  :  permissions:Permission.t list
  -> custodian:Permission.t
  -> (Role.t * Grants.t) list
  -> t Or_error.t

(** [create] that raises. *)
val create_exn
  :  permissions:Permission.t list
  -> custodian:Permission.t
  -> (Role.t * Grants.t) list
  -> t

(** The roles, most privileged first. *)
val roles : t -> Role.t list

(** The declared permissions, sorted. *)
val permissions : t -> Permission.t list

(** The permission some member must always hold. *)
val custodian : t -> Permission.t

(** Whether the model has this role. *)
val mem : t -> Role.t -> bool

(** Position in {!roles}: 0 for the most privileged. [None] for an unknown role. *)
val rank : t -> Role.t -> int option

(** [allows t role permission]: [false] for a role the model does not have. *)
val allows : t -> Role.t -> Permission.t -> bool

(** The declared permissions a role holds, sorted; every declared permission for an [All]
    role. Empty for an unknown role. This is the list a client uses to show or hide
    controls; the server still asks {!Authorize} on every request. *)
val permissions_of : t -> Role.t -> Permission.t list

(** The least privileged role that holds [permission], the one an error message names as
    "required". *)
val lowest_role_with : t -> Permission.t -> Role.t option

(** A four-role model for business banking, described in {!Default}. *)
val default : t

(** The names used by {!default}. *)
module Default : sig
  (** Holds every permission. *)
  val admin : Role.t

  (** Approves payments created by others, and exports. *)
  val approver : Role.t

  (** Prepares payments and manages payees, schedules, rules, cards, cost centres,
      addresses and accounting settings; exports. *)
  val operator : Role.t

  (** Reads and exports. *)
  val viewer : Role.t

  (** [members.manage], the custodian permission: add, change and remove members, send
      invitations. *)
  val manage_members : Permission.t

  (** [policy.manage]: approval thresholds and other organisation settings. *)
  val manage_policy : Permission.t

  (** [verification.manage]: the organisation's business verification file. *)
  val manage_verification : Permission.t

  (** [payments.create]: prepare payments and batches (the maker side). *)
  val create_payments : Permission.t

  (** [payments.approve]: approve or reject what others prepared (the checker side). *)
  val approve_payments : Permission.t

  (** [payees.manage] *)
  val manage_payees : Permission.t

  (** [schedules.manage]: recurring payments. *)
  val manage_schedules : Permission.t

  (** [rules.manage]: automatic treasury rules. *)
  val manage_rules : Permission.t

  (** [cards.manage] *)
  val manage_cards : Permission.t

  (** [cost_centres.manage] *)
  val manage_cost_centres : Permission.t

  (** [addresses.manage]: external wallet addresses. *)
  val manage_addresses : Permission.t

  (** [accounting.manage]: the link to an accounting system. *)
  val manage_accounting : Permission.t

  (** [export]: statements and reports. Every default role has it. *)
  val export : Permission.t
end

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    (** Decoding (bin_prot or sexp) runs the same checks as {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
