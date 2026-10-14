open! Core
open Org_access
module Memory = Store_memory.Make (Monad.Ident)
module Conformance = Store_conformance.Make (Monad.Ident) (Memory)

let%expect_test "the in-memory store passes the conformance suite" =
  print_s [%sexp (Conformance.check (Memory.create ()) : unit Or_error.t)];
  [%expect {| (Ok ()) |}]
;;

(* A store that forgets the version check must fail the suite: the suite is only useful
   if it catches the bug it exists for. *)
module Lossy = struct
  include Memory

  (* Last writer wins: whatever version is stored gets overwritten. *)
  let update_approval t (a : Approval.t) ~expected_version:_ note =
    match approval t a.id with
    | None -> `Conflict
    | Some stored -> update_approval t a ~expected_version:stored.version note
  ;;
end

module Lossy_conformance = Store_conformance.Make (Monad.Ident) (Lossy)

let%expect_test "a store without compare-and-set fails" =
  let r = Lossy_conformance.check (Lossy.create ()) in
  print_s [%sexp (Result.is_error r : bool)];
  [%expect {| true |}]
;;
