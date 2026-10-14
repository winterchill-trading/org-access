(** A normalised e-mail address, the key invitations are matched on.

    Normalisation trims surrounding whitespace and lower-cases the whole address. Mail
    systems may in theory treat the local part case-sensitively, but almost none do, and
    an invitation sent to [Ana@Example.com] must be accepted by the person who signs in as
    [ana@example.com]. Validation is deliberately shallow: one [@], a non-empty local
    part, a domain with a dot and no empty labels, no whitespace or control characters,
    254 characters at most. Whether the address receives mail is only known by sending. *)

open! Core

type t [@@deriving sexp, compare, equal, hash]

include Identifiable.S with type t := t

(** Normalises and validates. *)
val of_string_or_error : string -> t Or_error.t

(** The domain part, e.g. [example.com]. *)
val domain : t -> string

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    (** Bin_prot is the normalised string; decoding validates again. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
