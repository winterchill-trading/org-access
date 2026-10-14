(** Secret single-use tokens, such as the one in an invitation link, and their hashes.

    A token is 32 random bytes written as 64 lower-case hex characters. Only its SHA-256
    {!Hash} is stored, so a leaked database row cannot be turned back into a working link;
    the service looks a presented token up by its hash. A token is never printed: its sexp
    is [<secret>]. *)

open! Core

type t [@@deriving sexp_of]

(** [generate random_bytes] draws 32 bytes from [random_bytes n], which must return [n]
    bytes from a cryptographically secure source. Tests pass a seeded generator. *)
val generate : (int -> string) -> t

(** 32 bytes from [/dev/urandom]. *)
val random : unit -> t

(** The 64-character form to put in a link. *)
val to_string : t -> string

(** Parses a presented token. Fails on anything but 64 lower-case hex characters, before
    any lookup. *)
val of_string : string -> t Or_error.t

module Hash : sig
  (** The SHA-256 of the token's text form, as 64 hex characters. Safe to store and log. *)
  type t [@@deriving sexp, compare, equal, hash]

  include Comparable.S with type t := t

  val to_hex : t -> string
  val of_hex : string -> t Or_error.t

  (** Versioned serializers whose bin_prot shape never changes. *)
  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end
end

val hash : t -> Hash.t

(** [matches t hash] compares in constant time. *)
val matches : t -> Hash.t -> bool
