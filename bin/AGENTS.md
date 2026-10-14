# bin/

The `org-access` command (package `org-access-cli`): `roles` prints a role model's
matrix, `explain` runs `Authorize.decide` for a role and action, `required` applies an
approval policy file to amounts.

- Tested by `test/cli.t/run.t`; promote with `dune promote --root .. org-access/test/cli.t/run.t`.
- Keep it a thin layer over the library: no logic that the library does not expose.
