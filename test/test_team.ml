open! Core
open Org_access
open Fixtures
module D = Role_model.Default

let model = Role_model.default

let founded =
  let t, _ =
    Team.found model (organisation ()) ~email:(email "ana") ~display_name:"Ana" ~at:t0 ()
    |> Result.ok
    |> Option.value_exn
  in
  t
;;

let show r =
  match r with
  | Ok ((t : Team.t), changes) ->
    print_s
      [%message
        ""
          ~version:(t.version : int)
          ~members:
            (List.map t.members ~f:(fun m -> m.user, m.role) : (User_id.t * Role.t) list)
          ~changes:(List.length changes : int)]
  | Error e -> print_s [%message (e : Team.Error.t) ~code:(Team.Error.code e)]
;;

let ok r = Result.ok r |> Option.value_exn |> fst

let add ?policy ?(other_memberships = []) t ~by name role =
  Team.add
    ?policy
    model
    t
    ~actor:(Team.find t (user by))
    ~user:(user name)
    ~email:(email name)
    ~role
    ~other_memberships
    ~at:(at 1)
    ()
;;

let%expect_test "found, add, change role, remove" =
  show (Ok (founded, []));
  let t = ok (add founded ~by:"ana" "bea" D.approver) in
  let t = ok (add t ~by:"ana" "olu" D.operator) in
  show (Ok (t, []));
  show (add t ~by:"bea" "cal" D.viewer);
  show (add t ~by:"ana" "bea" D.viewer);
  show (add t ~by:"ana" "cal" (Role.of_string "owner"));
  show
    (Team.change_role
       model
       t
       ~actor:(Team.find t (user "ana"))
       ~user:(user "ana")
       ~role:D.viewer);
  show
    (Team.change_role
       model
       t
       ~actor:(Team.find t (user "ana"))
       ~user:(user "zed")
       ~role:D.viewer);
  show
    (Team.change_role
       model
       t
       ~actor:(Team.find t (user "ana"))
       ~user:(user "bea")
       ~role:D.approver);
  let t =
    ok
      (Team.change_role
         model
         t
         ~actor:(Team.find t (user "ana"))
         ~user:(user "bea")
         ~role:D.admin)
  in
  show (Ok (t, []));
  show (Team.remove model t ~actor:(Team.find t (user "bea")) ~user:(user "zed"));
  show (Team.remove model t ~actor:(Team.find t (user "bea")) ~user:(user "ana"));
  [%expect
    {|
    ((version 0) (members ((ana admin))) (changes 0))
    ((version 2) (members ((ana admin) (bea approver) (olu operator)))
     (changes 0))
    ((e
      (Denied
       (Permission_missing (role approver) (permission members.manage)
        (required (admin)))))
     (code role_required))
    ((e Already_member) (code member_exists))
    ((e (Unknown_role owner)) (code unknown_role))
    ((e Own_membership) (code own_membership))
    ((e Not_member) (code not_member))
    ((version 2) (members ((ana admin) (bea approver) (olu operator)))
     (changes 0))
    ((version 3) (members ((ana admin) (bea admin) (olu operator))) (changes 0))
    ((version 3) (members ((ana admin) (bea admin) (olu operator))) (changes 0))
    ((version 4) (members ((bea admin) (olu operator))) (changes 1))
    |}]
;;

let%expect_test "the last administrator stays" =
  let t = ok (add founded ~by:"ana" "bea" D.admin) in
  (* Bea demotes Ana: fine, Bea is still an administrator. *)
  let t =
    ok
      (Team.change_role
         model
         t
         ~actor:(Team.find t (user "bea"))
         ~user:(user "ana")
         ~role:D.viewer)
  in
  show (Team.leave model t ~user:(user "bea"));
  show (Team.leave model t ~user:(user "ana"));
  show (Team.leave model t ~user:(user "zed"));
  [%expect
    {|
    ((e Last_custodian) (code last_admin))
    ((version 3) (members ((bea admin))) (changes 1))
    ((e Not_member) (code not_member))
    |}]
