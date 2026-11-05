---
name: screen-check
description: After changing anything people see, such as a screen, component, style or wording. Checks every touched screen in a browser in light and dark, on a 360 px phone and by keyboard, with empty, filled and long content, and fixes what it finds before reporting.
---

# Screen check

Say "Using screen-check to ..." first. Tests prove the flows work. This proves the screens are right to use, so a screen isn't done until it passes.

## 1. Which screens

Every screen the change touches: the pages changed, and the pages using a changed component, style or string. When a shared primitive or token changed, that includes its entry on the design system's showcase page and a few screens that use it. List them before starting.

## 2. A browser

Use a browser tool: a browser MCP, Playwright, or the project's own end-to-end setup taking screenshots. Use the dev server if one is running, or start one. Never stop or restart a dev server someone else started.

If no browser tool is available, say so plainly, name what's missing and how to add it, and ask whether to go ahead without the check. Never skip it silently, and never call a screen checked that nobody looked at.

## 3. Each screen, every way

For every screen on the list, look at the rendered page, not the code:

- **Themes:** light and dark. Text, outlines, icons and chart marks keep their contrast in both.
- **Sizes:** a 360 px wide phone, and a desktop width. Nothing is wider than the phone: wide tables scroll inside their card. On touch, fields are 16 px and controls 40 px.
- **Keyboard only:** every action reachable in a sensible order, focus always visible, the skip link works, menus and dialogs open and close, and drag and drop has its menu equivalent.
- **Content:** empty, filled and long. No data at all, typical data, and long names, many rows and large numbers. Cut-off text shows its full value on hover and focus.
- **Loading and failure:** the page's loading skeleton, and a save that can't reach the server showing a connection error instead of hanging.
- **The console:** no errors or warnings caused by the change.

Hold what you see to `/dev-workflow:conventions-ui`: the project's own theme, its copy rules and its accessibility rules. ui-ux-pro-max has accessibility checks that help here.

## 4. Fix, then look again

Fix what you find before reporting, test first where it's behaviour. Then check that screen again in every way it failed, and in the ways the fix could have affected.

## 5. Report

Say which screens were checked, in which themes, sizes and states, and by keyboard. Then what was found and fixed. Say what couldn't be checked, and why.
