open! Core

type t =
  { org : Org_id.Stable.V1.t
  ; user : User_id.Stable.V1.t
  ; email : Email.Stable.V1.t
  ; display_name : string option
  ; role : Role.Stable.V1.t
  ; added_at : Time_utc.t
  ; added_by : User_id.Stable.V1.t option
  }
[@@deriving bin_io, sexp, compare, equal]

let create ~org ~user ~email ?(display_name = "") ~role ~added_at ~added_by () =
  let%map.Or_error display_name =
    Text.check_optional ~what:"display name" ~max:70 display_name
  in
  { org; user; email; display_name; role; added_at; added_by }
;;

let label t = Option.value t.display_name ~default:(Email.to_string t.email)

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
