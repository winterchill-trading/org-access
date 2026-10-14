open! Core
open Org_access
open Fixtures
module D = Role_model.Default

let events : Audit.Event.t list =
  [ Organisation_created { name = "Example Trading Ltd" }
  ; Member_added { user = user "bea"; role = D.approver; invitation = None }
  ; Role_changed { user = user "bea"; from = D.approver; to_ = D.admin }
  ; Access_denied { action = Action.requires D.manage_members; code = "role_required" }
  ]
;;

let chain ?(org = org_id) events =
  List.folding_mapi events ~init:None ~f:(fun i last event ->
    let e =
      Audit.next ~last ~org ~at:(at i) ~actor:(Some (user "ana")) event |> Or_error.ok_exn
    in
    Some e, e)
;;

let%expect_test "a chain and its checks" =
  let entries = chain events in
  List.iter entries ~f:(fun (e : Audit.Entry.t) ->
    printf
      "%d %s %s.. <- %s..\n"
      e.seq
      (Audit.Event.kind e.event)
      (String.prefix (Audit.Digest.to_hex e.digest) 12)
      (String.prefix (Audit.Digest.to_hex e.prev) 12));
  let verify ?after l = print_s [%sexp (Audit.verify ?after org_id l : (unit, Audit.Broken.t) result)] in
  verify entries;
  verify ~after:(List.nth_exn entries 1) (List.drop entries 2);
  verify (List.drop entries 1);
  (* Dropping an entry in the middle, editing one, or swapping two all break the chain. *)
  verify (List.filteri entries ~f:(fun i _ -> i <> 1));
  verify
    (List.mapi entries ~f:(fun i e ->
       if i = 2
       then { e with event = Role_changed { user = user "bea"; from = D.approver; to_ = D.viewer } }
       else e));
  verify
    (List.mapi entries ~f:(fun i (e : Audit.Entry.t) ->
       if i = 3 then { e with seq = 3 } else if i = 2 then { e with seq = 4 } else e)
     |> List.sort ~compare:(fun (a : Audit.Entry.t) b -> Int.compare a.seq b.seq));
  verify (chain ~org:other_org_id events);
  print_s
    [%sexp
      (Audit.next
         ~last:(Some (List.hd_exn entries))
         ~org:other_org_id
         ~at:t0
         ~actor:None
         (Organisation_verified { verified = true })
       |> Or_error.map ~f:ignore
       : unit Or_error.t)];
  [%expect
    {|
    1 organisation_created bf0df43f2461.. <- a870023a83d8..
    2 member_added d45c07d31f0d.. <- bf0df43f2461..
    3 role_changed f9afea8d60bc.. <- d45c07d31f0d..
    4 access_denied 6f84d0ed1f2e.. <- f9afea8d60bc..
    (Ok ())
    (Ok ())
    (Error (Gap (expected 1) (found 2)))
    (Error (Gap (expected 2) (found 3)))
    (Error (Digest_mismatch (seq 3)))
    (Error (Prev_mismatch (seq 3)))
    (Error (Wrong_organisation (seq 1)))
    (Error ("audit entry of another organisation" (expected org-2) (got org-1)))
    |}]
;;

let%test_unit "any single edit of a stored entry is detected" =
  let entries = chain (events @ events) |> Array.of_list in
  let n = Array.length entries in
  Quickcheck.test
    (Quickcheck.Generator.both (Int.gen_incl 0 (n - 1)) (Int.gen_incl 0 4))
    ~sexp_of:[%sexp_of: int * int]
    ~f:(fun (i, field) ->
      let copy = Array.copy entries in
      let e = copy.(i) in
      copy.(i)
      <- (match field with
          | 0 -> { e with at = Time_ns.add e.at Time_ns.Span.nanosecond }
          | 1 -> { e with actor = None }
          | 2 -> { e with event = Organisation_verified { verified = false } }
          | 3 -> { e with seq = e.seq + 100 }
          | _ -> { e with prev = e.digest });
      assert (Result.is_error (Audit.verify org_id (Array.to_list copy))))
;;
