open! Core

module type S = sig
  type t [@@deriving sexp, compare, equal, hash]

  include Identifiable.S with type t := t

  val of_string_or_error : string -> t Or_error.t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
    end
  end
end

module Make (Rule : sig
    val module_name : string
    val check : string -> unit Or_error.t
  end) =
struct
  let of_string_or_error s =
    Or_error.map (Rule.check s) ~f:(fun () -> s)
    |> Or_error.tag_s ~tag:[%message Rule.module_name ~name:(s : string)]
  ;;

  module T = struct
    type t = string [@@deriving compare, equal, hash]

    let module_name = Rule.module_name
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

  module Stable = struct
    module V1 = T
  end
end
