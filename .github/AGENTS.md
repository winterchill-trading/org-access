# .github/

`workflows/ci.yml`: build, test, examples, odoc (warnings fail) and the shared
`obj-magic` workflow, on the infra `ox-setup` action.

- The `pins:` list must follow the dependency order in `dune-project`
  (`fixed-decimal`, then `money`). Add a sibling there before depending on it.
- Check a run once with `gh run list --limit 1` and at most one `gh run watch`.
