open! Core

type t =
  | Not_a_member
  | Other_organisation
  | Organisation_suspended
  | Unknown_role of Role.Stable.V1.t
  | Permission_missing of
      { role : Role.Stable.V1.t
      ; permission : Permission.Stable.V1.t
      ; required : Role.Stable.V1.t option
      }
  | Verification_required
[@@deriving bin_io, sexp, compare, equal, hash]

let code = function
  | Not_a_member -> "not_a_member"
  | Other_organisation -> "other_organisation"
  | Organisation_suspended -> "organisation_suspended"
  | Unknown_role _ -> "unknown_role"
  | Permission_missing _ -> "role_required"
  | Verification_required -> "verification_required"
;;

let all_codes =
  let role = Role.of_string "r" in
  List.map
    ~f:code
    [ Not_a_member
    ; Other_organisation
    ; Organisation_suspended
    ; Unknown_role role
    ; Permission_missing { role; permission = Permission.of_string "p"; required = None }
    ; Verification_required
    ]
;;

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
