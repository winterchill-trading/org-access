open! Core

module type S = sig
  type t [@@deriving sexp, compare, equal, hash]

  include Identifiable.S with type t := t

  val of_string_or_error : string -> t Or_error.t
  val quickcheck_generator : t Quickcheck.Generator.t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end
end

let max_length = 64

let is_id_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' | '.' | ':' -> true
  | _ -> false
;;

let check s =
  let length = String.length s in
  if length = 0
  then Or_error.error_string "empty id"
  else if length > max_length
  then Or_error.error_s [%message "id too long" (length : int) (max_length : int)]
  else if not (String.for_all s ~f:is_id_char)
  then Or_error.error_string "id has a character outside [A-Za-z0-9_.:-]"
  else Ok ()
;;

module Make
    (Name : sig
       val module_name : string
     end)
    () =
struct
  let of_string_or_error s =
    Or_error.map (check s) ~f:(fun () -> s)
    |> Or_error.tag_s ~tag:[%message Name.module_name ~id:(s : string)]
  ;;

  module T = struct
    type t = string [@@deriving compare, equal, hash]

    let module_name = Name.module_name
    let to_string t = t
    let of_string s = Or_error.ok_exn (of_string_or_error s)
    let sexp_of_t = sexp_of_string
    let t_of_sexp sexp = of_string (string_of_sexp sexp)

    (* Decoding goes through [of_string], so a stored record cannot smuggle in an id the
       smart constructor would refuse. *)
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

  let quickcheck_generator =
    let open Quickcheck.Generator.Let_syntax in
    let%bind length = Int.gen_incl 1 8 in
    String.gen_with_length length (Char.gen_uniform_inclusive 'a' 'f')
  ;;

  module Stable = struct
    module V1 = T
  end
end
