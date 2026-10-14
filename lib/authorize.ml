open! Core

module Decision = struct
  type t =
    | Allowed of { role : Role.t }
    | Denied of Reason.t
  [@@deriving sexp, compare, equal]

  let is_allowed = function
    | Allowed _ -> true
    | Denied _ -> false
  ;;

  let to_or_error = function
    | Allowed _ -> Ok ()
    | Denied reason ->
      Or_error.error_s [%message "access denied" ~code:(Reason.code reason) (reason : Reason.t)]
  ;;
end

let scope ~(membership : Member.t option) org : (Member.t, Reason.t) result =
  match membership with
  | None -> Error Not_a_member
  | Some m when not (Org_id.equal m.org org) -> Error Other_organisation
  | Some m -> Ok m
;;

let decide model ~(organisation : Organisation.t) ~membership (action : Action.t)
  : Decision.t
  =
  let check =
    let open Result.Let_syntax in
    let%bind (member : Member.t) = scope ~membership organisation.id in
    let%bind () =
      match organisation.status with
      | Active -> Ok ()
      | Suspended -> Error Reason.Organisation_suspended
    in
    let role = member.role in
    let%bind () =
      if Role_model.mem model role then Ok () else Error (Reason.Unknown_role role)
    in
    let%bind () =
      match action.permission with
      | None -> Ok ()
      | Some permission ->
        if Role_model.allows model role permission
        then Ok ()
        else
          Error
            (Reason.Permission_missing
               { role; permission; required = Role_model.lowest_role_with model permission })
    in
    let%map () =
      if action.needs_verification && not organisation.verified
      then Error Reason.Verification_required
      else Ok ()
    in
    role
  in
  match check with
  | Ok role -> Allowed { role }
  | Error reason -> Denied reason
;;
