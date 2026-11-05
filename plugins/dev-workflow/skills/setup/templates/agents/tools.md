## Tools

These rules override the defaults of the skills and plugins they name.

- Superpowers is the process, and skills are announced ("Using brainstorming to ..."): `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion`, `receiving-code-review`. `/dev-workflow:land` replaces `finishing-a-development-branch`.
- `/dev-workflow:choose-stack` before choosing or changing a stack.
- Code follows `/dev-workflow:conventions-code`. Screens follow `/dev-workflow:conventions-ui`, and every touched screen passes `/dev-workflow:screen-check` before it's called done.
- Context7 for current docs.
- Serena for reading and changing code by symbol, moves and renames. No Serena memories: what's worth keeping goes in `AGENTS.md` or `docs/`.
- A read-only database MCP on the local stack, when the database has one.
- intent for UX thinking, ui-ux-pro-max for UI guidelines and accessibility checks. The project's own theme overrides their palettes and styles, and intent takes its context from this file and `docs/`.
- `/security-review` for changes to permissions, sign-in or anything public.
- Larger pull requests get `/dev-workflow:independent-review` before merging. Check each finding against the code before acting on it.
- `/dev-workflow:maintain` for upkeep, run by a person when it's due.
