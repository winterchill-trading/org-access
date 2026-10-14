(** Why {!Authorize.decide} refused, with a stable snake_case code for clients and logs.

    The codes are part of the public contract: renaming one breaks every client that
    branches on it, so add a constructor instead. *)

open! Core

type t =
  | Not_a_member (** the user belongs to no organisation *)
  | Other_organisation
  (** the resource belongs to another organisation; answer as if it did not exist, so ids
      from other organisations cannot be probed *)
  | Organisation_suspended
  | Unknown_role of Role.t
  (** the member's stored role is not in the model (a model changed without migrating
      members); refused rather than guessed *)
  | Permission_missing of
      { role : Role.t
      ; permission : Permission.t
      ; required : Role.t option
      (** the least privileged role holding the permission, for the message *)
      }
  | Verification_required
[@@deriving sexp, compare, equal, hash]

(** [not_a_member], [other_organisation], [organisation_suspended], [unknown_role],
    [role_required], [verification_required]. *)
val code : t -> string

(** Every code, for checking a client's message catalogue. *)
val all_codes : string list

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
