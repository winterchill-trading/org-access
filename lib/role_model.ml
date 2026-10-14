open! Core

module Grants = struct
  type t =
    | All
    | Only of Permission.Stable.V1.t list
  [@@deriving bin_io, sexp, compare, equal]

  let normalise = function
    | All -> All
    | Only l -> Only (List.dedup_and_sort l ~compare:Permission.compare)
  ;;
end

module Repr = struct
  type t =
    { roles : (Role.Stable.V1.t * Grants.t) list
    ; permissions : Permission.Stable.V1.t list
    ; custodian : Permission.Stable.V1.t
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Repr.t =
  { roles : (Role.t * Grants.t) list
  ; permissions : Permission.t list
  ; custodian : Permission.t
  }
[@@deriving compare, equal]

let sexp_of_t = Repr.sexp_of_t

let grants_allow (grants : Grants.t) permission =
  match grants with
  | All -> true
  | Only l -> List.mem l permission ~equal:Permission.equal
;;

let create ~permissions ~custodian roles =
  let permissions = List.dedup_and_sort permissions ~compare:Permission.compare in
  let roles = List.map roles ~f:(fun (role, grants) -> role, Grants.normalise grants) in
  let declared p = List.mem permissions p ~equal:Permission.equal in
  let undeclared =
    List.concat_map roles ~f:(fun (role, grants) ->
      match grants with
      | All -> []
      | Only l -> List.filter l ~f:(Fn.non declared) |> List.map ~f:(fun p -> role, p))
  in
  if List.is_empty roles
  then Or_error.error_string "role model has no roles"
  else (
    match List.find_a_dup (List.map roles ~f:fst) ~compare:Role.compare with
    | Some role -> Or_error.error_s [%message "role listed twice" (role : Role.t)]
    | None ->
      if not (List.is_empty undeclared)
      then
        Or_error.error_s
          [%message
            "role grants an undeclared permission"
              (undeclared : (Role.t * Permission.t) list)]
      else if not (declared custodian)
      then
        Or_error.error_s
          [%message "custodian permission is not declared" (custodian : Permission.t)]
      else if not (List.exists roles ~f:(fun (_, g) -> grants_allow g custodian))
      then
        Or_error.error_s
          [%message "no role holds the custodian permission" (custodian : Permission.t)]
      else Ok { roles; permissions; custodian })
;;

let create_exn ~permissions ~custodian roles =
  Or_error.ok_exn (create ~permissions ~custodian roles)
;;

let roles t = List.map t.roles ~f:fst
let permissions t = t.permissions
let custodian t = t.custodian
let grants t role = List.Assoc.find t.roles role ~equal:Role.equal
let mem t role = Option.is_some (grants t role)

let rank t role =
  List.find_mapi t.roles ~f:(fun i (r, _) -> Option.some_if (Role.equal r role) i)
;;

let allows t role permission =
  match grants t role with
  | None -> false
  | Some g -> grants_allow g permission
;;

let permissions_of t role =
  match grants t role with
  | None -> []
  | Some All -> t.permissions
  | Some (Only l) -> l
;;

let lowest_role_with t permission =
  List.rev t.roles
  |> List.find_map ~f:(fun (role, g) -> Option.some_if (grants_allow g permission) role)
;;

module Default = struct
  let role = Role.of_string
  let permission = Permission.of_string
  let admin = role "admin"
  let approver = role "approver"
  let operator = role "operator"
  let viewer = role "viewer"
  let manage_members = permission "members.manage"
  let manage_policy = permission "policy.manage"
  let manage_verification = permission "verification.manage"
  let create_payments = permission "payments.create"
  let approve_payments = permission "payments.approve"
  let manage_payees = permission "payees.manage"
  let manage_schedules = permission "schedules.manage"
  let manage_rules = permission "rules.manage"
  let manage_cards = permission "cards.manage"
  let manage_cost_centres = permission "cost_centres.manage"
  let manage_addresses = permission "addresses.manage"
  let manage_accounting = permission "accounting.manage"
  let export = permission "export"
end

let default =
  let open Default in
  let operator_permissions =
    [ create_payments
    ; manage_payees
    ; manage_schedules
    ; manage_rules
    ; manage_cards
    ; manage_cost_centres
    ; manage_addresses
    ; manage_accounting
    ; export
    ]
  in
  create_exn
    ~permissions:
      (manage_members
       :: manage_policy
       :: manage_verification
       :: approve_payments
       :: operator_permissions)
    ~custodian:manage_members
    [ admin, All
    ; approver, Only [ approve_payments; export ]
    ; operator, Only operator_permissions
    ; viewer, Only [ export ]
    ]
;;

module Stable = struct
  module V1 = struct
    let of_repr (r : Repr.t) =
      create_exn ~permissions:r.permissions ~custodian:r.custodian r.roles
    ;;

    module T = struct
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

    include T
  end
end
