open! Core
open Money

module Tier = struct
  type t =
    { above : Amount.Stable.V1.t
    ; required : int
    }
  [@@deriving bin_io, sexp, compare, equal]
end

module Unlisted = struct
  type t =
    | Base
    | Strictest
  [@@deriving bin_io, sexp, compare, equal, enumerate]
end

module Repr = struct
  type t =
    { base : int
    ; tiers : Tier.t list
    ; unlisted : Unlisted.t
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Repr.t =
  { base : int
  ; tiers : Tier.t list
  ; unlisted : Unlisted.t
  }
[@@deriving compare, equal]

let sexp_of_t = Repr.sexp_of_t

let compare_tier (a : Tier.t) (b : Tier.t) =
  match Currency.compare (Amount.currency a.above) (Amount.currency b.above) with
  | 0 -> Amount.compare a.above b.above
  | c -> c
;;

let check_currency ~base (tiers : Tier.t list) =
  let rec ascending (prev : Tier.t) = function
    | [] -> Ok ()
    | (tier : Tier.t) :: rest ->
      if Amount.compare tier.above prev.above <= 0
      then Or_error.error_s [%message "duplicate threshold" ~above:(tier.above : Amount.t)]
      else if tier.required < prev.required
      then
        Or_error.error_s
          [%message
            "a higher threshold asks for fewer approvals"
              ~above:(tier.above : Amount.t)
              ~required:(tier.required : int)
              ~below:(prev.required : int)]
      else ascending tier rest
  in
  let%bind.Or_error () =
    List.find tiers ~f:(fun tier -> Amount.is_negative tier.above)
    |> Option.value_map ~default:(Ok ()) ~f:(fun tier ->
      Or_error.error_s [%message "negative threshold" ~above:(tier.above : Amount.t)])
  in
  let%bind.Or_error () =
    List.find tiers ~f:(fun tier -> tier.required < base)
    |> Option.value_map ~default:(Ok ()) ~f:(fun tier ->
      Or_error.error_s
        [%message
          "a tier asks for fewer approvals than the base"
            ~above:(tier.above : Amount.t)
            ~required:(tier.required : int)
            (base : int)])
  in
  match tiers with
  | [] -> Ok ()
  | first :: rest -> ascending first rest
;;

let by_currency tiers =
  List.sort tiers ~compare:compare_tier
  |> List.group ~break:(fun (a : Tier.t) (b : Tier.t) ->
    not (Currency.equal (Amount.currency a.above) (Amount.currency b.above)))
;;

let create ?(unlisted = Unlisted.Base) ~base tiers =
  if base < 1
  then Or_error.error_s [%message "base must be at least 1" (base : int)]
  else (
    let groups = by_currency tiers in
    let%map.Or_error () = Or_error.all_unit (List.map groups ~f:(check_currency ~base)) in
    { base; tiers = List.concat groups; unlisted })
;;

let create_exn ?unlisted ~base tiers = Or_error.ok_exn (create ?unlisted ~base tiers)

let four_eyes ~above =
  create_exn ~base:1 (List.map above ~f:(fun above -> { Tier.above; required = 2 }))
;;

let single = create_exn ~base:1 []
let base t = t.base
let tiers t = t.tiers
let unlisted t = t.unlisted

let tiers_of t currency =
  List.filter t.tiers ~f:(fun tier -> Currency.equal (Amount.currency tier.above) currency)
;;

let set_tiers t currency tiers =
  match
    List.find tiers ~f:(fun (tier : Tier.t) ->
      not (Currency.equal (Amount.currency tier.above) currency))
  with
  | Some tier ->
    Or_error.error_s
      [%message
        "tier in another currency"
          ~expected:(currency : Currency.t)
          ~above:(tier.above : Amount.t)]
  | None ->
    let others =
      List.filter t.tiers ~f:(fun tier ->
        not (Currency.equal (Amount.currency tier.above) currency))
    in
    create ~unlisted:t.unlisted ~base:t.base (others @ tiers)
;;

let strictest t =
  List.fold t.tiers ~init:t.base ~f:(fun acc tier -> Int.max acc tier.required)
;;

let required t amount =
  let magnitude = Amount.abs amount in
  match tiers_of t (Amount.currency amount) with
  | [] ->
    (match t.unlisted with
     | Base -> t.base
     | Strictest -> strictest t)
  | tiers ->
    List.fold tiers ~init:t.base ~f:(fun acc (tier : Tier.t) ->
      if Amount.compare magnitude tier.above > 0 then Int.max acc tier.required else acc)
;;

let required_for t amounts =
  (* Totals per currency first: two payments of 6,000 EUR under a 10,000 EUR threshold
     move 12,000 EUR together and need what 12,000 EUR needs. Magnitudes are added, so a
     refund line cannot offset a payment line. *)
  List.map amounts ~f:Amount.abs
  |> List.sort_and_group ~compare:(fun a b ->
    Currency.compare (Amount.currency a) (Amount.currency b))
  |> List.map ~f:(fun group ->
    List.reduce_exn group ~f:Amount.add_exn |> required t)
  |> List.fold ~init:t.base ~f:Int.max
;;

module Stable = struct
  module V1 = struct
    let of_repr (r : Repr.t) = create_exn ~unlisted:r.unlisted ~base:r.base r.tiers

    type nonrec t = t [@@deriving compare, equal]

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Repr)
        (struct
          type nonrec t = t

          let to_binable = Fn.id
          let of_binable = of_repr
        end)

    let sexp_of_t = sexp_of_t
    let t_of_sexp sexp = of_repr (Repr.t_of_sexp sexp)
  end
end
