open! Core
open Org_access

(* Pinned bin_prot shape digests. A change here means records written by an earlier
   version can no longer be read: add a V2 instead of editing V1. *)
let%expect_test "stable digests" =
  print_endline [%bin_digest: Org_id.Stable.V1.t];
  print_endline [%bin_digest: Role.Stable.V1.t];
  print_endline [%bin_digest: Email.Stable.V1.t];
  print_endline [%bin_digest: Token.Hash.Stable.V1.t];
  print_endline [%bin_digest: Role_model.Stable.V1.t];
  print_endline [%bin_digest: Organisation.Stable.V1.t];
  print_endline [%bin_digest: Member.Stable.V1.t];
  print_endline [%bin_digest: Action.Stable.V1.t];
  print_endline [%bin_digest: Reason.Stable.V1.t];
  print_endline [%bin_digest: Approval_policy.Stable.V1.t];
  print_endline [%bin_digest: Approval.Stable.V1.t];
  print_endline [%bin_digest: Invitation.Stable.V1.t];
  print_endline [%bin_digest: Audit.Stable.Event.V1.t];
  print_endline [%bin_digest: Audit.Stable.Entry.V1.t];
  [%expect {|
    d9a8da25d5656b016fb4dbdc2e4197fb
    d9a8da25d5656b016fb4dbdc2e4197fb
    d9a8da25d5656b016fb4dbdc2e4197fb
    d9a8da25d5656b016fb4dbdc2e4197fb
    4fc8a6c9a2e4a713a57e126043e365ba
    8e8b3f1c949678ccc4b3d7bfadd3d7b9
    96dea43d2df57d8fdacbc46965a8c8dc
    eb55c3229fa55db48b86836a491aae87
    298bd400ff4bde04bc74a5e1199f284c
    f40392eaf7974ee40970654d5082eb52
    14b831271cbecd38590b2ffb31120554
    75c82d66090c840ce80a140c71c1ffd7
    b9a3d017fbaf8c8bbf2c4d151494cf09
    c92e10837ab0ff7910b658a46987ce16
    |}]
;;

let round_trip (type a) (module M : Binable.S with type t = a) ~equal (v : a) =
  let s = Binable.to_string (module M) v in
  assert (equal v (Binable.of_string (module M) s))
;;

let%expect_test "bin_prot round trips" =
  let open Fixtures in
  round_trip (module Role_model.Stable.V1) ~equal:Role_model.equal Role_model.default;
  round_trip (module Member.Stable.V1) ~equal:Member.equal (member "ana" Role_model.Default.admin);
  round_trip
    (module Approval_policy.Stable.V1)
    ~equal:Approval_policy.equal
    (Approval_policy.four_eyes ~above:[ Money.Amount.of_string "10000.00 EUR" ]);
  [%expect {| |}]
;;
