# claude-code-custom

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace by [AbelCS](https://github.com/AbelCS).

## Available plugins

| Plugin | Description |
|---|---|
| [web-dev-workflow](plugins/web-dev-workflow) | Establishes web development workflow rules (conventional commits, TDD, Serena, Context7, latest stable versions, commit discipline) in any project. |
| [dev-workflow](plugins/dev-workflow) | General development workflow tooling for GitHub-hosted projects: issue-driven development and release-please setup. |

## Installation

Add this marketplace from GitHub, then install the plugins you want.

```text
/plugin marketplace add AbelCS/claude-code-custom
/plugin install web-dev-workflow@claude-code-custom
/plugin install dev-workflow@claude-code-custom
```

To update later:

```text
/plugin marketplace update claude-code-custom
```

## Usage

### web-dev-workflow

Once installed, run inside any project where you want the workflow rules applied:

```text
/web-dev-workflow:setup
```

This writes the workflow rules into the project's `AGENTS.md` (creating it if needed) and ensures `CLAUDE.md` exists as a pointer to `AGENTS.md` for Claude Code compatibility. If a populated `CLAUDE.md` already exists, its content is migrated into `AGENTS.md` first. The rules then apply to every Claude Code (or other agent) session in that project.

The same setup is also available as an auto-activating skill — Claude will offer to run it when it detects you are starting a new web project.

### dev-workflow

Run inside any project to set it up with the methodology, or to upgrade an earlier setup:

```text
/dev-workflow:setup
```

It looks at the repo, checks the tools and plugins it relies on, asks what it can't tell one question at a time, and shows every file it would create or update. Nothing is written until you agree. It writes `AGENTS.md` with sections it keeps up to date, a `CLAUDE.md` that imports it, the git hooks, `.claude/dev-workflow.json` and the attribution settings. Text you edited is kept, and shown as a difference. It replaces `/dev-workflow:enable-github-issues`.

To enable automated, conventional-commit-driven releases via [release-please](https://github.com/googleapis/release-please):

```text
/dev-workflow:enable-releases
```

This detects the project type (node, python, rust, …), creates `release-please-config.json`, `.release-please-manifest.json`, and `.github/workflows/release-please.yml`, and prints next steps.

## Repository layout

```
.
├── .claude-plugin/
│   └── marketplace.json     # Marketplace manifest
└── plugins/
    ├── web-dev-workflow/
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   ├── commands/
    │   │   └── setup.md          # /web-dev-workflow:setup
    │   └── skills/
    │       └── setup/
    │           └── SKILL.md      # Auto-activating setup skill
    └── dev-workflow/
        ├── .claude-plugin/
        │   └── plugin.json
        ├── commands/
        │   └── enable-releases.md       # /dev-workflow:enable-releases
        ├── hooks/                       # Claude Code hooks
        ├── scripts/                     # The hooks' scripts and setup's mechanical work
        ├── skills/                      # /dev-workflow:setup, choose-stack and the rest
        └── stacks/                      # What the methodology means for each stack
```

## License

MIT