;;

let%expect_test "single membership" =
  let policy = { Team.Policy.single_membership = true } in
  let elsewhere = member ~org:other_org_id "bea" D.viewer in
  show (add ~policy ~other_memberships:[ elsewhere ] founded ~by:"ana" "bea" D.viewer);
  show (add ~other_memberships:[ elsewhere ] founded ~by:"ana" "bea" D.viewer);
  [%expect
    {|
    ((e (Member_elsewhere org-2)) (code member_elsewhere))
    ((version 1) (members ((ana admin) (bea viewer))) (changes 1))
    |}]
;;

let%expect_test "join from an accepted invitation" =
  let inv =
    Invitation.create
      model
      ~id:(Invitation_id.of_string "inv-1")
      ~org:org_id
      ~email:(email "bea")
      ~role:D.approver
      ~display_name:"Bea"
      ~invited_by:(user "ana")
      ~token:(token 1)
      ~members:founded.members
      ~invitations:[]
      ~at:t0
      ()
    |> Result.ok
    |> Option.value_exn
  in
  let join ?(user = Fixtures.user "bea") invitation =
    Team.join model founded ~invitation ~user ~other_memberships:[] ~at:(at 2)
  in
  show (join inv);
  let accepted =
    Invitation.accept
      inv
      ~proof:Verified_email
      ~user:(user "bea")
      ~email:(email "bea")
      ~at:(at 1)
    |> Result.ok
    |> Option.value_exn
  in
  show (join ~user:(user "eve") accepted);
  (match join accepted with
   | Ok (_, [ Put m ]) -> print_s [%sexp (m : Member.t)]
   | _ -> assert false);
  [%expect
    {|
    ((e Invitation_not_accepted) (code invitation_not_accepted))
    ((e Invitation_not_accepted) (code invitation_not_accepted))
    ((org org-1) (user bea) (email bea@example.com) (display_name (Bea))
     (role approver) (added_at "2027-03-01 09:02:00Z") (added_by (ana)))
    |}]
;;

(* Random administrators add, re-role and remove random users, and members leave. The
   organisation never ends up without a custodian, versions grow by one per applied change
   set, and no user appears twice. *)
let%test_unit "a custodian always remains" =
  let names = [ "ana"; "bea"; "cal"; "dan"; "eli" ] in
  let roles = Role_model.roles model in
  let gen =
    let open Quickcheck.Generator.Let_syntax in
    List.gen_with_length
      30
      (let%map op = Int.gen_incl 0 3
       and actor = Quickcheck.Generator.of_list names
       and target = Quickcheck.Generator.of_list names
       and role = Quickcheck.Generator.of_list roles in
       op, actor, target, role)
  in
  Quickcheck.test
    gen
    ~sexp_of:[%sexp_of: (int * string * string * Role.t) list]
    ~f:(fun ops ->
      let final =
        List.fold ops ~init:founded ~f:(fun t (op, actor, target, role) ->
          let actor_m = Team.find t (user actor) in
          let r =
            match op with
            | 0 -> add t ~by:actor target role
            | 1 -> Team.change_role model t ~actor:actor_m ~user:(user target) ~role
            | 2 -> Team.remove model t ~actor:actor_m ~user:(user target)
            | _ -> Team.leave model t ~user:(user target)
          in
          match r with
          | Error _ -> t
          | Ok (t', []) ->
            assert (Team.equal t t');
            t'
          | Ok (t', _ :: _) ->
            [%test_result: int] t'.version ~expect:(t.version + 1);
            t')
      in
      assert (not (List.is_empty (Team.custodians model final)));
      assert (
        not
          (List.contains_dup
             (List.map final.members ~f:(fun m -> m.user))
             ~compare:User_id.compare)))
;;
