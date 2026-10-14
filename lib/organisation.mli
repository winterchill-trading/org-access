(** A business customer: the scope every member, invitation, approval and audit record
    belongs to.

    Two flags gate what members may do, both checked by {!Authorize}: a [Suspended]
    organisation refuses every action, reads included, and an organisation that is not
    [verified] refuses the actions marked as needing verification (moving money, usually)
    until its business verification is approved. Reading and team management stay open
    before verification so the organisation can be set up. *)

open! Core

module Status : sig
  type t =
    | Active
    | Suspended
  [@@deriving bin_io, sexp, compare, equal, hash, enumerate]
end

type t =
  { id : Org_id.t
  ; name : string (** 2 to 120 bytes, whitespace collapsed *)
  ; created_at : Time_utc.t
  ; created_by : User_id.t
  ; status : Status.t
  ; verified : bool
  }
[@@deriving sexp, compare, equal]

(** An active, unverified organisation. Fails on a blank, one-character or over-long name. *)
val create
  :  id:Org_id.t
  -> name:string
  -> created_by:User_id.t
  -> at:Time_ns.t
  -> t Or_error.t

(** Renames, with the same checks as {!create}. *)
val rename : t -> string -> t Or_error.t

(** Records the outcome of business verification. *)
val set_verified : t -> bool -> t

(** Sets the status. *)
val set_status : t -> Status.t -> t

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
