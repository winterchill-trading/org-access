open! Core
open Org_access

let model_param =
  let open Command.Param in
  flag
    "model"
    (optional string)
    ~doc:"FILE role model as a sexp (default: the built-in four-role model)"
  |> map ~f:(function
    | None -> Role_model.default
    | Some file -> Sexp.load_sexp_conv_exn file Role_model.Stable.V1.t_of_sexp)
;;

let roles =
  Command.basic
    ~summary:"print each role's permissions, most privileged first"
    (let%map_open.Command model = model_param in
     fun () ->
       let permissions = Role_model.permissions model in
       let width =
         List.fold permissions ~init:10 ~f:(fun w p ->
           Int.max w (String.length (Permission.to_string p)))
       in
       let line first cells =
         String.rstrip
           (sprintf "%-*s" width first
            ^ String.concat (List.map cells ~f:(fun c -> sprintf " %-9s" c)))
         |> print_endline
       in
       let roles = Role_model.roles model in
       line "" (List.map roles ~f:Role.to_string);
       List.iter permissions ~f:(fun p ->
         line
           (Permission.to_string p)
           (List.map roles ~f:(fun r ->
              if Role_model.allows model r p then "yes" else "-")));
       printf "custodian: %s\n" (Permission.to_string (Role_model.custodian model)))
;;

let explain =
  Command.basic
    ~summary:"decide whether a member with a role may take an action"
    (let%map_open.Command model = model_param
     and role = flag "role" (required string) ~doc:"ROLE the member's role"
     and permission =
       flag "permission" (optional string) ~doc:"PERMISSION what the action needs"
     and needs_verification =
       flag "needs-verification" no_arg ~doc:" the action needs a verified organisation"
     and verified = flag "verified" no_arg ~doc:" the organisation is verified"
     and suspended = flag "suspended" no_arg ~doc:" the organisation is suspended" in
     fun () ->
       let at = Time_ns.epoch in
       let org = Org_id.of_string "org" in
       let organisation =
         Organisation.create
           ~id:org
           ~name:"Example"
           ~created_by:(User_id.of_string "u")
           ~at
         |> Or_error.ok_exn
         |> Fn.flip Organisation.set_verified verified
         |> Fn.flip Organisation.set_status (if suspended then Suspended else Active)
       in
       let member =
         Member.create
           ~org
           ~user:(User_id.of_string "u")
           ~email:(Email.of_string "u@example.com")
           ~role:(Role.of_string role)
           ~added_at:at
           ~added_by:None
           ()
         |> Or_error.ok_exn
       in
       let action =
         { Action.permission = Option.map permission ~f:Permission.of_string
         ; needs_verification
         }
       in
       let decision =
         Authorize.decide model ~organisation ~membership:(Some member) action
       in
       print_s [%sexp (decision : Authorize.Decision.t)];
       match decision with
       | Allowed _ -> ()
       | Denied reason -> printf "code: %s\n" (Reason.code reason))
;;

let required =
  Command.basic
    ~summary:"how many approvals a request moving these amounts needs"
    (let%map_open.Command policy =
       flag "policy" (required string) ~doc:"FILE approval policy as a sexp"
     and amounts = anon (non_empty_sequence_as_list ("AMOUNT" %: string)) in
     fun () ->
       let policy = Sexp.load_sexp_conv_exn policy Approval_policy.Stable.V1.t_of_sexp in
       let amounts = List.map amounts ~f:Money.Amount.of_string in
       List.iter amounts ~f:(fun a ->
         printf "%s: %d\n" (Money.Amount.to_string a) (Approval_policy.required policy a));
       printf "together: %d\n" (Approval_policy.required_for policy amounts))
;;

let () =
  Command_unix.run
    (Command.group
       ~summary:"inspect org-access role models and approval policies"
       [ "roles", roles; "explain", explain; "required", required ])
;;
