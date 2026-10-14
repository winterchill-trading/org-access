# test/

Inline expect tests and Quickcheck properties (library `org_access_test`), plus
`cli.t`, a cram test of the `org-access` command.

- Run: `dune build --root .. @org-access/runtest`; promote one file at a time with
  `dune promote --root .. org-access/test/<file>`.
- `fixtures.ml` holds the shared clock start, organisation, members and deterministic
  tokens; tests never read the wall clock or `/dev/urandom` except the token test that
  checks two random tokens differ.
- `test_stable.ml` pins bin_prot digests. `test_store.ml` runs `Store_conformance`
  against the memory store and checks that a store without compare-and-set fails it.
- Before trusting a new property, break the rule it guards and watch it fail.
