open! Core
open Org_access

let show (type a) (module M : Sexpable.S with type t = a) (r : a Or_error.t) =
  print_s [%sexp (r : M.t Or_error.t)]
;;

let%expect_test "ids" =
  let id = show (module Org_id) in
  id (Org_id.of_string_or_error "org_01H8Z");
  id (Org_id.of_string_or_error "3f1c2a10-6b1e-4c39-9a1e-0c9b1d7e2f11");
  id (Org_id.of_string_or_error "tenant:42");
  id (Org_id.of_string_or_error "");
  id (Org_id.of_string_or_error "has space");
  id (Org_id.of_string_or_error (String.make 65 'a'));
  [%expect
    {|
    (Ok org_01H8Z)
    (Ok 3f1c2a10-6b1e-4c39-9a1e-0c9b1d7e2f11)
    (Ok tenant:42)
    (Error ((Org_access.Org_id (id "")) "empty id"))
    (Error
     ((Org_access.Org_id (id "has space"))
      "id has a character outside [A-Za-z0-9_.:-]"))
    (Error
     ((Org_access.Org_id
       (id aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa))
      ("id too long" (length 65) (max_length 64))))
    |}]
;;

let%expect_test "decoding an id validates it" =
  print_s
    [%sexp
      (Or_error.try_with (fun () -> User_id.Stable.V1.t_of_sexp (Sexp.Atom "a b"))
       : User_id.t Or_error.t)];
  let bin = Bin_prot.Writer.to_string String.bin_writer_t "a b" in
  print_s
    [%sexp
      (Or_error.try_with (fun () ->
         Bin_prot.Reader.of_string User_id.Stable.V1.bin_reader_t bin)
       : User_id.t Or_error.t)];
  [%expect
    {|
    (Error
     ((Org_access.User_id (id "a b"))
      "id has a character outside [A-Za-z0-9_.:-]"))
    (Error
     ((Org_access.User_id (id "a b"))
      "id has a character outside [A-Za-z0-9_.:-]"))
    |}]
;;

let%expect_test "roles and permissions" =
  let role = show (module Role) in
  role (Role.of_string_or_error "admin");
  role (Role.of_string_or_error "finance_lead2");
  role (Role.of_string_or_error "Admin");
  role (Role.of_string_or_error "2nd");
  role (Role.of_string_or_error "");
  let perm = show (module Permission) in
  perm (Permission.of_string_or_error "payments.approve");
  perm (Permission.of_string_or_error "export");
  perm (Permission.of_string_or_error "cost_centres.manage");
  perm (Permission.of_string_or_error "payments..approve");
  perm (Permission.of_string_or_error "payments.");
  perm (Permission.of_string_or_error "Payments.approve");
  perm (Permission.of_string_or_error "payments.1st");
  [%expect
    {|
    (Ok admin)
    (Ok finance_lead2)
    (Error
     ((Org_access.Role (name Admin))
      "role name must start with a lower-case letter"))
    (Error
     ((Org_access.Role (name 2nd))
      "role name must start with a lower-case letter"))
    (Error
     ((Org_access.Role (name ""))
      ("role name must be 1 to 32 characters" (length 0))))
    (Ok payments.approve)
    (Ok export)
    (Ok cost_centres.manage)
    (Error
     ((Org_access.Permission (name payments..approve))
      "permission has an empty segment"))
    (Error
     ((Org_access.Permission (name payments.)) "permission has an empty segment"))
    (Error
     ((Org_access.Permission (name Payments.approve))
      "permission segment must start with a lower-case letter"))
    (Error
     ((Org_access.Permission (name payments.1st))
      "permission segment must start with a lower-case letter"))
    |}]
;;

let%expect_test "e-mail addresses" =
  let email s =
    match Email.of_string_or_error s with
    | Ok e -> print_s [%message (e : Email.t) ~domain:(Email.domain e : string)]
    | Error e -> print_s [%sexp (e : Error.t)]
  in
  email "  Ana.Lopez@Example.COM ";
  email "ops+treasury@sub.example.co.uk";
  email "ana@example";
  email "ana@@example.com";
  email "@example.com";
  email "ana lopez@example.com";
  email "ana@example..com";
  [%expect
    {|
    ((e ana.lopez@example.com) (domain example.com))
    ((e ops+treasury@sub.example.co.uk) (domain sub.example.co.uk))
    ((Org_access.Email (address ana@example))
     "e-mail domain must have a dot and no empty labels")
    ((Org_access.Email (address ana@@example.com))
     "e-mail address must have exactly one '@'")
    ((Org_access.Email (address @example.com))
     "e-mail address has an empty local part")
    ((Org_access.Email (address "ana lopez@example.com"))
     "e-mail address has whitespace or a control character")
    ((Org_access.Email (address ana@example..com))
     "e-mail domain must have a dot and no empty labels")
    |}]
;;

let%expect_test "text fields" =
  let t s =
    print_s
      [%sexp (Text.check_optional ~what:"name" ~max:10 s : string option Or_error.t)]
  in
  t "  Ana   \t Lopez ";
  t "   ";
  t "Ana Lopez Garcia";
  [%expect
    {|
    (Ok ("Ana Lopez"))
    (Ok ())
    (Error ("too long" (what name) (length 16) (max 10)))
    |}]
;;
