# Decisions

One line per significant decision, newest last, linking its spec.

- 2026-11-05: Merge the plugins into one, `dev-workflow`, holding the whole methodology. [Spec](superpowers/specs/2026-11-05-dev-workflow-methodology-design.md)
- 2026-11-05: Remove `web-dev-workflow` with a marketplace rename to `dev-workflow`, and remove `enable-github-issues`, whose rules setup now writes. [Spec](superpowers/specs/2026-11-05-dev-workflow-methodology-design.md#4-decisions), [PR 12](https://github.com/AbelCS/claude-code-custom/pull/12)
- 2026-11-05: No hard plugin dependencies. Setup checks for the recommended plugins and offers to install them. [Spec](superpowers/specs/2026-11-05-dev-workflow-methodology-design.md#4-decisions)
- 2026-11-05: Choices that apply to every project live in the plugin's settings. Facts about one project live in `.claude/dev-workflow.json`. [Spec](superpowers/specs/2026-11-05-dev-workflow-methodology-design.md#6-settings)
- 2026-11-05: Rules that must always hold are enforced by git hooks and Claude Code hooks. Judgment stays in `AGENTS.md` and skills. [Spec](superpowers/specs/2026-11-05-dev-workflow-methodology-design.md#8-enforcement), [PR 9](https://github.com/AbelCS/claude-code-custom/pull/9)
- 2026-11-05: Maintenance is started by a person, with a session-start reminder when it's due. [Spec](superpowers/specs/2026-11-05-dev-workflow-methodology-design.md#92-maintain)
- 2026-11-05: The hooks catch mistakes and aren't a security boundary. They read a command's text, so some shell forms are known limits and aren't blocked: `eval`, `sh -c`, aliases and functions, and a `cd` inside a subshell, which counts for the rest of the command. A local merge that slips through still can't reach the default branch past `pre-push`. [Limits](hook-behaviour.md#limits), [the command splitter](../plugins/dev-workflow/scripts/lib/split-command.awk)
- 2026-11-05: A database reset asks a person, rather than being denied: real sessions in several permission modes never ran one without a person. [Hook behaviour](hook-behaviour.md#ask-on-a-database-reset)
- 2026-11-05: Merging through GitHub's MCP tool is blocked outright, because it can't keep the squash message blank. Merges go through `gh pr merge`. [PR 9](https://github.com/AbelCS/claude-code-custom/pull/9)
- 2026-11-05: From part 3 of the build on, one implementer per task and one independent review per part, and two test setups instead of four, to cut cost. [Spec](superpowers/specs/2026-11-05-dev-workflow-methodology-design.md#4-decisions)
- 2026-11-06: A project gets a README and docs at a stable 1.0.0, or earlier if the owner asks, kept current. [Spec](superpowers/specs/2026-11-05-dev-workflow-methodology-design.md#appendix-a-the-methodology), [PR 11](https://github.com/AbelCS/claude-code-custom/pull/11)
- 2026-11-06: Docs and READMEs go to their own model setting. Research, product thinking, design critique, specs and plans go to the non-coding model. [Spec](superpowers/specs/2026-11-05-dev-workflow-methodology-design.md#6-settings), [PR 12](https://github.com/AbelCS/claude-code-custom/pull/12)
