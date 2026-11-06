# claude-code-custom

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace by [AbelCS](https://github.com/AbelCS). It holds one plugin, `dev-workflow`: one development methodology for any web project, set up by one command, `/dev-workflow:setup`. The rules that must always hold are enforced by hooks, so they don't depend on anyone remembering them.

## Quick start

1. Add the marketplace and install the plugin:

   ```text
   /plugin marketplace add AbelCS/claude-code-custom
   /plugin install dev-workflow@claude-code-custom
   ```

2. Set up each project you want to use it in:

   ```text
   /dev-workflow:setup
   ```

3. Start working. Describe what you want in plain words, such as "Add search to the products page."

Check [Requirements](#requirements) for what you need first.

## Setting up a project

`/dev-workflow:setup` does this, once per project:

- It reads the repo and checks the tools. It works on a new project, an existing one, or one set up with an older version.
- It asks only what it can't read, one question at a time, with its recommendation first: the stack, the commands for `check` and `verify`, whether there are screens or a database, and a few approvals.
- It shows every file it would create or update, and every conflict it will leave alone. It writes nothing until you say yes.
- After the yes, it writes `.claude/dev-workflow.json`, the rules in `AGENTS.md` and a `CLAUDE.md` that imports them, the git hooks in `.githooks/`, the attribution settings, and `docs/decisions.md` and `docs/maintenance.md` if they're missing. It also turns the git hooks on.
- With your approval, it also sets the GitHub repo to squash-only merges with a blank message, and to delete merged branches.
- Git hooks aren't cloned. In a fresh clone, turn them on yourself:

  ```sh
  git config core.hooksPath .githooks
  ```

- If setup added a `prepare` script to `package.json`, `npm install` does it for you. If you forget, the session start warns you.

## A day with dev-workflow

Say you want to add search. You type almost nothing special: you describe the work.

1. **Issue.** Ask Claude to open one, with an objective, scope and acceptance criteria. The rules ask for it before any meaningful work.
2. **Branch.** Claude creates `<type>/<issue>-<slug>`, like `feat/12-search`. The issue number comes back in every commit subject, and `commit-msg` reads it from the branch name.
3. **Work.** Ask for the feature. Skills come in on their own: tests first, a failure debugged properly, code and screens built to the rules. You type nothing.
4. **Commit.** Git runs `pre-commit`, which checks formatting of staged files and blocks a workflow gaining a per-PR trigger. Then `commit-msg` checks the subject, like `feat: add product search (#12)`, and rejects AI attribution.
5. **Push.** `pre-push` runs the project's `check` command and refuses a direct push to the default branch. If `check` fails, the push doesn't happen.
6. **Finish.** Say "land this", or just "this is done, merge it". `land` checks the acceptance criteria, runs `verify`, asks for an independent review of a larger change and a screen check if screens changed, opens the pull request, squash-merges it once green, and updates your default branch. It asks first only for a change you haven't approved that alters what people see or do, money rules or permissions.

At the end, Claude says what landed and what was verified.

## What you type

| Command | When |
|---|---|
| `/dev-workflow:setup` | Once per project, and again after updating the plugin |
| `/dev-workflow:maintain` | The session-start line says maintenance is overdue. It never runs on a schedule |
| `/dev-workflow:enable-releases` | You want release-please set up in a GitHub repo |

You can call any skill by name, such as `/dev-workflow:land`, at any time. You don't have to. Say what you want in plain words, such as "check the screens I changed" or "get an outside review of this pull request", and the right skill comes in. Claude says "Using screen-check to ..." when one does.

## What happens by itself

Nine skills. Seven come in on their own when their trigger comes up. Two start only when you type them.

**Comes in on its own** (you can also call it by name):

| Skill | What it does | When it comes in |
|---|---|---|
| `/dev-workflow:setup` | Sets up or upgrades a repo with the methodology | You ask to set up or upgrade a repo, or start a new web project |
| `/dev-workflow:choose-stack` | Decides the stack, one question at a time, and records it | A new project, or part of one, has no stack decided |
| `/dev-workflow:conventions-code` | Applies the module shape, boundaries and data rules | You decide where code, a query or a permission check goes, add a table, or change how data is read or saved |
| `/dev-workflow:conventions-ui` | Applies the design system, copy, theme, accessibility and touch rules | You build, change or word a screen, form, label or message |
| `/dev-workflow:screen-check` | Checks every touched screen in a browser and fixes what it finds | Anything people see has changed |
| `/dev-workflow:independent-review` | Gets a review by another model, with a narrow brief, and checks each finding against the code | A pull request is larger than `review_threshold_lines`, or you ask for an outside review |
| `/dev-workflow:land` | Confirms the issue is met, runs `verify` and the reviews needed, opens the pull request, squash-merges it when green and updates the default branch | Work on a branch is finished and ready to merge |

**Only when you type it:**

| Skill | What it does | When to type it |
|---|---|---|
| `/dev-workflow:maintain` | Sweeps branches, dead code, dependencies, code smells, docs and the setup, and records the run in `docs/maintenance.md` | Maintenance is due |
| `/dev-workflow:enable-releases` | Sets up release-please in a GitHub repo | You want releases set up |

Superpowers skills come in alongside these: `brainstorming` shapes a new idea, `test-driven-development` writes the test first, and `systematic-debugging` handles a failure.

The session-start check also runs by itself. See [Guardrails](#guardrails).

## Guardrails

Two layers check the rules. Both do nothing in a repo that hasn't run `/dev-workflow:setup`: the Claude Code hooks look for `.claude/dev-workflow.json` first, and the git hooks exist only where setup wrote them.

**Git hooks** are copied into the project by setup. They work for anyone who commits there, with or without Claude Code or this plugin. A fresh clone has to turn them on (see [Setting up a project](#setting-up-a-project)).

| Hook | When it runs | What it checks |
|---|---|---|
| `commit-msg` | Every commit | Conventional Commit format. The issue number in the subject, on a `<type>/<issue>-<slug>` branch. No AI attribution, along with the project's attribution settings |
| `pre-commit` | Every commit | Staged files are formatted. No workflow gains a per-pull-request trigger |
| `pre-push` | Every push | Checks pass: it runs the project's `check` command. No direct push to the default branch |

**Claude Code hooks** come with the plugin. They apply only to Claude's own commands and edits.

| Hook | When it runs | What it does |
|---|---|---|
| Commands | Before each Bash command | Blocks a merge chained after tests, a local merge into the default branch, `--no-verify` on commits, AI attribution in `gh` text, a pull request title without the right format or a closing keyword, and a squash merge without a blank message. Asks for a person's yes before a database reset |
| GitHub tools | Before each GitHub MCP call | Blocks AI attribution, and merging that way |
| Workflow edits | Before each file write and edit | Asks for a person's yes before a workflow gains a per-pull-request trigger |
| Session start | Every session in a set-up project | Prints one line for each problem: git hooks off, a tool or plugin missing, rules out of date, maintenance overdue. It is silent when all is well |

**What you see.** A block is a message that says why and what to do instead. You see it as the command's result, and Claude acts on it. Two examples:

```text
dev-workflow: --no-verify skips the git hooks, and -n means the same on git commit.
Run the command without it, and fix what the hooks report.
```

```text
commit-msg: this branch is for issue #12: end the subject with (#12), got: feat: add search
```

Some actions ask for your approval instead of being blocked. A database reset command gets "this looks like a database reset, which destroys data, so it needs a person's yes." A write that gives a workflow a per-PR trigger gets "this gives `<file>` a trigger on `<event>`, and CI runs only for releases, so it needs a person's yes." Without a person to answer, an approval request acts as a denial.

A hook that breaks blocks the action, so a broken check never lets a command through. These checks catch mistakes. They read a command's text, so they aren't a security boundary. Judgment rules, such as test-first and honest reporting, stay as guidance in `AGENTS.md` and the skills.

`docs/hook-behaviour.md` records what the hooks were seen to do in real sessions, including what wasn't tested.

## Settings

The plugin has ten settings. Skills and hooks read them, so no model name is written into a skill or a project's rules.

| Key | Default | What it's for |
|---|---|---|
| `model_noncoding` | `claude-fable-5-1` | Research, product thinking, design critique, specs and plans |
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

## Updating

Auto-update is off for this marketplace by default. To update:

```text
/plugin marketplace update claude-code-custom
claude plugin update dev-workflow@claude-code-custom
/reload-plugins
```

The first and third are commands inside Claude Code. The second runs in your terminal. Then rerun `/dev-workflow:setup` in each project, to upgrade its rules. Setup replaces a rule section only if you haven't edited it. If you have, it leaves your text and shows the difference. Nothing changes a project until you run it there.

### Upgrade notes

For people coming from 0.x or from `web-dev-workflow`.

- `/web-dev-workflow:setup` and `/dev-workflow:enable-github-issues` are gone. Use `/dev-workflow:setup` for both.
- If you used `web-dev-workflow`, run `claude plugin install dev-workflow@claude-code-custom` once, after `/plugin marketplace update claude-code-custom`. The marketplace renames the old plugin, but without this step the new one is turned on and doesn't load ("not cached"). Use `install` here and not `update`: `update` can fix only the project you run it in. A project whose committed `.claude/settings.json` named `web-dev-workflow` has that key rewritten the first time a session runs there, which leaves a change to commit.
- Old projects keep working, but their rules didn't load. The old `CLAUDE.md` pointer didn't import them. Rerun `/dev-workflow:setup` in each one, which recognises the old blocks and pointers and replaces them.
- `/dev-workflow:enable-releases` now creates a workflow that runs only when you start it. Existing workflows aren't changed. If one runs release-please on every push, the skill says so and offers to replace it.
- A manual release takes two runs. The first, from the Actions tab or `gh workflow run release-please.yml`, opens or updates the release pull request. After you merge it, a second run tags the release.
- The optional release check needs a token secret of its own, such as `RELEASE_PLEASE_TOKEN`. Pull requests opened with the default `GITHUB_TOKEN` don't start other workflows, so the check would never run. Without the check, the release workflow can use `GITHUB_TOKEN`. Also turn on "Allow GitHub Actions to create and approve pull requests" in the repo's Actions settings.

## Requirements

Setup stops if a required tool is missing.

- `git`
- `gh`, signed in
- `jq`
- Claude Code 2.1.295 or later

Setup checks for these recommended plugins and offers to install the missing ones:

- Superpowers
- Context7
- Serena
- intent
- ui-ux-pro-max

The Codex CLI is optional. `/dev-workflow:independent-review` needs it, and setup warns if it's missing.

## Developing this repo

This repo follows the methodology it ships. `AGENTS.md` has its rules, and every change starts from an issue.

After a fresh clone, turn on the git hooks:

```sh
git config core.hooksPath .githooks
```

| Command | What it does |
|---|---|
| `scripts/check` | Script tests, plugin validation and shell lint. `pre-push` runs it |
| `scripts/verify` | `check`, then the slower tests in `tests/verify_only/`: the leak search, the install and update tests, live hook tests that spend a few cents on real sessions, and end-to-end setup tests on the sample apps, with their database tests in Docker |
| `sh tests/<name>.test.sh` | One test |
| `claude plugin eval plugins/dev-workflow --ablation none --max-cost-usd 4` | The skill evals: does each skill come in on natural phrasing and stay out otherwise. Real sessions, about $3 |

Two variables skip the slowest parts of `scripts/verify`, and it says so when they do. `DW_SKIP_LIVE=1` skips the live hook tests. `DW_SKIP_FIXTURES=1` skips the end-to-end setup tests on sample apps, which install packages and start Docker containers.

Tools needed: `git`, `gh`, `jq`, `uvx`, `claude` (2.1.295 or later) and `npm`, plus `uv`, `nc` and a running Docker for the fixtures test. The leak search also needs `.leak-terms.local`, a private git-ignored file.

## License

MIT. See [LICENSE](LICENSE).
