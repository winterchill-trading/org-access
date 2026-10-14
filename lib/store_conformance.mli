(** Scenarios every {!Store.S} implementation must pass: organisation creation, versioned
    team updates, invitation uniqueness and compare-and-set, approval compare-and-set,
    listing orders, and an audit that grows only with successful writes and verifies as a
    chain. A service runs them against its database store in its own test suite, next to
    {!Store_memory}.

    Give it a fresh, empty store; the scenarios use ids starting with [conformance-]. *)

open! Core

module Make (M : Monad.S) (Store : Store.S with type 'a io := 'a M.t) : sig
  (** [Ok ()] when every scenario passes, otherwise every difference found. *)
  val check : Store.t -> unit Or_error.t M.t
end
