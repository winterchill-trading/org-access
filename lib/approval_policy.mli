(** How many distinct approvers an amount needs: maker-checker thresholds expressed as
    money amounts, per currency.

    Every request needs [base] approvals (usually one: someone other than the maker). Each
    currency may list tiers: an amount {e strictly above} a tier's threshold needs that
    tier's count. The common four-eyes rule "two approvers above 10,000.00 EUR" is one
    tier:

    {[
      Approval_policy.create_exn
        ~base:1
        [ { above = Amount.of_string "10000.00 EUR"; required = 2 } ]
    ]}

    Thresholds are compared in the amount's own currency, never converted: a policy that
    wants a single limit across currencies lists one tier per currency, which also keeps a
    decision independent of exchange rates that move between the request and the last
    approval. A request in several currencies (a batch of payments) needs the largest
    count any of its per-currency totals needs. *)

open! Core
open Money

module Tier : sig
  type t =
    { above : Amount.t
    (** compared with [>]: an amount equal to it does not need [required] *)
    ; required : int
    }
  [@@deriving sexp, compare, equal]
end

(** What a currency without tiers needs. *)
module Unlisted : sig
  type t =
    | Base (** [base] approvals *)
    | Strictest (** the largest count of any tier in any currency *)
  [@@deriving sexp, compare, equal, enumerate]
end

type t [@@deriving sexp_of, compare, equal]

(** Fails when [base < 1], a threshold is negative, a tier asks for fewer than [base], or
    within one currency the thresholds are not strictly increasing or the counts decrease.
    Tiers may be given in any order. [unlisted] defaults to [Base]. *)
val create : ?unlisted:Unlisted.t -> base:int -> Tier.t list -> t Or_error.t

(** [create] that raises. *)
val create_exn : ?unlisted:Unlisted.t -> base:int -> Tier.t list -> t

(** One approver below the thresholds, two above: the classic four-eyes policy with one
    threshold per currency. *)
val four_eyes : above:Amount.t list -> t

(** One approver for everything. *)
val single : t

(** The approvals needed without any tier. *)
val base : t -> int

(** The tiers, by currency then threshold. *)
val tiers : t -> Tier.t list

(** The tiers of one currency, by threshold. *)
val tiers_of : t -> Currency.t -> Tier.t list

val unlisted : t -> Unlisted.t

(** Replaces one currency's tiers, with the checks of {!create}. *)
val set_tiers : t -> Currency.t -> Tier.t list -> t Or_error.t

(** Approvals needed for one amount. The magnitude counts: a refund of -20,000 EUR needs
    what 20,000 EUR needs. *)
val required : t -> Amount.t -> int

(** Approvals needed for a request moving all of [amounts]: amounts of the same currency
    are added first, then the largest count wins. [base] for an empty list. *)
val required_for : t -> Amount.t list -> int

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    (** Decoding runs the checks of {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
