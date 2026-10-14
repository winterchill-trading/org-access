(** A user's place in one organisation: their role there and how they got it. *)

open! Core

type t =
  { org : Org_id.t
  ; user : User_id.t
  ; email : Email.t
  ; display_name : string option (** up to 70 bytes, whitespace collapsed *)
  ; role : Role.t
  ; added_at : Time_utc.t
  ; added_by : User_id.t option (** [None] for the organisation's creator *)
  }
[@@deriving sexp, compare, equal]

(** Checks the display name (blank means none). The role is checked against a model by
    {!Team}, not here. *)
val create
  :  org:Org_id.t
  -> user:User_id.t
  -> email:Email.t
  -> ?display_name:string
  -> role:Role.t
  -> added_at:Time_ns.t
  -> added_by:User_id.t option
  -> unit
  -> t Or_error.t

(** The display name if there is one, otherwise the e-mail address. *)
val label : t -> string

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
