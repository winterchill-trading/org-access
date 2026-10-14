# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

## 0.1.0

First version prepared for opam; not yet published.

### Added

- Validated ids (`Org_id`, `User_id`, `Invitation_id`, `Approval_id`), names (`Role`,
  `Permission`), `Email` and free-text checks.
- `Role_model`: roles in privilege order with permission sets, a custodian permission
  and a default four-role model.
- `Organisation` (status, verification) and `Member`.
- `Action`, `Reason` and `Authorize.decide`: a pure decision with stable reason codes.
- `Approval_policy`: per-currency maker-checker thresholds as money amounts.
- `Approval`: open, approve (distinct members, never the maker), reject and cancel,
  versioned for compare-and-set writes.
- `Token` and `Invitation`: secret single-use tokens stored as SHA-256 hashes;
  invitations with expiry, resend, revoke and acceptance by link or verified address.
- `Team`: member operations that keep at least one custodian.
- `Audit`: hash-chained, append-only entries with `verify`.
- `Store`, `Store_memory`, `Store_conformance`: persistence signature, in-memory
  implementation and conformance suite.
- `Access`: service operations over any store and monad, with retries and auditing of
  refusals.
- `org-access` command (package `org-access-cli`).
- `Stable.V1` bin_prot and sexp forms with pinned digests.
