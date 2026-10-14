(** What a request asks to do, as far as authorization is concerned.

    A service maps each of its operations to an action once, next to the route, and asks
    {!Authorize.decide} with it on every request. *)

open! Core

type t =
  { permission : Permission.t option (** [None]: any member may *)
  ; needs_verification : bool
  (** refused until the organisation's business verification is approved *)
  }
[@@deriving sexp, compare, equal, hash]

(** Any member, verified or not: reading, mostly. *)
val read : t

(** Needs [permission]; allowed before verification (settings, team management). *)
val requires : Permission.t -> t

(** Needs [permission] and a verified organisation (moving money). *)
val requires_verified : Permission.t -> t

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
