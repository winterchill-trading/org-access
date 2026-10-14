(lang dune 3.17)

(name org-access)

(generate_opam_files true)

(license MIT)

(authors "WinterChill AI")

(maintainers "hello@winterchill.xyz")

(source
 (github winterchill-trading/org-access))

(homepage "https://github.com/winterchill-trading/org-access")

(bug_reports "https://github.com/winterchill-trading/org-access/issues")

(documentation "https://github.com/winterchill-trading/org-access#readme")

(package
 (name org-access)
 (synopsis
  "Organisations, members, roles, invitations and maker-checker approvals for business banking")
 (description
  "org-access models who may do what inside a business customer: organisations, members with roles mapped to permission sets, every resource scoped to one organisation, invitations with an expiry and a single-use token stored only as a hash, maker-checker approvals where amounts above per-currency thresholds need several distinct approvers and nobody approves their own request, and an append-only, hash-chained audit of every access change and refusal. Authorization is a pure function that returns a decision with a stable reason code. Persistence is a module type with an in-memory implementation and a conformance suite. Requires the OxCaml compiler.")
 (tags
  (authorization rbac maker-checker banking organisations oxcaml))
 (depends
  oxcaml
  (ocaml
   (and
    (>= 5.2.0)
    (< 5.3~)))
  dune
  (core
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (ppx_jane
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (cryptokit
   (>= 1.16))
  money
  (base_quickcheck :with-test)
  (odoc :with-doc)))


(package
 (name org-access-cli)
 (synopsis "Command-line view of org-access role models and approval policies")
 (description
  "The org-access command prints a role model's permission matrix, explains an authorization decision and computes how many approvals a set of amounts needs under a policy.")
 (depends
  oxcaml
  (ocaml
   (and
    (>= 5.2.0)
    (< 5.3~)))
  dune
  (core
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (core_unix
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (org-access
   (= :version))))
