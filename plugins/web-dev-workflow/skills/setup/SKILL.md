---
name: setup
description: Use when starting a new web development project or when the user wants to establish web dev workflow rules in the current project. Sets up CLAUDE.md with conventional commits, TDD, Serena, and Context7 requirements.
---

# Web Dev Workflow Setup

## Overview

Establishes web development workflow rules in the current project by writing them into `CLAUDE.md`. This ensures every Claude Code session in this project follows the same standards.

## What This Does

Appends the following rules to the project's `CLAUDE.md`:

### 1. Conventional Commits

All git commits MUST use conventional commit format:

- `feat: ...` — new feature or capability
- `fix: ...` — bug fix or change to existing feature without new functionality
- `docs: ...` — documentation only
- `style: ...` — formatting, no code change
- `refactor: ...` — code restructuring, no behavior change
- `test: ...` — adding or updating tests
- `chore: ...` — maintenance, dependencies, tooling

**Decision rule:** If it adds something that didn't exist before, it's `feat`. If it changes or corrects something that already exists without adding new functionality, it's `fix`.

### 2. Test-Driven Development (TDD)

All feature work and bug fixes MUST follow TDD:

1. **RED** — Write a failing test first
2. **GREEN** — Write minimal code to make it pass
3. **REFACTOR** — Clean up while keeping tests green

No implementation code without a failing test first.

### 3. Serena for Code Intelligence

Always use Serena (MCP plugin) for code navigation and editing in supported languages. Prefer Serena's semantic tools (`find_symbol`, `get_symbols_overview`, `replace_symbol_body`, etc.) over raw file reads and text edits when working with supported languages.

### 4. Context7 for Documentation

Always use Context7 (MCP plugin) to fetch up-to-date documentation for any framework, library, SDK, or API being used in the project. Use it even for well-known libraries — training data may be outdated. Prefer Context7 over web search for library docs.

### 5. Latest Stable Versions

Always use the latest stable compatible versions of dependencies, frameworks, libraries, and tools. When adding new dependencies or upgrading existing ones, target the latest stable release that is compatible with the project's current stack. Never default to outdated versions from training data — verify current versions via Context7 or package registries.

## Instructions

When this skill is invoked:

1. Read the project's `CLAUDE.md` if it exists (to avoid duplicating rules)
2. If these rules are NOT already present, append them to `CLAUDE.md`
3. If `CLAUDE.md` doesn't exist, create it with these rules
4. Confirm to the user what was added

Use this exact block when writing to `CLAUDE.md`:

```markdown
## Web Dev Workflow Rules

### Conventional Commits
All commits MUST use conventional commit format:
- `feat: ...` for new features or capabilities
- `fix: ...` for bug fixes or changes to existing features without new functionality
- `docs: ...` for documentation changes
- `style: ...` for formatting changes
- `refactor: ...` for code restructuring without behavior change
- `test: ...` for adding or updating tests
- `chore: ...` for maintenance and tooling

**Rule:** If it adds something new, use `feat`. If it changes/corrects existing behavior without new functionality, use `fix`.

### Test-Driven Development
All feature work and bug fixes MUST follow TDD (Red-Green-Refactor):
1. Write a failing test first
2. Write minimal code to make it pass
3. Refactor while keeping tests green

No implementation code without a failing test first.

### Serena for Code Intelligence
Always use Serena (MCP plugin) for code navigation and editing in supported languages. Prefer Serena's semantic tools (`find_symbol`, `get_symbols_overview`, `replace_symbol_body`, etc.) over raw file reads and text edits.

### Context7 for Documentation
Always use Context7 (MCP plugin) to fetch up-to-date documentation for any framework, library, SDK, or API used in the project. Prefer Context7 over web search for library docs — even for well-known libraries.

### Latest Stable Versions
Always use the latest stable compatible versions of dependencies, frameworks, libraries, and tools. Never default to outdated versions from training data — verify current versions via Context7 or package registries.
```
