# AGENTS.md

Guide for AI coding agents working in this repository. Read this first; the
subdirectory `AGENTS.md` files add detail for `lib/`, `test/`, `examples/`, `bin/` and
`.github/`. The workspace-wide guide is `../oxcaml-claude-skills/AGENTS.md`.

## Purpose

`org-access` is an OCaml library for access control inside business customers of a
bank: organisations, members and roles, invitations, maker-checker approvals with
per-currency thresholds, and a hash-chained access audit. Decisions are pure functions
with stable reason codes; persistence is a `Store.S` module type with an in-memory
implementation and a conformance suite.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The library, wrapped as `Org_access` (module list in `lib/org_access.ml`) |
| `bin/` | The `org-access` command (package `org-access-cli`): `roles`, `explain`, `required` |
| `test/` | Expect tests, Quickcheck properties, pinned digests, `test/cli.t` cram test |
| `examples/` | `quick_start.ml`, run by `dune test` and diffed against `quick_start.expected` |
| `.github/` | CI workflow |
| `dune-project` | Package metadata; `dune build` regenerates both `.opam` files |
| `README.md`, `CHANGES.md`, `LICENSE` | User docs, changelog, MIT licence |

## Build, test, docs

Inside the workspace (sibling checkouts and the shared `5.2.0+ox` switch), from this
directory:

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @org-access/all
opam exec --switch 5.2.0+ox -- dune build --root .. @org-access/runtest
opam exec --switch 5.2.0+ox -- dune build --root .. @org-access/doc
```

Parallel work: prefix with `DUNE_BUILD_DIR=_build-org-access` (resolved from the
workspace root because of `--root ..`; `../_build-org-access` fails with "path outside
the workspace").

Standalone, once the org packages are published:

```sh
opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git
opam install --deps-only --with-test .
dune build && dune test
```

## Conventions

- Every module has an `.mli` and every public value an odoc comment. `open! Core`,
  labelled arguments, ppx_jane derivations.
- Decisions and state machines are pure: no clock, store or randomness inside
  `Authorize`, `Team`, `Invitation`, `Approval`. Time comes in as `~at`, tokens through
  `Access.Config.new_token`.
- Reason and error codes are public contract: add a constructor, never rename a code.
- Stored types have `Stable.V1` modules; `test/test_stable.ml` pins their bin_prot
  digests. A changed digest means old records no longer decode: add a V2. Times in
  records are `Time_utc.t` so sexps print in UTC on every machine.
- Writes are compare-and-set on a `version`; a new store must pass
  `Store_conformance`.
- Tests: expect tests per module and Quickcheck properties for the invariants
  (approvals, custodian, thresholds, audit chain). Promote one file at a time with
  `dune promote --root .. <file>`.
- Formatting: `opam exec --switch 5.2.0+ox -- dune build --root .. @org-access/fmt --auto-promote`,
  after tests pass and promotion is done. Never `dune fmt` at the workspace root.
- Comments for humans at non-obvious choices. `CHANGES.md`: a line under
  `## Unreleased` for every user-visible change.

## Dependencies and dependents

- Depends on `money` (and through it `fixed-decimal`), pinned in CI in that order.
  External: `core`, `ppx_jane`, `cryptokit` (SHA-256, `/dev/urandom`); `core_unix` for
  the command only.
- No org repository depends on it yet.

## CI

`.github/workflows/ci.yml` runs the infra `ox-setup` action (cached switch, pins
`fixed-decimal` then `money`), `dune build`, `dune test`, `dune build @examples/runtest`,
an odoc build where any warning fails, and the shared `obj-magic` workflow. Check a run
with `gh run list --limit 1`, then at most one `gh run watch <id> --exit-status`. Never
poll in a loop.

## Pitfalls

- A functor argument or result named like a library module shadows it:
  `module Access = Access.Make (...)` hides `Access.Config`; name instances `Ops` or
  similar, and alias `Store.Note` before `Store_conformance.Make (M) (Store)`.
- A local module named `Error` (in `Approval`, `Team`, `Invitation`, `Access`) shadows
  Core's; write `Core.Error.to_string_hum`.
- `Time_ns.t` sexps print in the machine's zone; use `Time_utc.t` in records.
- A Quickcheck property is only trusted after a mutation check: disable the rule
  (`false && ...`) and see the property fail.
- `Binable.Of_binable_without_uuid` needs `[@alert "-legacy"]`; it is how decoding
  re-runs validation (ids, role models, policies).
- Cryptokit's `Random.system_rng` raises on Unix; `Token.random` reads `/dev/urandom`.

## Where to read more

- `README.md`: concepts, default role model, codes, known gaps.
- `../specs/repos/org-access.md` once the specs page exists.
- `../oxcaml-claude-skills/skills/banking-standards/` and `janestreet-ocaml-style/`.
- `../oxcaml-claude-skills/GOTCHAS.md`, section "Product libraries".
- `../oxcaml-claude-skills/AGENTS.md` for the workspace model.

## Never do

- Install or upgrade opam packages that change the compiler, `core`, `base`, `async` or
  `ppx_jane` on the shared switch. Run `opam install --switch 5.2.0+ox --dry-run <pkg>`
  first and stop if the plan touches any of them.
- Publish, tag or release.
- Commit credentials or print secrets; never log a `Token.t` (its sexp is `<secret>`
  on purpose).
- Poll CI in loops.
