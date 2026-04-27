---
name: setup
description: Use when starting a new web development project or when the user wants to establish web dev workflow rules in the current project. Sets up AGENTS.md (with a CLAUDE.md pointer) with conventional commits, TDD, Serena, and Context7 requirements.
---

# Web Dev Workflow Setup

## Overview

Establishes web development workflow rules in the current project by writing them into `AGENTS.md`. `CLAUDE.md` is maintained as a thin pointer to `AGENTS.md` for Claude Code compatibility. This ensures every Claude Code (or other agent) session in this project follows the same standards.

## What This Does

Appends the following rules to the project's `AGENTS.md`:

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

### 6. Commit Discipline

After completing a set of changes or before switching to a different task, commit your work if there are uncommitted changes. Do not let changes accumulate across unrelated tasks — keep commits focused and timely.

## Instructions

When this skill is invoked:

### Step 1: Normalize the agent-instructions files

This plugin treats `AGENTS.md` as the canonical agent instructions file. `CLAUDE.md`, when present, is a thin pointer to `AGENTS.md`.

Before writing any rules:

1. Read `AGENTS.md` and `CLAUDE.md` if they exist.
2. If `CLAUDE.md` exists and contains anything beyond a pointer to `AGENTS.md`, migrate its content into `AGENTS.md`: append sections that aren't already in `AGENTS.md`, do NOT duplicate sections that are.
3. Overwrite `CLAUDE.md` with exactly this content (or create it if missing):

   ```markdown
   # CLAUDE.md

   The canonical agent instructions for this project live in [AGENTS.md](./AGENTS.md).
   ```

4. If `AGENTS.md` does not exist after migration, create it (an empty file is fine — content is appended below).

### Step 2: Write the rule block

5. If the rule block below is NOT already present in `AGENTS.md`, append it. If it is already present (in part or whole), only append the missing sections.
6. Confirm to the user what was added, what was migrated from `CLAUDE.md`, and that `CLAUDE.md` is now a pointer.

Use this exact block when writing to `AGENTS.md`:

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

### Commit Discipline
After completing a set of changes or before switching to a different task, commit your work if there are uncommitted changes. Do not let changes accumulate across unrelated tasks — keep commits focused and timely.
```
