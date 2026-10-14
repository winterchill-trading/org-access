(** An in-memory {!Store.S} for tests, examples and offline modes. Every call completes at
    once, so each one is trivially atomic within one process. Nothing survives a restart. *)

open! Core

module Make (M : Monad.S) : sig
  include Store.S with type 'a io = 'a M.t

  val create : unit -> t

  (** Every organisation's full audit, by organisation then sequence number. *)
  val all_audit : t -> Audit.Entry.t list
end
