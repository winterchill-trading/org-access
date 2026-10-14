(** A point in time whose sexp form is UTC whatever the machine's zone.

    [Time_ns.t]'s own sexp prints in the local zone, so a record printed on a laptop and
    on a CI runner would differ. Every time in this library's records uses this type; it
    is equal to [Time_ns.t]. *)

open! Core

type t = Time_ns.t [@@deriving bin_io, sexp, compare, equal, hash]

include Comparable.S with type t := t
