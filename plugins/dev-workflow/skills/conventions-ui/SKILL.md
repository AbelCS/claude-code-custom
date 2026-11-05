---
name: conventions-ui
description: When building, changing or wording a screen, form, label, tooltip or message. The design system, copy, theme, accessibility and touch rules every screen follows.
---

# UI conventions

Say "Using conventions-ui to ..." first. UX is a first-class requirement, not polish for later. The project's own theme always wins: use ui-ux-pro-max for guidelines and accessibility checks and intent for UX thinking, but never their palettes or styles over the project's. Every touched screen passes `/dev-workflow:screen-check` before it's called done.

## The design system

Build from the design system: primitives plus the project's patterns, with a showcase page in the app. Look there before creating something new. A new pattern goes there too, with its states.

## Copy

`references/copy.md` has examples.

- **Short labels, hard rule:** one word, or as few as possible. Explanations go in a tooltip, and only where needed.
- **Never say it twice:** a tooltip, hint or description adds only what isn't visible, and no two places say the same thing.
- Mark optional fields quietly, through the design system's one way of doing it, never "(optional)".
- Reread every string before delivering it.

## Theme

- Theme tokens only, never raw palette colours.
- One type scale.
- Motion through motion tokens that respect reduced motion.
- Money and dates are formatted through one helper each, never by hand.

## Accessibility

- Contrast of 4.5:1 for text, and 3:1 for field outlines, icons and chart marks, in light and dark.
- Visible focus, and accessible names on every control.
- Meaning never colour alone: add text, an icon or a pattern.
- A menu equivalent for drag and drop.
- A skip link on every page.
- A screen-reader summary for each chart.

## Interaction

- Everything clickable shows the hand cursor, through one global rule.
- Explanations open on hover, keyboard focus and tap. Never rely on a native `title`, except for the full value of cut-off text.

## Phones and touch

- Nothing is wider than a 360 px phone. Wide tables scroll inside their card.
- On touch screens, fields are 16 px so phone browsers don't zoom in, and controls grow to 40 px. The desktop stays dense.

## Loading and failure

- Every page has its own loading skeleton.
- A save that never reaches the server shows a connection error instead of hanging.
