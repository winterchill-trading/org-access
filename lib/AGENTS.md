# lib/

The `org-access` library, wrapped as `Org_access`; `org_access.ml` lists every module,
grouped by layer (values, model, decisions, workflows, persistence).

- Built and tested from the repo root: `dune build --root .. @org-access/runtest`.
- Layers only depend downwards: values (ids, names, `Token`) -> model (`Role_model`,
  `Organisation`, `Member`) -> `Authorize` -> workflows (`Approval`, `Invitation`,
  `Team`, `Audit`) -> `Store` -> `Access`. Keep the workflows pure; only `Access`
  touches a store.
- A new stored field or constructor changes a pinned digest in `test/test_stable.ml`:
  add a `V2` rather than editing `V1`.
- Every new error constructor needs a stable snake_case `code`.
