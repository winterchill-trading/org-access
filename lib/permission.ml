open! Core

let check_segment segment =
  if String.is_empty segment
  then Or_error.error_string "permission has an empty segment"
  else if not (Char.is_lowercase segment.[0])
  then Or_error.error_string "permission segment must start with a lower-case letter"
  else if
    not
      (String.for_all segment ~f:(fun c ->
         Char.is_lowercase c || Char.is_digit c || Char.equal c '_'))
  then Or_error.error_string "permission has a character outside [a-z0-9_.]"
  else Ok ()
;;

let check s =
  let length = String.length s in
  if length = 0 || length > 64
  then Or_error.error_s [%message "permission must be 1 to 64 characters" (length : int)]
  else Or_error.all_unit (List.map (String.split s ~on:'.') ~f:check_segment)
;;

include Validated_name.Make (struct
    let module_name = "Org_access.Permission"
    let check = check
  end)
