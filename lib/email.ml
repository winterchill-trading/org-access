open! Core

let max_length = 254

let check s =
  let length = String.length s in
  if length = 0 || length > max_length
  then Or_error.error_s [%message "e-mail address must be 1 to 254 characters" (length : int)]
  else if String.exists s ~f:(fun c -> Char.is_whitespace c || Char.to_int c < 0x20 || Char.to_int c = 0x7f)
  then Or_error.error_string "e-mail address has whitespace or a control character"
  else (
    match String.split s ~on:'@' with
    | [ local; domain ] ->
      let labels = String.split domain ~on:'.' in
      if String.is_empty local
      then Or_error.error_string "e-mail address has an empty local part"
      else if List.length labels < 2 || List.exists labels ~f:String.is_empty
      then Or_error.error_string "e-mail domain must have a dot and no empty labels"
      else Ok ()
    | _ -> Or_error.error_string "e-mail address must have exactly one '@'")
;;

let normalise s = String.lowercase (String.strip s)

let of_string_or_error raw =
  let s = normalise raw in
  Or_error.map (check s) ~f:(fun () -> s)
  |> Or_error.tag_s ~tag:[%message "Org_access.Email" ~address:(raw : string)]
;;

module T = struct
  type t = string [@@deriving compare, equal, hash]

  let module_name = "Org_access.Email"
  let to_string t = t
  let of_string s = Or_error.ok_exn (of_string_or_error s)
  let sexp_of_t = sexp_of_string
  let t_of_sexp sexp = of_string (string_of_sexp sexp)

  include
    Binable.Of_binable_without_uuid [@alert "-legacy"]
      (String)
      (struct
        type t = string

        let to_binable = Fn.id
        let of_binable = of_string
      end)
end

include T
include Identifiable.Make (T)

let domain t = String.drop_prefix t (String.index_exn t '@' + 1)

module Stable = struct
  module V1 = T
end
