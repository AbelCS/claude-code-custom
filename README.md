# claude-code-custom

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace by [AbelCS](https://github.com/AbelCS). It holds one plugin, `dev-workflow`.

## What dev-workflow is

dev-workflow is one development methodology for any web project. One command, `/dev-workflow:setup`, sets a project up with it: the rules in `AGENTS.md`, git hooks and a project file. The rules that must always hold are enforced by hooks, so they don't depend on anyone remembering them.

## Installation

Add the marketplace, then install the plugin:

```text
/plugin marketplace add AbelCS/claude-code-custom
/plugin install dev-workflow@claude-code-custom
```

Then run this in each project you want to set up:

```text
/dev-workflow:setup
```

Setup looks at the repo, checks the tools, asks what it can't detect one question at a time, and shows every file it would write. It writes nothing until you say yes. It works on a new project, an existing one, or one set up with an older version.

**Requirements.** Setup stops if one is missing.

- `git`
- `gh`, signed in
- `jq`
- Claude Code 2.1.295 or later

**Recommended plugins.** Setup checks for these and offers to install the missing ones:

- Superpowers
- Context7
- Serena
- intent
- ui-ux-pro-max

The Codex CLI is optional. `/dev-workflow:independent-review` needs it, and setup warns if it's missing.

## Updating

Auto-update is off for this marketplace by default. To update:

```text
/plugin marketplace update claude-code-custom
claude plugin update dev-workflow@claude-code-custom
/reload-plugins
```

The first and third are commands inside Claude Code. The second runs in your terminal. Then rerun `/dev-workflow:setup` in each project, to upgrade its rules. Setup replaces a rule section only if you haven't edited it. If you have, it leaves your text and shows the difference. Nothing changes a project until you run it there.

## Skills

Nine skills. Seven are used automatically when their trigger comes up, and you can call them yourself too. Two are command only.

| Skill | Used when |
|---|---|
| `/dev-workflow:setup` | Setting up or upgrading a repo, or starting a new web project |
| `/dev-workflow:choose-stack` | A new project, or part of one, has no stack decided yet |
| `/dev-workflow:land` | Work on a branch is finished and ready to merge |
| `/dev-workflow:independent-review` | A larger pull request is about to merge, or you ask for an outside review by another model |
| `/dev-workflow:screen-check` | Anything people see has changed |
| `/dev-workflow:conventions-code` | Deciding where code, a query or a permission check goes, or changing how data is read or saved |
| `/dev-workflow:conventions-ui` | Building, changing or wording a screen, form, label or message |
| `/dev-workflow:maintain` | **Command only.** Maintenance is due. It sweeps branches, dead code, dependencies, code smells, docs and the setup, and records the run in `docs/maintenance.md` |
| `/dev-workflow:enable-releases` | **Command only.** Setting up release-please in a GitHub repo |

## What's enforced

There are two layers.

- **Git hooks** are copied into the project by setup. They work for anyone who commits there, with or without Claude Code or this plugin. A fresh clone has to turn them on: setup says how, usually `git config core.hooksPath .githooks`.
- **Claude Code hooks** come with the plugin. They apply only to Claude's own commands and edits.

Both layers do nothing in a repo that hasn't run `/dev-workflow:setup`. The Claude Code hooks look for `.claude/dev-workflow.json` first, and the git hooks exist only where setup wrote them. A hook that breaks blocks the action, so a broken check never lets a command through.

| Rule | Where it's enforced |
|---|---|
| Conventional Commit format | Git hook (`commit-msg`) |
| Issue number in the subject, on a `<type>/<issue>-<slug>` branch | Git hook (`commit-msg`) |
| No AI attribution in commits | Git hook (`commit-msg`) and the project's attribution settings |
| Checks pass before a push | Git hook (`pre-push`), which runs the project's `check` command |
| No direct push to the default branch | Git hook (`pre-push`) |
| Staged files are formatted | Git hook (`pre-commit`) |
| No per-pull-request workflow trigger | Git hook (`pre-commit`) and a Claude Code hook on writes |
| No AI attribution in pull requests, issues, comments and releases | Claude Code hook |
| Squash merges with a blank message | Claude Code hook |
| Pull request title format and a closing keyword | Claude Code hook |
| No local merge into the default branch | Claude Code hook |
| No `--no-verify` on commits | Claude Code hook |
| A database reset needs a person's yes | Claude Code hook |
| No merge chained after tests | Claude Code hook |
| One-line warnings at session start: git hooks off, a plugin missing, rules out of date, maintenance overdue | Claude Code hook |

These checks catch mistakes. They read a command's text, so they aren't a security boundary. Judgment rules, such as test-first and honest reporting, stay as guidance in `AGENTS.md` and the skills.

`docs/hook-behaviour.md` records what the hooks were seen to do in real sessions, including what wasn't tested.

## Settings

The plugin has ten settings. Skills and hooks read them, so no model name is written into a skill or a project's rules.

| Key | Default | What it's for |
|---|---|---|
| `model_noncoding` | `claude-fable-5-1` | Research, product thinking and design critique |
| `model_noncoding_alt` | `gpt-6-astra` | A second opinion on the same work, from OpenAI through the Codex CLI |
| `model_docs` | `claude-sonnet-5-5` | Docs, READMEs and similar writing |
| `effort_docs` | `high` | Reasoning effort for docs |
| `model_coding` | `claude-opus-5-5` | Writing code |
| `effort_coding` | `high` | Reasoning effort for code |
| `reviewer_name` | `GPT-6.1 Sol (OpenAI, high effort, read-only)` | Shown when an independent review is announced |
| `reviewer_command` | `codex exec -m gpt-6.1-sol -c model_reasoning_effort=high --sandbox read-only "<brief>" < /dev/null` | The command that runs an independent review, with `<brief>` where the brief goes |
| `review_threshold_lines` | `300` | A pull request with more changed lines than this gets an independent review |
| `maintenance_interval_days` | `30` | The session-start check says maintenance is overdue after this many days |

### How to change a default

Open `/config` in Claude Code and change the plugin's settings there. A value you haven't saved falls back to the plugin's default above.

## Upgrade notes

For people coming from 0.x or from `web-dev-workflow`.

- `/web-dev-workflow:setup` and `/dev-workflow:enable-github-issues` are gone. Use `/dev-workflow:setup` for both.
- If you used `web-dev-workflow`, run `claude plugin install dev-workflow@claude-code-custom` once, after `/plugin marketplace update claude-code-custom`. The marketplace renames the old plugin, but without this step the new one is turned on and doesn't load ("not cached"). Use `install` here and not `update`: `update` can fix only the project you run it in. A project whose committed `.claude/settings.json` named `web-dev-workflow` has that key rewritten the first time a session runs there, which leaves a change to commit.
- Old projects keep working, but their rules didn't load. The old `CLAUDE.md` pointer didn't import them. Rerun `/dev-workflow:setup` in each one, which recognises the old blocks and pointers and replaces them.
- `/dev-workflow:enable-releases` now creates a workflow that runs only when you start it. Existing workflows aren't changed. If one runs release-please on every push, the skill says so and offers to replace it.
- A manual release takes two runs. The first, from the Actions tab or `gh workflow run release-please.yml`, opens or updates the release pull request. After you merge it, a second run tags the release.
- The optional release check needs a token secret of its own, such as `RELEASE_PLEASE_TOKEN`. Pull requests opened with the default `GITHUB_TOKEN` don't start other workflows, so the check would never run. Without the check, the release workflow can use `GITHUB_TOKEN`. Also turn on "Allow GitHub Actions to create and approve pull requests" in the repo's Actions settings.

## Developing this repo

This repo follows the methodology it ships. `AGENTS.md` has its rules, and every change starts from an issue.

After a fresh clone, turn on the git hooks:

```sh
git config core.hooksPath .githooks
```

| Command | What it does |
|---|---|
| `scripts/check` | Script tests, plugin validation and shell lint. `pre-push` runs it |
| `scripts/verify` | `check`, then the slower tests in `tests/verify_only/`: the leak search, the install and update tests, and live hook tests that spend a few cents on real sessions |
| `sh tests/<name>.test.sh` | One test |

Two variables skip the slowest parts of `scripts/verify`, and it says so when they do. `DW_SKIP_LIVE=1` skips the live hook tests. `DW_SKIP_FIXTURES=1` skips the end-to-end setup tests on sample apps, which install packages and start Docker containers.

Tools needed: `git`, `gh`, `jq`, `uvx`, `claude` (2.1.295 or later) and `npm`, plus `uv`, `nc` and a running Docker for the fixtures test. The leak search also needs `.leak-terms.local`, a private git-ignored file.

## License

MIT. See [LICENSE](LICENSE).
