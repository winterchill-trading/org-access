open! Core

module Status = struct
  type t =
    | Active
    | Suspended
  [@@deriving bin_io, sexp, compare, equal, hash, enumerate]
end

type t =
  { id : Org_id.Stable.V1.t
  ; name : string
  ; created_at : Time_utc.t
  ; created_by : User_id.Stable.V1.t
  ; status : Status.t
  ; verified : bool
  }
[@@deriving bin_io, sexp, compare, equal]

let check_name name =
  let%bind.Or_error name = Text.check ~what:"organisation name" ~max:120 name in
  if String.length name < 2
  then Or_error.error_string "organisation name must be at least 2 characters"
  else Ok name
;;

let create ~id ~name ~created_by ~at =
  let%map.Or_error name = check_name name in
  { id; name; created_at = at; created_by; status = Active; verified = false }
;;

let rename t name =
  let%map.Or_error name = check_name name in
  { t with name }
;;

let set_verified t verified = { t with verified }
let set_status t status = { t with status }

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
