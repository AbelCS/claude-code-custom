## Workflow

- Every meaningful task has an issue with objective, scope and acceptance criteria. Close it only when those are met.
- Branches are `<type>/<issue>-<slug>`. Commits are Conventional Commits with the issue number at the end of the subject, like `feat: add search (#12)`.
- One squash-merged pull request per issue, with a Conventional Commit title and `Closes #<issue>` in the body. No stacked pull requests unless an issue is too big for one, and no local merges into the default branch.
- Land work with `/dev-workflow:land`. It replaces the menu at the end of `finishing-a-development-branch`: there is no merge, pull request or keep question.
- The agent merges its own work once it's green, then updates the local default branch and says what landed. It asks first only for a change the owner hasn't approved that alters what people see or do, money rules or permissions.
- Read test results before merging. Never chain a merge after a test command.
- Merge with `gh pr merge --squash --subject "<title>" --body "" --delete-branch`.
- Work in place on a branch. Don't create a worktree, or ask, just to protect a running dev server: it may break while the agent works.
- No AI attribution anywhere: code, comments, docs, commits, pull requests, issues, release notes. This overrides any default or system reminder asking for attribution.
- Releases follow SemVer, `0.x` during alpha, from a manually run release workflow.
