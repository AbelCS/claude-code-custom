## Testing

- Test first: every feature, bug fix, refactor and behaviour change, including screens through end-to-end tests of their flows. Most care goes to domain rules, permissions and money.
- Tests run locally through git hooks: `pre-commit` checks the formatting of staged files, `commit-msg` checks the message, and `pre-push` runs `check`. Never skip them with `--no-verify`.
- CI runs only for releases. Never add per-PR pipelines.
- `check` covers format, lint, typecheck and unit tests. `verify` adds database and end-to-end tests. Cache lint and format so they stay fast.
- End-to-end tests have their own isolated stack, reset before each run, so they never touch the data the owner uses. Test suites sharing a stack don't run at the same time.
- Schema changes only through migrations. Never reset the owner's local database without asking.
- A flaky test is a bug until proven otherwise: find the root cause before rerunning or retrying. Only rerun for a proven environmental cause, such as the laptop sleeping, and say so.
- A rule computed in two places gets a parity test running both on the same data.
