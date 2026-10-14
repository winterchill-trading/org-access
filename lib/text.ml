open! Core

let collapse_whitespace s =
  String.split_on_chars s ~on:[ ' '; '\t'; '\n'; '\r' ]
  |> List.filter ~f:(Fn.non String.is_empty)
  |> String.concat ~sep:" "
;;

let has_control s = String.exists s ~f:(fun c -> Char.to_int c < 0x20 || Char.to_int c = 0x7f)

let check ~what ~max raw =
  let s = collapse_whitespace raw in
  let length = String.length s in
  if length = 0
  then Or_error.error_s [%message "blank" (what : string)]
  else if length > max
  then Or_error.error_s [%message "too long" (what : string) (length : int) (max : int)]
  else if has_control s
  then Or_error.error_s [%message "control character" (what : string)]
  else Ok s
;;

let check_optional ~what ~max raw =
  if String.is_empty (collapse_whitespace raw)
  then Ok None
  else Or_error.map (check ~what ~max raw) ~f:Option.some
;;
