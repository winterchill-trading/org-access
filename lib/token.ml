open! Core

let byte_length = 32
let hex_length = 2 * byte_length
let is_hex = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false
;;

let check_hex s =
  if String.length s = hex_length && String.for_all s ~f:is_hex
  then Ok s
  else Or_error.error_string "expected 64 lower-case hex characters"
;;

let to_hex bytes = Cryptokit.transform_string (Cryptokit.Hexa.encode ()) bytes

type t = string

let sexp_of_t _ = Sexp.Atom "<secret>"

let generate random_bytes =
  let bytes = random_bytes byte_length in
  if String.length bytes <> byte_length
  then raise_s [%message "random source returned the wrong length" ~length:(String.length bytes : int)];
  to_hex bytes
;;

let random () =
  (* Cryptokit's [system_rng] is Windows-only and raises on Unix; read the kernel's
     CSPRNG directly. *)
  let rng = Cryptokit.Random.device_rng "/dev/urandom" in
  Exn.protect
    ~f:(fun () -> generate (fun n -> Cryptokit.Random.string rng n))
    ~finally:(fun () -> rng#wipe)
;;

let to_string t = t

let of_string s = Or_error.tag (check_hex s) ~tag:"Org_access.Token"

module Hash = struct
  module T = struct
    type t = string [@@deriving compare, equal, hash, sexp]

    let of_hex s = Or_error.tag (check_hex s) ~tag:"Org_access.Token.Hash"
    let t_of_sexp sexp = Or_error.ok_exn (of_hex (string_of_sexp sexp))

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (String)
        (struct
          type nonrec t = t

          let to_binable = Fn.id
          let of_binable s = Or_error.ok_exn (of_hex s)
        end)
  end

  include T
  include Comparable.Make (T)

  let to_hex t = t
  let of_hex = T.of_hex

  module Stable = struct
    module V1 = T
  end
end

let hash t = to_hex (Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) t)

let matches t h =
  (* Equal lengths always (both are 64 hex characters), so folding over every byte keeps
     the time independent of where the first difference is. *)
  let a = hash t
  and b = Hash.to_hex h in
  String.length a = String.length b
  && String.foldi a ~init:0 ~f:(fun i acc c ->
    acc lor (Char.to_int c lxor Char.to_int b.[i]))
     = 0
;;
