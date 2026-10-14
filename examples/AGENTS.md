# examples/

`quick_start.ml`: an organisation, two invited approvers, an operator, verification
and a four-eyes payment approval over the in-memory store, ending with the audit.

- `dune test` runs it and diffs its output with `quick_start.expected`; after an
  intended change, `dune promote --root .. org-access/examples/quick_start.expected`.
- CI runs `dune build @examples/runtest`. Keep the output deterministic (fixed times,
  no tokens printed).
