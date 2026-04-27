---
description: Enable issue-driven development in this project by writing the GitHub issue workflow rules into AGENTS.md (with a CLAUDE.md pointer for compatibility).
allowed-tools: Read, Write, Edit
---

Enable the issue-driven development workflow in the current project.

## Step 1: Normalize the agent-instructions files

This plugin treats `AGENTS.md` as the canonical agent instructions file. `CLAUDE.md`, when present, is a thin pointer to `AGENTS.md`.

Before writing any rules:

1. Read `AGENTS.md` and `CLAUDE.md` if they exist.
2. If `CLAUDE.md` exists and contains anything beyond a pointer to `AGENTS.md`, migrate its content into `AGENTS.md`: append sections that aren't already in `AGENTS.md`, do NOT duplicate sections that are.
3. Overwrite `CLAUDE.md` with exactly this content (or create it if missing):

   ```markdown
   # CLAUDE.md

   The canonical agent instructions for this project live in [AGENTS.md](./AGENTS.md).
   ```

4. If `AGENTS.md` does not exist after migration, create it.

## Step 2: Write the rule block

5. If the rule block below is NOT already present in `AGENTS.md`, append it. If it is partially present, only append the missing sections.
6. Confirm to the user what was added, what was migrated from `CLAUDE.md`, and that `CLAUDE.md` is now a pointer.

Use this exact block:

```markdown
## GitHub Issue-Driven Workflow

When the user provides a link to an issue in this project's GitHub repository, follow this workflow:

### 1. Understand the issue
- Fetch it with `gh issue view <number> --comments` (or by URL).
- Read the title, body, labels, and all comments. Follow links to related issues, PRs, or design docs.
- Do not start work until the requirements are clear. If anything is ambiguous, ask the user before proceeding.

### 2. Mark the issue as in progress
- Assign yourself: `gh issue edit <number> --add-assignee @me`.
- If the repo uses a project board, move the issue to the "In Progress" column.
- Optionally post a brief comment on the issue indicating that work has started.

### 3. Create a branch
- Branch from the default branch.
- Use a descriptive name following the convention `<type>/<issue-number>-<short-slug>`, e.g. `feat/123-add-login`, `fix/456-null-pointer`.
- The `<type>` should match the conventional commit type the eventual PR will use (`feat`, `fix`, `docs`, `refactor`, etc.).

### 4. Implement the change
- Follow the project's other workflow rules (conventional commits, TDD, commit discipline, etc.).
- Make incremental commits — do not let unrelated changes accumulate.

### 5. Push and open a PR
- Push the branch with upstream tracking: `git push -u origin <branch>`.
- Open the PR with `gh pr create`. The PR description MUST include a closing keyword that links the issue, e.g. `Closes #123`, so the issue auto-closes on merge.
- Use a PR title that follows conventional commit format and clearly summarizes the change.

### 6. Update issue status after PR opens
- Verify the issue is linked from the PR (the closing keyword does this automatically).
- If the repo uses a project board, move the issue to "In Review" (or the equivalent column).
- Report the PR URL back to the user.
```
