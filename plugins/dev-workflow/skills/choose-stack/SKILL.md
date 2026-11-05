---
name: choose-stack
description: When a new project, or a new part of one, has no stack decided yet. Decides it from where it runs, who operates it, data limits, licences, and what a PoC and production need, one question at a time, and records the outcome as a spec and a decision-log line.
---

# Choose a stack

Say "Using choose-stack to ..." first. A stack is a product and architecture decision, so the owner makes it. This skill asks what decides it, weighs the options and records the outcome. `setup` hands over to it when no stack is decided, and carries on once it is.

**No default vendor.** No framework, host or database starts ahead. Each option earns its place from the answers, and the recommendation names what in them decided it.

## 1. Read what's known

Read the issue, `AGENTS.md`, `docs/superpowers/specs/` and `docs/decisions.md`, and any brief the owner gave. An answer already there is one you don't ask again: say what you read and use it.

## 2. Ask, one question at a time

One question at a time, recommendation first with why, and wait for the answer before the next. In this order:

1. **Where it runs:** in people's browsers, on a server, at the edge, on people's own machines or inside a private network. Which regions, whether it must work offline, and on which devices.
2. **Who operates it:** who deploys it, patches it, watches it and is woken when it fails, with what skills and how much time. What they already run, since a second platform is a cost too.
3. **Data limits:** what data it holds and how sensitive it is, where it may be stored, how long it's kept, how it's backed up and restored, and how much there will be: rows, files, requests. Personal, health, money or other regulated data follows the real practice of the people who do that work: research it first, and label any simplification as a trade-off.
4. **Licences:** the project's own licence, the licences its parts may have, and the terms of any hosted service. How hard it is to leave each one, and what that would cost.
5. **What the PoC needs:** the smallest thing that proves the idea, how soon, and what it may fake or leave out.
6. **What production needs:** users and load, availability, sign-in and roles, money, audit, accessibility and the budget. Which parts the PoC must already get right, because changing them later is expensive: usually the data model, permissions and where the data lives.

Skip a question the reading answered. If an answer changes an earlier one, say so and go back to it.

## 3. Weigh the options

Name two or three stacks that fit every answer. For each:

- what it fits and what it doesn't, against the answers in order;
- its cost to run and to operate, for the people named in question 2;
- how hard it is to leave, and its licences;
- its **current stable versions**, verified with Context7 or the official docs and release pages on the day, never from memory, with the date checked;
- whether `${CLAUDE_PLUGIN_ROOT}/stacks/` has a stack file for it. A stack without one is fine: all general rules still apply, and `setup` asks for its commands.

Then recommend one: why it wins, what it gives up, and what answer would change the choice. The owner decides. If they pick another, record theirs and why.

## 4. Record it

Write the spec to `docs/superpowers/specs/<YYYY-MM-DD>-stack-design.md`, using today's date:

- the answers to the six questions;
- the options weighed, and why each was or wasn't chosen;
- the decision, its versions and the date they were checked;
- what the PoC leaves out, and what must change before production;
- what's still open.

Show it to the owner and ask for approval. Once approved, add one line to `docs/decisions.md` linking it, in the form that file gives, such as `- 2026-11-06: Build on <stack>. [Spec](superpowers/specs/2026-11-06-stack-design.md)`. Both go in the same pull request as the work they start, the methodology's way.

## 5. Hand back

Give `setup`, or the person, the stack's parts and which of them have a stack file, for the project file's `stack`: the stack file names that apply, or none. Then go on with what called this.
