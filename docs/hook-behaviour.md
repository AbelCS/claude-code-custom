# How the hooks behave in real sessions

Results from Claude Code 2.1.317 on macOS, on 2026-11-05, using `claude -p --plugin-dir plugins/dev-workflow` and a cheap, fast model, each case in its own temp repo. Rerun the test after a Claude Code upgrade that touches permissions.

There are two kinds of result here:

- **The committed test,** `tests/verify_only/live-hooks.test.sh`, checks and fails on what's stated as checked. Its evidence is what happened in the repo: a marker file the command would have written, a commit or a merge. It also compares each session's permission mode with the one asked for. A row where `auto` wasn't available reads "not exercised", and isn't a pass.
- **One-off hand runs** are marked as such. Nothing rechecks them.

## `"ask"` on a database reset

The command was `npm run db:reset`, whose script only writes a marker file. No real database was involved. The committed test checks all of these, and the marker never appeared in any.

| Mode | How it was run | The command ran? |
|---|---|---|
| `-p` default | Nothing allowed | No |
| `-p` default | `--allowedTools Bash` | No |
| `dontAsk` | `--allowedTools Bash` | No |
| `auto` | Nothing allowed | No |
| `auto` | `--allowedTools Bash`, which allows nothing extra: the docs say auto mode drops broad allow rules on entry | No |
| `-p` default | An allow rule for that exact command in the project's `.claude/settings.json` | No |
| `-p` default | A project `PermissionRequest` hook that says yes to everything | No |
| `-p` default | That same hook, and `--allowedTools Bash` | No |

Each session reported the mode shown. In a hand-read log of the same kind of run, the hook's `"ask"` came back to the model as a failed tool call with the hook's reason as its text, and the result listed it as a permission denial. So with no person there, `"ask"` worked as a denial in each mode above. The same command with `--allowedTools Bash`, in a repo without a project file, did write its marker, which shows that the block came from the hook.

**`bypassPermissions`, one-off hand run.** Claude Code 2.1.317, 2026-11-05, with nothing allowed and only the Bash tool: the hook returned `"ask"` and the marker didn't appear. This case isn't in the committed test, so nothing rechecks it.

### A `PermissionRequest` hook

The hook writes a marker of its own, then says yes. As a control, the same hook ran with nothing allowed in a repo with no project file, where the command would otherwise be denied for want of a prompt. There the hook's marker appeared and the reset's marker appeared, so this hook can approve a prompt in `-p`.

In a repo with a project file, in both rows above, neither marker appeared. So under these conditions the plugin's `"ask"` held against a hook that would have approved, and the hook didn't run at all. That's what these three sessions show. The docs don't promise it, and it could change in a later version, which is one reason to rerun the test.

### Not tested

- **Auto mode in an interactive session.** It needs a person at the prompt, which this test can't provide. The docs say a `PreToolUse` hook's `"ask"` "normally sends the tool call to the permission prompt, and the classifier doesn't decide it", and that auto mode still shows prompts forced by a hook. They also say the classifier can deny a call Claude Code's own checks flag before any prompt appears, which is a denial, not a pass.
- **Anything else that answers a prompt on a person's behalf.** The docs describe two, neither tried here. A `--permission-prompt-tool` or an Agent SDK `canUseTool` callback is asked about a call a hook would prompt for. A mod that handles `tool.check` can approve such a call, without a prompt, unless managed settings or a Team or Enterprise login is in place. Each is something someone has to install or wire up on purpose.
- **Whether a deny would close the mod route.** The permissions docs say it wouldn't: without managed settings or a Team or Enterprise login, a mod's `tool.check` "can approve a call that a deny rule refuses or a `PreToolUse` hook blocked". So changing the reset rule from `"ask"` to a deny wouldn't stop a mod either.

## What's denied, and what still runs

The committed test checks these. Each had the tool allowed, so that only the hook could stop it. It checks the hook's decision and the one effect named in each cell.

| Case | With a project file | Without one |
|---|---|---|
| `npm test && git merge --no-edit feature` | Denied, and `npm test`'s marker didn't appear. Whether the branch merged only prints a warning, and doesn't fail the test | Merged |
| `git commit --no-verify --allow-empty -m "..."` | Denied, no commit | Committed |
| Write a workflow with a `pull_request` trigger | `"ask"`, file not written | File written |
| `touch` a file | Ran | Not tried |

Told that a merge must come after the tests' results, the model will often go on to run the tests and the merge as two commands. In a one-off hand run it did so in 5 of 8 tries on a prompt that didn't forbid it, and in 0 of 8 on one that did. That's what the rule asks for, since the rule is about one command, so the test's prompt tells it to stop at a block.

## A broken check blocks

The committed test checks these. With `"onFailure": "block"`, each of these stopped an ordinary `touch`, and the file wasn't written: a script that exits 3, a script that's missing, and a script that runs past its timeout. A copy of the plugin with every execute bit removed still denied `git commit --no-verify`, because `hooks.json` runs each script through `sh`.

## The session-start check

The committed test checks that its line reached the session in a set-up repo where git hooks were off, and that it printed nothing in a repo without a project file.

In a one-off hand run through `--plugin-dir` with no saved settings, a hook saw `CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS` empty, even though `plugin.json` gives the option a default. So the script's own fallback of 30 is what applies then.

## Trust in `-p`

A `-p` session shows no workspace trust dialog, as the docs say. The plugin's hooks ran in temp folders nobody had ever trusted. In a one-off hand run, an allow rule in the project's own `.claude/settings.json` was ignored, with this on stderr: `Ignoring 1 permissions.allow entry from .claude/settings.json: this workspace has not been trusted`. So project allow rules don't decide anything in these results, and rules given by `--allowedTools` do.

## Limits

- Only a Bash matcher and a `Write|Edit` matcher were exercised in real sessions. The GitHub matcher is tested against tool names read from `hooks.json`, not against a live server.
- The GitHub rules match on the tool's name, in any capitals, so a GitHub server named without "github" goes unchecked. They aren't widened to every MCP tool, because the attribution and merge rules would then falsely block writes to unrelated tools.
- These sessions loaded no user settings, so a person's own rules and other plugins played no part.
- These checks catch mistakes and aren't a security boundary. They read the command's text, so a reset inside a script of its own isn't something they can see.
