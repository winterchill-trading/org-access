# org-access

Access control for business customers of a bank, in OxCaml: organisations, members and
roles, invitations, maker-checker approvals and an append-only access audit.

- **Roles map to permission sets.** A role model lists roles from most to least
  privileged; each holds every permission or a named set. One permission (managing the
  team) is the *custodian* permission, and the library never lets the last member
  holding it be demoted or removed.
- **Every resource belongs to one organisation.** A member of another organisation gets
  the same answer as for something that does not exist.
- **Authorization is a pure function.** `Authorize.decide` takes the role model, the
  organisation, the caller's membership and the action, and returns `Allowed` or
  `Denied` with a stable reason code (`role_required`, `verification_required`, ...).
- **Maker-checker thresholds are money amounts.** `Approval_policy` says how many
  distinct approvers an amount needs, per currency (for example two above
  10,000.00 EUR). The maker never approves their own request, and two approvals from
  the same person count once.
- **Invitations expire and their tokens are single-use.** Only the SHA-256 of the link
  token is stored; resending rotates it.
- **The audit is append-only and hash-chained.** Every change and every refusal is an
  entry; `Audit.verify` detects a deleted, edited or reordered entry.
- **Persistence is a module type.** `Store.S` has an in-memory implementation and a
  conformance suite; a service implements it over its own database.

## Why separate

Every business-banking service needs the same answers: who belongs to this company, what
may they do, how many people must sign off a payment of this size, and who changed any of
it. Getting these wrong is how money leaves without a second pair of eyes, or how a
company locks out its only administrator. Keeping them in one small library, with pure
decisions and property tests on the invariants, lets each service use the same rules
instead of re-implementing them in its handlers. The library depends only on `money` for
amounts.

## Quick start

```ocaml
open Org_access
module D = Role_model.Default
module Store = Store_memory.Make (Monad.Ident)
module Ops = Access.Make (Monad.Ident) (Store)

let config = Access.Config.default
let store = Store.create ()

let _team =
  Ops.create_organisation config store ~id:org ~name:"Acme Trading Ltd"
    ~creator:ana ~email:ana_email ~at:now ()

(* Invite an approver: the token goes into the e-mail link, only its hash is stored. *)
let invitation, token =
  Ops.invite config store ~actor:ana ~org ~id:inv_id ~email:bea_email
    ~role:D.approver ~at:now () |> Result.ok_or_failwith

let _member = Ops.accept_link config store ~token ~user:bea ~email:bea_email ~at:now

(* Payments above 10,000.00 EUR need two approvers who are not the maker. *)
let policy = Approval_policy.four_eyes ~above:[ Money.Amount.of_string "10000.00 EUR" ]

let _approval =
  Ops.open_approval config store ~maker:olu ~org ~id:apr_id ~policy
    ~subject:"supplier invoice 2027-031"
    ~action:(Action.requires_verified D.approve_payments)
    ~amounts:[ Money.Amount.of_string "12500.00 EUR" ] ~at:now ()
```

`examples/quick_start.ml` is the complete program; `dune test` runs it and compares its
output with `examples/quick_start.expected`.

## Modules

| Module | Holds |
| --- | --- |
| `Org_id`, `User_id`, `Invitation_id`, `Approval_id` | Validated ids, one type each |
| `Role`, `Permission`, `Email`, `Text`, `Time_utc` | Validated names and fields |
| `Role_model` | Roles in privilege order, their permissions, the custodian permission; `Role_model.default` |
| `Organisation`, `Member` | The organisation (status, verification) and a user's membership |
| `Action`, `Reason`, `Authorize` | What a request needs, why it was refused, the pure decision |
| `Approval_policy` | Per-currency maker-checker thresholds |
| `Approval` | The approval state machine: open, approve, reject, cancel |
| `Invitation`, `Token` | Invitations with expiry, resend and single-use acceptance; secret tokens |
| `Team` | Pure member operations that keep a custodian |
| `Audit` | Events, hash-chained entries, `verify` |
| `Store`, `Store_memory`, `Store_conformance` | Persistence signature, in-memory store, conformance suite |
| `Access` | The operations a service exposes, over any store and monad |

## The default role model

| Permission | admin | approver | operator | viewer |
| --- | --- | --- | --- | --- |
| `members.manage` (custodian), `policy.manage`, `verification.manage` | yes | | | |
| `payments.approve` | yes | yes | | |
| `payments.create`, `payees.manage`, `schedules.manage`, `rules.manage`, `cards.manage`, `cost_centres.manage`, `addresses.manage`, `accounting.manage` | yes | | yes | |
| `export` | yes | yes | yes | yes |

Every member may read. A service can define its own model with `Role_model.create`; the
model is data (it has a stable sexp and bin_prot form), so it can live in configuration.

## Decisions

`Authorize.decide` checks, in this order: the caller has a membership (`not_a_member`);
it is in the resource's organisation (`other_organisation`); the organisation is not
suspended (`organisation_suspended`); the role is in the model (`unknown_role`); the role
holds the action's permission (`role_required`, with the least privileged role that
does); the organisation is verified if the action needs it (`verification_required`).
Outsiders are checked first so they learn nothing about the organisation.

Workflow errors have codes too: `own_request`, `already_approved`, `not_pending`,
`not_enough_approvers`, `not_canceller` (approvals); `member_exists`, `member_elsewhere`,
`own_membership`, `last_admin` (team); `invitation_pending`, `too_many_invitations`,
`invitation_not_pending`, `invitation_expired`, `invalid_token`, `email_mismatch`
(invitations).

## Concurrency

Team, invitation and approval writes are compare-and-set on a version. Two approvers
clicking at the same moment cannot both be counted as the last approval, and two
administrators cannot demote each other into an organisation with none. `Access`
reloads and retries a lost write (three attempts by default) and then answers
`conflict`. Accepting an invitation writes the membership before marking the invitation
accepted, so an interrupted acceptance is finished by the next attempt.

## Command

The `org-access` command (package `org-access-cli`) prints a role model's permission
matrix, explains a decision and computes the approvals a set of amounts needs:

```sh
org-access roles
org-access explain -role approver -permission payments.approve -needs-verification -verified
org-access required -policy policy.sexp "9000.00 EUR" "6000.00 EUR"
```

## Build

Inside the workspace (sibling checkouts and the shared `5.2.0+ox` switch):

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @org-access/all @org-access/runtest
```

Standalone, once the org packages are published to the `winterchill` opam repository:

```sh
opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git
opam install --deps-only --with-test .
dune build && dune test
```

## Known gaps

- Access for people outside the organisation (a supplier submitting invoices through a
  link) is not modelled; `Token` is the building block for it.
- Verification is one flag on the organisation. The verification file itself (legal
  entity, owners, documents) belongs in a KYC/KYB library.
- Scoping stops at the organisation. Finer rules (only the cardholder may reveal a card)
  are the service's checks after `Authorize.decide`.
- The audit chain is tamper-evident, not signed: someone able to rewrite the whole table
  can rebuild it. Export the latest digest elsewhere.
- No database store ships here; libraries never persist. A service implements
  `Store.S` and runs `Store_conformance` against it.

## Docs

- API docs: `dune build @doc`.
- `CHANGES.md`, `AGENTS.md`.

## License

MIT
