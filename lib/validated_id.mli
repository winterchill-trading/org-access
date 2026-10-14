(** Identifiers checked once, at the edge.

    An id is 1 to {!max_length} characters from [A-Z a-z 0-9 _ - . :]. That covers UUIDs,
    prefixed ids such as [usr_01H...] and namespaced ids such as [tenant:42], while keeping
    every id safe to print in a log line or an audit record without quoting. *)

open! Core

module type S = sig
  type t [@@deriving sexp, compare, equal, hash]

  include Identifiable.S with type t := t

  (** [of_string] raises on an invalid id; this is the non-raising form. *)
  val of_string_or_error : string -> t Or_error.t

  (** Short ids from a small alphabet, for property tests. *)
  val quickcheck_generator : t Quickcheck.Generator.t

  (** Versioned serializers whose bin_prot shape never changes. *)
  module Stable : sig
    module V1 : sig
      (** Bin_prot is the plain string; decoding checks the id again. *)
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end
end

(** 64 characters. *)
val max_length : int

(** Why [s] is not a valid id, if it is not. *)
val check : string -> unit Or_error.t

(** One fresh id type per use, so a member id cannot be passed where an organisation id is
    expected. *)
module Make
    (_ : sig
       (** Used in error messages, e.g. ["Org_access.Org_id"]. *)
       val module_name : string
     end)
    () : S
