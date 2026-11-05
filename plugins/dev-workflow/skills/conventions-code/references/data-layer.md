# The data layer

Permissions are enforced in the data layer as well as in code, with or without row-level security. Code checks give clear errors. The data layer makes sure a missed check can't leak or change what it shouldn't. Choose the route that fits the database, and record it in `AGENTS.md`'s Code organisation section.

## Two routes

**Where the database enforces access rules on each row:**

- Every table has a rule for each operation it allows, and anything not allowed is refused.
- Reads and writes for a person run as that person, so the database applies their rules.
- A connection that bypasses the rules is used only by tasks that need it, and each such use is named and explained in the code.
- Actions still check permissions in code first, for clear errors.

**Where it doesn't, or the project doesn't use it:**

- Every read and write goes through one data-access layer, the module's queries and actions. It takes the signed-in person, and applies the access rules for each table in one place.
- Nothing else holds a database connection. A lint rule keeps it that way.
- Tasks that act for no one say so explicitly, rather than skipping the rules by accident.

## Testing permissions

For each role, test against a real database, signed in as that role: what it can read, what it can change, and that it can't read or change anything else. A new table's test covers each operation. A test signed in with full access proves nothing about permissions.

## Paging by a unique key

Sort by something unique and stable, such as the id, or a timestamp with the id after it. Ask for the rows after the last key seen, and stop when a page comes back short. An offset skips or repeats rows when others insert or delete between pages.

Totals count every row. Do them in the database where you can, and where you can't, page through every row first. Never total the first page.

## All or nothing

A save that changes several rows runs in one transaction, or one database function that does the same. If any part fails, none of it lands, and the person sees the error.
