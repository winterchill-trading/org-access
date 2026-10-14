open! Core

let check s =
  let length = String.length s in
  if length = 0 || length > 32
  then Or_error.error_s [%message "role name must be 1 to 32 characters" (length : int)]
  else if not (Char.is_lowercase s.[0])
  then Or_error.error_string "role name must start with a lower-case letter"
  else if
    not
      (String.for_all s ~f:(fun c -> Char.is_lowercase c || Char.is_digit c || Char.equal c '_'))
  then Or_error.error_string "role name has a character outside [a-z0-9_]"
  else Ok ()
;;

include Validated_name.Make (struct
    let module_name = "Org_access.Role"
    let check = check
  end)
