# The answers file

`run.sh --answers <file|->` takes one JSON object: the project file's own fields, which go into `.claude/dev-workflow.json`, plus `approvals`. Pass `-` to read it from stdin. Fields left out keep what the project file already has, and `commands` merges command by command, so a rerun only needs what changed.

```json
{
  "stack": ["node-tooling"],
  "hasScreens": true,
  "defaultBranch": "main",
  "commands": {
    "check": "npm run check",
    "verify": "npm run verify",
    "format": "npm run format",
    "formatCheckStaged": [
      { "glob": "*.ts", "command": "npx prettier --check" },
      { "glob": "*.tsx", "command": "npx prettier --check" }
    ],
    "deadCode": "npm run knip",
    "audit": "npm audit"
  },
  "testCommands": ["npm test"],
  "databaseResetCommands": ["npm run db:reset"],
  "ciAllowlist": [".github/workflows/release-check.yml"],
  "approvals": {
    "githubSettings": false,
    "mergePermission": false,
    "installPlugins": false
  }
}
```

## The project file's fields

`references/project-file.schema.json` is the authority, and `run.sh` stops with its message when an answer breaks it.

| Field | What to put |
|---|---|
| `stack` | The stack files that apply, by name, as `detect.sh` suggests in `stackHints` and the person confirms. `[]` when none applies. Each stack's database reset commands are added for you. |
| `hasScreens` | Whether people use screens in it. Turns on the screen rules and the plugins for screens. |
| `defaultBranch` | The branch pushes are kept off. `detect.sh` reads it from the remote. Without a remote it gives the current branch, so confirm it. Missing means `main`. |
| `commands.check` | Required: the fast checks `pre-push` runs. A project without one gets a visible failure, never a silent pass. |
| `commands.verify` | `check` plus the slower tests, before a release. |
| `commands.formatCheckStaged` | The formatting checks `pre-commit` runs on staged files, one rule per glob. Each must only check, never rewrite: no `--write`, `-w` or `--fix`. No brace globs: one rule each for `*.ts` and `*.tsx`. |
| `commands.format`, `deadCode`, `audit` | Optional, for the maintenance skill. |
| `testCommands` | Commands that run the project's tests. |
| `databaseResetCommands` | Commands that wipe a database, which the hooks hold for a person's yes. Only the project's own: the stack's come with it. |
| `ciAllowlist` | Workflows allowed per-PR triggers. `project-file.sh existing-ci <root>` lists the ones that have them now, to offer. |

`schemaVersion`, `pluginVersion` and `managed` are setup's to set, and answers holding them are refused.

## Approvals

Each one is something outside the project's files that needs the person's yes. Each is `false` unless set to `true`, and `run.sh` refuses any other key here.

| Key | When `true` |
|---|---|
| `mergePermission` | Adds `Bash(gh pr merge *)` to `permissions.allow` in `.claude/settings.local.json`, so auto mode doesn't block the agent merging its own pull requests. |
| `githubSettings` | Sets the GitHub repo behind `origin` to squash merges only, with the pull request's title as the subject, a blank message, and merged branches deleted. Needs admin rights on that repo. |
| `installPlugins` | Installs the missing plugins `tools.sh` lists, with `claude plugin install`, for the current user. The screen plugins are only installed when `hasScreens` is true. A session needs `/reload-plugins` afterwards. |
