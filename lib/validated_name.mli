(** Lower-case names checked at the edge, the shared shape of {!Role} and {!Permission}. *)

open! Core

module type S = sig
  type t [@@deriving sexp, compare, equal, hash]

  include Identifiable.S with type t := t

  (** [of_string] raises on an invalid name; this is the non-raising form. *)
  val of_string_or_error : string -> t Or_error.t

  (** Versioned serializers whose bin_prot shape never changes. *)
  module Stable : sig
    module V1 : sig
      (** Bin_prot is the plain string; decoding checks the name again. *)
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end
end

(** One fresh name type per use. *)
module Make (_ : sig
    (** Used in error messages. *)
    val module_name : string

    (** [Ok ()] for a valid name. *)
    val check : string -> unit Or_error.t
  end) : S
