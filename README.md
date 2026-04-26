# claude-code-custom

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace by [AbelCS](https://github.com/AbelCS).

## Available plugins

| Plugin | Description |
|---|---|
| [web-dev-workflow](plugins/web-dev-workflow) | Establishes web development workflow rules (conventional commits, TDD, Serena, Context7, latest stable versions, commit discipline) in any project. |

## Installation

Add this marketplace from GitHub, then install the plugins you want.

```text
/plugin marketplace add AbelCS/claude-code-custom
/plugin install web-dev-workflow@claude-code-custom
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

## Repository layout

```
.
├── .claude-plugin/
│   └── marketplace.json     # Marketplace manifest
└── plugins/
    └── web-dev-workflow/
        ├── .claude-plugin/
        │   └── plugin.json  # Plugin manifest
        ├── commands/
        │   └── setup.md     # /web-dev-workflow:setup
        └── skills/
            └── setup/
                └── SKILL.md # Auto-activating setup skill
```

## License

MIT
