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

This writes the workflow rules into the project's `CLAUDE.md` (creating it if needed). The rules then apply to every Claude Code session in that project.

The same setup is also available as an auto-activating skill — Claude will offer to run it when it detects you are starting a new web project.

### dev-workflow

Run inside any project where you want issue-driven development enabled:

```text
/dev-workflow:enable-github-issues
```

This writes a "GitHub Issue-Driven Workflow" section into the project's `CLAUDE.md`. After that, when you paste a GitHub issue link from the project's repo, Claude will read the issue, branch, work, push, and open a PR that closes the issue.

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
        └── commands/
            ├── enable-github-issues.md  # /dev-workflow:enable-github-issues
            └── enable-releases.md       # /dev-workflow:enable-releases
```

## License

MIT
