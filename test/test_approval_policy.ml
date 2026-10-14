open! Core
open Money
open Org_access

let a = Amount.of_string

let policy =
  Approval_policy.create_exn
    ~base:1
    [ { above = a "50000.00 EUR"; required = 3 }
    ; { above = a "10000.00 EUR"; required = 2 }
    ; { above = a "8000.00 GBP"; required = 2 }
    ]
;;

let%expect_test "thresholds are strict and per currency" =
  List.iter
    [ "9999.99 EUR"
    ; "10000.00 EUR"
    ; "10000.01 EUR"
    ; "50000.00 EUR"
    ; "50000.01 EUR"
    ; "-20000.00 EUR"
    ; "8000.01 GBP"
    ; "1000000 JPY"
    ]
    ~f:(fun s -> printf "%s -> %d\n" s (Approval_policy.required policy (a s)));
  [%expect
    {|
    9999.99 EUR -> 1
    10000.00 EUR -> 1
    10000.01 EUR -> 2
    50000.00 EUR -> 2
    50000.01 EUR -> 3
    -20000.00 EUR -> 2
    8000.01 GBP -> 2
    1000000 JPY -> 1
    |}]
;;

let%expect_test "unlisted currencies" =
  let strict =
    Approval_policy.create_exn ~unlisted:Strictest ~base:1 (Approval_policy.tiers policy)
  in
  printf "%d\n" (Approval_policy.required strict (a "1 JPY"));
  [%expect {| 3 |}]
;;

let%expect_test "a batch adds same-currency amounts first" =
  let req l = printf "%d\n" (Approval_policy.required_for policy (List.map l ~f:a)) in
  req [];
  req [ "6000.00 EUR"; "6000.00 EUR" ];
  req [ "6000.00 EUR"; "-6000.00 EUR" ];
  req [ "9000.00 EUR"; "9000.00 GBP" ];
  [%expect {|
    1
    2
    2
    2
    |}]
;;

let%expect_test "validation" =
  let try_ ?unlisted ~base tiers =
    print_s
      [%sexp
        (Approval_policy.create ?unlisted ~base tiers |> Or_error.map ~f:ignore
         : unit Or_error.t)]
  in
  try_ ~base:0 [];
  try_ ~base:1 [ { above = a "-1.00 EUR"; required = 2 } ];
  try_ ~base:2 [ { above = a "1.00 EUR"; required = 1 } ];
  try_
    ~base:1
    [ { above = a "1.00 EUR"; required = 2 }; { above = a "1.00 EUR"; required = 3 } ];
  try_
    ~base:1
    [ { above = a "1.00 EUR"; required = 3 }; { above = a "2.00 EUR"; required = 2 } ];
  print_s
    [%sexp
      (Approval_policy.set_tiers
         policy
         Currency.usd
         [ { above = a "1.00 EUR"; required = 2 } ]
       |> Or_error.map ~f:ignore
       : unit Or_error.t)];
  let p = Approval_policy.set_tiers policy Currency.eur [] |> Or_error.ok_exn in
  print_s [%sexp (p : Approval_policy.t)];
  [%expect
    {|
    (Error ("base must be at least 1" (base 0)))
    (Error ("negative threshold" (above "-1.00 EUR")))
    (Error
     ("a tier asks for fewer approvals than the base" (above "1.00 EUR")
      (required 1) (base 2)))
    (Error ("duplicate threshold" (above "1.00 EUR")))
    (Error
     ("a higher threshold asks for fewer approvals" (above "2.00 EUR")
      (required 2) (below 3)))
    (Error ("tier in another currency" (expected USD) (above "1.00 EUR")))
    ((base 1) (tiers (((above "8000.00 GBP") (required 2)))) (unlisted Base))
    |}]
;;

let gen_policy =
  let open Quickcheck.Generator.Let_syntax in
  let%bind base = Int.gen_incl 1 3 in
  let%bind n = Int.gen_incl 0 4 in
  let%map tiers =
    List.gen_with_length
      n
      (let%map cents = Int.gen_incl 0 1_000_000
       and extra = Int.gen_incl 0 3 in
       { Approval_policy.Tier.above = Amount.of_minor_units_int Currency.eur cents
       ; required = base + extra
       })
  in
  (* Sort, drop duplicate thresholds and make counts non-decreasing so the policy is
     valid; [create] itself is tested above. *)
  let tiers =
    List.dedup_and_sort tiers ~compare:(fun (x : Approval_policy.Tier.t) y ->
      Amount.compare x.above y.above)
    |> List.folding_map ~init:base ~f:(fun acc (tier : Approval_policy.Tier.t) ->
      let required = Int.max acc tier.required in
      required, { tier with required })
  in
  Approval_policy.create_exn ~base tiers
;;

let%test_unit "a larger amount never needs fewer approvals" =
  Quickcheck.test
    (Quickcheck.Generator.tuple3
       gen_policy
       (Int.gen_incl 0 2_000_000)
       (Int.gen_incl 0 2_000_000))
    ~sexp_of:[%sexp_of: Approval_policy.t * int * int]
    ~f:(fun (p, x, y) ->
      let x, y = Int.min x y, Int.max x y in
      let r v = Approval_policy.required p (Amount.of_minor_units_int Currency.eur v) in
      assert (r x <= r y);
      assert (r x >= Approval_policy.base p))
;;

let%test_unit "a batch needs at least what each of its lines needs" =
  Quickcheck.test
    (Quickcheck.Generator.both
       gen_policy
       (List.gen_non_empty (Int.gen_incl (-1_000_000) 1_000_000)))
    ~sexp_of:[%sexp_of: Approval_policy.t * int list]
    ~f:(fun (p, lines) ->
      let amounts = List.map lines ~f:(Amount.of_minor_units_int Currency.eur) in
      let batch = Approval_policy.required_for p amounts in
      List.iter amounts ~f:(fun line -> assert (Approval_policy.required p line <= batch)))
;;
