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
- Versions follow SemVer, `0.x` during alpha. Every version is a git tag holding the bare version, like `1.4.0`, never `v1.4.0`.
- Without release-please, every merge that needs it raises the version: `land` works it out from the pull request title's type, `feat` the minor, `fix` and `perf` the patch, a `!` the major, one step lower before 1.0.0, commits it before the merge and tags it after. With release-please, it raises and tags the version when a release is cut.
- GitHub Releases are optional. A project that wants them runs `/dev-workflow:enable-releases`, whose release workflow runs only when started by hand.
