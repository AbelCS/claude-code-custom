# How the hooks behave in real sessions

What `tests/verify_only/live-hooks.test.sh` saw, run on 2026-11-05 with Claude Code 2.1.317 on macOS, using `claude -p --plugin-dir plugins/dev-workflow` and a cheap, fast model. Each case ran in its own temp repo. The evidence is what happened in that repo: a marker file the command would have written, a commit or a merge. Rerun it after a Claude Code upgrade that touches permissions.

## `"ask"` on a database reset

The command was `npm run db:reset`, whose script only writes a marker file. No real database was involved. The marker never appeared in any of these.

| Mode | How it was run | The command ran? |
|---|---|---|
| `-p` default | Nothing allowed | No |
| `-p` default | The whole Bash tool allowed | No |
| `dontAsk` | The whole Bash tool allowed | No |
| `auto` | Nothing allowed | No |
| `auto` | The whole Bash tool allowed | No |
| `bypassPermissions` | Nothing allowed | No |
| `-p` default | An allow rule for that exact command in the project's `.claude/settings.json` | No |
| `-p` default | The Bash tool allowed, and a project `PermissionRequest` hook that says yes to everything | No |

In every case the hook's `"ask"` came back to the model as a failed tool call, with the hook's reason as its text, and the result listed it as a permission denial. So with no person there, `"ask"` works as a denial in each mode tried. The same command run with the Bash tool allowed, in a repo without a project file, did write its marker, which shows that the block came from the hook.

The `PermissionRequest` hook never ran. The headless docs say a prompt is denied "unless a `PermissionRequest` hook allows it", but no such hook was consulted for a prompt that a `PreToolUse` hook forced.

### Not tested

- **Auto mode in an interactive session.** It needs a person at the prompt, which this test can't provide. The docs say a `PreToolUse` hook's `"ask"` "normally sends the tool call to the permission prompt, and the classifier doesn't decide it", and that auto mode still shows prompts forced by a hook. They also say the classifier can deny a call Claude Code's own checks flag before any prompt appears, which is a denial, not a pass.
- **Anything that answers a prompt on a person's behalf.** The docs describe two, neither tried here. A `--permission-prompt-tool` or an Agent SDK `canUseTool` callback is asked about a call a hook would prompt for. A mod that handles `tool.check` can approve such a call, without a prompt, unless managed settings or a Team or Enterprise login is in place. Each is something someone has to install or wire up on purpose.

## What's denied, and what still runs

Each of these had the tool allowed, so that only the hook could stop it.

| Case | With a project file | Without one |
|---|---|---|
| `npm test && git merge --no-edit feature` | Denied, nothing ran, not merged | Ran and merged |
| `git commit --no-verify --allow-empty -m "..."` | Denied, no commit | Committed |
| Write a workflow with a `pull_request` trigger | `"ask"`, file not written | File written |
| `touch` a file | Ran | Not tried |

Told that a merge must come after the tests' results, the model will often go on to run the tests and the merge as two commands. It did so in 5 of 8 tries on a prompt that didn't forbid it. That's what the rule asks for, since the rule is about one command, so the test's prompt tells it to stop at a block.

## A broken check blocks

With `"onFailure": "block"`, each of these stopped an ordinary `touch`, and the file wasn't written: a script that exits 3, a script that's missing, and a script that runs past its timeout. A copy of the plugin with every execute bit removed still denied `git commit --no-verify`, because `hooks.json` runs each script through `sh`.

## The session-start check

Its line reached the session in a set-up repo where git hooks were off, and it printed nothing in a repo without a project file.

Run through `--plugin-dir` with no saved settings, a hook saw `CLAUDE_PLUGIN_OPTION_MAINTENANCE_INTERVAL_DAYS` empty, even though `plugin.json` gives the option a default. So the script's own fallback of 30 is what applies then.

## Trust in `-p`

A `-p` session shows no workspace trust dialog, as the docs say. The plugin's hooks ran in temp folders nobody had ever trusted. An allow rule in the project's own `.claude/settings.json` was ignored, with this on stderr: `Ignoring 1 permissions.allow entry from .claude/settings.json: this workspace has not been trusted`. So project allow rules don't decide anything in these results, and rules given by `--allowedTools` do.

## Limits

- Only a Bash matcher and a `Write|Edit` matcher were exercised in real sessions. The GitHub matcher is tested against tool names read from `hooks.json`, not against a live server.
- These sessions loaded no user settings, so a person's own rules and other plugins played no part.
- These checks catch mistakes and aren't a security boundary. They read the command's text, so a reset inside a script of its own isn't something they can see.
