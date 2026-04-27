---
description: Configure this project with the web dev workflow rules (conventional commits, TDD, Serena, Context7, latest stable versions, commit discipline) by writing them to AGENTS.md (with a CLAUDE.md pointer for compatibility).
allowed-tools: Read, Write, Edit
---

Run the `setup` skill from this plugin to configure the current project's `AGENTS.md` with the web development workflow rules.

The skill is located at `skills/setup/SKILL.md` within this plugin and contains the canonical instructions, including:

- Migrating any existing `CLAUDE.md` content into `AGENTS.md`.
- Replacing `CLAUDE.md` with a pointer to `AGENTS.md`.
- Appending the rule block to `AGENTS.md` (de-duplicating any sections already present).
- Confirming to the user what was added or migrated.
