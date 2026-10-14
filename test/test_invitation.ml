open! Core
open Org_access
open Fixtures
module D = Role_model.Default

let model = Role_model.default
let ana = member "ana" D.admin

let invite
  ?(policy = Invitation.Policy.default)
  ?(members = [ ana ])
  ?(invitations = [])
  ?(at = t0)
  ~id
  name
  role
  =
  Invitation.create
    ~policy
    model
    ~id:(Invitation_id.of_string id)
    ~org:org_id
    ~email:(email name)
    ~role
    ~invited_by:ana.user
    ~token:(token (String.length id))
    ~members
    ~invitations
    ~at
    ()
;;

let show_error e =
  print_s [%message (e : Invitation.Error.t) ~code:(Invitation.Error.code e)]
;;

let show_result r =
  match r with
  | Ok (i : Invitation.t) ->
    print_s
      [%message
        ""
          ~status:(i.status : Invitation.Status.t)
          ~version:(i.version : int)
          ~sent:(i.sent_count : int)
          ~expires_at:(i.expires_at : Time_utc.t)]
  | Error e -> show_error e
;;

let%expect_test "tokens" =
  let t = token 1 in
  print_s [%sexp (t : Token.t)];
  print_endline (Token.to_string t);
  (* The hash is SHA-256 of the 64-character text form; `shasum -a 256` over that text
     gives the same digest. *)
  print_endline (Token.Hash.to_hex (Token.hash t));
  print_s [%sexp (Token.matches t (Token.hash t) : bool)];
  print_s [%sexp (Token.matches (token 2) (Token.hash t) : bool)];
  print_s [%sexp (Token.of_string "ABC" |> Or_error.map ~f:ignore : unit Or_error.t)];
  let parsed = Token.of_string (Token.to_string t) |> Or_error.ok_exn in
  print_s [%sexp (Token.matches parsed (Token.hash t) : bool)];
  let r1 = Token.random ()
  and r2 = Token.random () in
  print_s [%sexp (String.equal (Token.to_string r1) (Token.to_string r2) : bool)];
  print_s [%sexp (String.length (Token.to_string r1) : int)];
  [%expect
    {|
    <secret>
    01080f161d242b323940474e555c636a71787f868d949ba2a9b0b7bec5ccd3da
    2ad40b4cc9e195a19d34f51833a801888f19b8acd8759e5cbde821c8819edcea
    true
    false
    (Error (Org_access.Token "expected 64 lower-case hex characters"))
    true
    false
    64
    |}]
;;

let%expect_test "lifecycle" =
  let i = invite ~id:"inv-1" "bea" D.approver |> Result.ok |> Option.value_exn in
  show_result (Ok i);
  print_s [%sexp (Invitation.shown i ~now:(at 60) : Invitation.Shown.t)];
  let fourteen_days = 14 * 24 * 60 in
  print_s [%sexp (Invitation.shown i ~now:(at fourteen_days) : Invitation.Shown.t)];
  (* Accepting needs the right token, the invited address and an unexpired link. *)
  let accept ?(email = Fixtures.email "bea") ?(at = at 60) i proof =
    Invitation.accept i ~proof ~user:(user "bea") ~email ~at
  in
  show_result (accept i (Token (token 9)));
  show_result (accept ~email:(Fixtures.email "eve") i (Token (token 5)));
  show_result (accept ~at:(at fourteen_days) i (Token (token 5)));
  let accepted = accept i (Token (token 5)) in
  show_result accepted;
  let accepted = Result.ok accepted |> Option.value_exn in
  show_result (accept accepted (Token (token 5)));
  show_result (accept accepted Verified_email);
  show_result (Invitation.revoke accepted ~at:(at 61));
  show_result (Invitation.resend accepted ~token:(token 6) ~at:(at 61));
  [%expect
    {|
    ((status Pending) (version 0) (sent 1) (expires_at "2027-03-15 09:00:00Z"))
    Pending
    Expired
    ((e Wrong_token) (code invalid_token))
    ((e Email_mismatch) (code email_mismatch))
    ((e Expired) (code invitation_expired))
    ((status Accepted) (version 1) (sent 1) (expires_at "2027-03-15 09:00:00Z"))
    ((e (Not_pending Accepted)) (code invitation_not_pending))
    ((e (Not_pending Accepted)) (code invitation_not_pending))
    ((e (Not_pending Accepted)) (code invitation_not_pending))
    ((e (Not_pending Accepted)) (code invitation_not_pending))
    |}]
;;

let%expect_test "resend rotates the token; revoke is idempotent" =
  let i = invite ~id:"inv-1" "bea" D.approver |> Result.ok |> Option.value_exn in
  let late = at (20 * 24 * 60) in
  let r =
    Invitation.resend i ~token:(token 77) ~at:late |> Result.ok |> Option.value_exn
  in
  show_result (Ok r);
  let accept proof =
    Invitation.accept r ~proof ~user:(user "bea") ~email:(email "bea") ~at:late
  in
  show_result (accept (Token (token 5)));
  show_result (accept (Token (token 77)));
  let revoked = Invitation.revoke r ~at:late |> Result.ok |> Option.value_exn in
  show_result (Ok revoked);
  show_result (Invitation.revoke revoked ~at:late);
  show_result (accept Verified_email);
  show_result
    (Invitation.accept
       revoked
       ~proof:Verified_email
       ~user:(user "bea")
       ~email:(email "bea")
       ~at:late);
  [%expect
    {|
    ((status Pending) (version 1) (sent 2) (expires_at "2027-04-04 09:00:00Z"))
    ((e Wrong_token) (code invalid_token))
    ((status Accepted) (version 2) (sent 2) (expires_at "2027-04-04 09:00:00Z"))
    ((status Revoked) (version 2) (sent 2) (expires_at "2027-04-04 09:00:00Z"))
    ((status Revoked) (version 2) (sent 2) (expires_at "2027-04-04 09:00:00Z"))
    ((status Accepted) (version 2) (sent 2) (expires_at "2027-04-04 09:00:00Z"))
    ((e (Not_pending Revoked)) (code invitation_not_pending))
    |}]
;;

let%expect_test "creation checks" =
  let first = invite ~id:"inv-1" "bea" D.approver |> Result.ok |> Option.value_exn in
  show_result (invite ~id:"inv-2" "bea" (Role.of_string "owner"));
  show_result (invite ~id:"inv-2" "ana" D.viewer);
  show_result (invite ~invitations:[ first ] ~id:"inv-2" "bea" D.viewer);
  (* Even once expired, the pending one must be resent rather than duplicated. *)
  show_result
    (invite ~invitations:[ first ] ~at:(at (15 * 24 * 60)) ~id:"inv-2" "bea" D.viewer);
  let policy = { Invitation.Policy.default with max_pending = 1 } in
  show_result (invite ~policy ~invitations:[ first ] ~id:"inv-2" "cal" D.viewer);
  (* Expired invitations do not count against the limit. *)
  show_result
    (invite
       ~policy
       ~invitations:[ first ]
       ~at:(at (15 * 24 * 60))
       ~id:"inv-2"
       "cal"
       D.viewer);
  [%expect
    {|
    ((e (Unknown_role owner)) (code unknown_role))
    ((e Already_member) (code already_member))
    ((e Already_invited) (code invitation_pending))
    ((e Already_invited) (code invitation_pending))
    ((e (Too_many_pending (max 1))) (code too_many_invitations))
    ((status Pending) (version 0) (sent 1) (expires_at "2027-03-30 09:00:00Z"))
    |}]
;;
