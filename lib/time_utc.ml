open! Core

module T = struct
  type t = Time_ns.Stable.Alternate_sexp.V1.t
  [@@deriving bin_io, sexp, compare, equal, hash]

  type comparator_witness = Time_ns.Alternate_sexp.comparator_witness

  let comparator = Time_ns.Alternate_sexp.comparator
end

include T
include Comparable.Make_using_comparator (T)
