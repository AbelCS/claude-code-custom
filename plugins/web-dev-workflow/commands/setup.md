---
name: setup
description: Configure this project with the web dev workflow rules (conventional commits, TDD, Serena, Context7, latest stable versions, commit discipline) by writing them to CLAUDE.md.
---

Run the `setup` skill from this plugin to configure the current project's `CLAUDE.md` with the web development workflow rules.

The skill is located at `skills/setup/SKILL.md` within this plugin and contains the canonical instructions and the exact rule block to write.

Steps:

1. Read the project's `CLAUDE.md` if it exists, to avoid duplicating rules already present.
2. If the rules are not present, append them; if `CLAUDE.md` does not exist, create it with the rule block from the skill.
3. Confirm to the user what was added (or that the rules were already present).
