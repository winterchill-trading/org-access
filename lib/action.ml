open! Core

type t =
  { permission : Permission.Stable.V1.t option
  ; needs_verification : bool
  }
[@@deriving bin_io, sexp, compare, equal, hash]

let read = { permission = None; needs_verification = false }
let requires p = { permission = Some p; needs_verification = false }
let requires_verified p = { permission = Some p; needs_verification = true }

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
