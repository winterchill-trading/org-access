open! Core
open Org_access

let t0 = Time_ns.of_string_with_utc_offset "2027-03-01 09:00:00Z"
let at minutes = Time_ns.add t0 (Time_ns.Span.of_int_min minutes)
let org_id = Org_id.of_string "org-1"
let other_org_id = Org_id.of_string "org-2"
let user = User_id.of_string
let email name = Email.of_string (name ^ "@example.com")

let organisation ?(verified = true) ?(status = Organisation.Status.Active) () =
  let o =
    Organisation.create ~id:org_id ~name:"Example Trading Ltd" ~created_by:(user "ana") ~at:t0
    |> Or_error.ok_exn
  in
  Organisation.set_status (Organisation.set_verified o verified) status
;;

let member ?(org = org_id) name role =
  Member.create
    ~org
    ~user:(user name)
    ~email:(email name)
    ~role
    ~added_at:t0
    ~added_by:None
    ()
  |> Or_error.ok_exn
;;

let token seed =
  Token.generate (fun n -> String.init n ~f:(fun j -> Char.of_int_exn ((seed + (7 * j)) land 0xff)))
;;
