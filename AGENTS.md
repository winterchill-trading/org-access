# AGENTS.md

Guide for AI coding agents working in this repository. Read this first. The
workspace-wide guide is `../oxcaml-claude-skills/AGENTS.md`.

## Purpose

`org-access` is an OCaml library for access control inside business customers:
organisations, members and roles, invitations, maker-checker approvals and an
append-only access audit. Authorization is a pure function returning a decision with a
stable reason code; persistence is a `Store` module type with an in-memory implementation.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The library, wrapped as `Org_access` |
| `examples/` | `quick_start.ml`, run by `dune test` and diffed against `quick_start.expected` |
| `.github/` | CI workflow |
| `dune-project` | Package metadata; `dune build` regenerates the `.opam` files |

## Build, test, docs

Inside the workspace (sibling checkouts and the shared `5.2.0+ox` switch):

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @org-access/all
opam exec --switch 5.2.0+ox -- dune build --root .. @org-access/runtest
```

Parallel work: prefix with `DUNE_BUILD_DIR=_build-org-access`.

## Never do

- Install or upgrade opam packages that change the compiler, `core`, `base`, `async` or
  `ppx_jane` on the shared switch.
- Publish, tag or release. Commit credentials. Poll CI in a loop.
