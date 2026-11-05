#!/bin/sh
# shellcheck disable=SC2016 # Dollars and backticks in quotes are commands for the hook.
#
# Tests the Bash rules on gh commands: how a pull request merges, titles and closing
# keywords, and attribution in whatever text reaches GitHub.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
# shellcheck source=tests/lib/hook.sh
. "$ROOT/tests/lib/hook.sh"
# shellcheck source=tests/lib/bash-rules.sh
. "$ROOT/tests/lib/bash-rules.sh"

# --- gh pr merge flags

rule deny 'gh pr merge 1 --squash' '--body'
rule deny 'gh pr merge 1 --merge --body ""' '--squash'
rule deny 'gh pr merge 1 --rebase --body ""'
rule deny 'gh pr merge 1 --squash --merge --body ""'
rule deny 'gh pr merge 1 --body ""'
rule deny 'gh pr merge 1 --squash --body "text"'
rule deny 'gh pr merge 1 --squash --body-file b.md'
rule deny 'gh pr merge 1 --squash --subject "--body"'
rule deny 'gh pr merge 1 --subject "--squash" --body ""'
rule deny 'gh pr merge'
rule none 'gh pr merge 1 --squash --body ""'
rule none "gh pr merge 1 --squash --body ''"
rule none 'gh pr merge 1 --squash --body=""'
rule none 'gh pr merge 1 --squash --body='
rule none 'gh pr merge 1 --squash --subject "--merge" --body "" --delete-branch'
rule none 'gh pr merge 1 -s -b ""'
rule none 'gh pr merge 1 -sd -b ""'
rule none 'gh pr merge 1 --squash --body "" 2>&1'
rule none 'gh pr merge 1 --disable-auto'
rule none 'gh pr merge --help'
rule none 'gh pr view 1'
rule none 'gh pr list --search "gh pr merge"'
rule none 'echo "gh pr merge 1"'
rule none 'grep "gh pr merge" notes.md'
rule none 'gh pr comment 1 --body "explains gh pr merge"'

# A subject becomes a commit that no git hook sees.
rule deny 'gh pr merge 1 --squash --subject "Generated with Claude Code" --body ""' 'attribution'

# --- Pull request titles and closing keywords

rule deny 'gh pr create --title "add stuff" --body "Closes #1"' 'title'
rule deny 'gh pr create --title "feat: x" --body "no keyword"' 'closing keyword'
rule none 'gh pr create --title "feat: x" --body "Closes #1"'
rule deny 'gh pr create --title "feat: x" --body "Closes #1\n\nGenerated with Claude Code"' 'attribution'

for title in \
  'feat(api)!: add thing' \
  'fix(scope): y (#12)' \
  'chore: z'; do
  rule none "gh pr create --title \"$title\" --body \"Closes #1\""
done
for title in \
  'Merge branch x' \
  'nonsense: y' \
  'feat:' \
  'feat: ' \
  'fixup! feat: x' \
  ''; do
  rule deny "gh pr create --title \"$title\" --body \"Closes #1\"" 'title'
done
rule deny 'gh pr create --body "Closes #1"' 'title'
rule deny 'gh pr create --title "feat: x"' 'closing keyword'
rule deny 'gh pr create' 'title'
rule deny 'gh pr create --title "Oops
feat: x" --body "Closes #1"' 'title'

# Every way of writing the flags.
rule none 'gh pr create -t "feat: x" -b "Closes #1"'
rule none 'gh pr create -t"feat: x" -b"Closes #1"'
rule none 'gh pr create --title="feat: x" --body="Closes #1"'
rule none 'gh pr create -dt "feat: x" -b "Closes #1"'
rule none "gh pr create --title 'feat: x' --body 'Closes #1'"
rule none 'gh pr create --title "feat: x" --body $'"'"'Why.\n\nCloses #1'"'"
rule none 'gh pr create --title "feat: x" --body "Why.\n\nCloses #1"'
rule none 'gh pr create --title "feat: x" --body "Why.

Closes #1"'
rule deny 'gh pr create -t "add stuff" -b "Closes #1"' 'title'
rule deny 'gh pr create --label "--title" --title "add stuff" --body "Closes #1"' 'title'
rule deny 'gh pr create --title "feat: x" --body "--title"' 'closing keyword'

# GitHub's closing keywords, in any case, and what isn't one.
for keyword in \
  'closes #1' 'Close #1' 'Closed #1' 'FIXES #1' 'Fix #1' 'fixed #1' \
  'Resolves #12' 'resolve #1' 'resolved #1' 'Closes: #1' 'Closes o/r#1'; do
  rule none "gh pr create --title \"feat: x\" --body \"Why.
$keyword\""
done
for no_keyword in \
  'Closes' 'Closes #' 'Closes #x' 'See #1' 'discloses #1' 'prefix #1'; do
  rule deny "gh pr create --title \"feat: x\" --body \"$no_keyword\"" 'closing keyword'
done

# --fill takes the body from the commits, where the keyword can't be checked.
rule deny 'gh pr create --fill' '--body'
rule deny 'gh pr create -f' '--body'
rule deny 'gh pr create --fill-first' '--body'
rule deny 'gh pr create --fill-verbose' '--body'
rule deny 'gh pr create --title "feat: x" --fill' '--body'

# gh pr edit checks what's there.
rule none 'gh pr edit 1 --add-label bug'
rule none 'gh pr edit 1 --title "feat: x"'
rule none 'gh pr edit 1 --body "Closes #1"'
rule deny 'gh pr edit 1 --title "add stuff"' 'title'
rule deny 'gh pr edit 1 -t "add stuff"' 'title'
rule deny 'gh pr edit 1 --body "no keyword"' 'closing keyword'
rule deny 'gh pr edit 1 --title "feat: x" --body "no keyword"' 'closing keyword'
rule deny 'gh pr edit 1 --body "Closes #1

Generated with Claude Code"' 'attribution'
rule deny 'gh pr edit 1 --title "Generated with Claude Code"' 'attribution'

# --- Attribution

for line in \
  'Generated with Claude Code' \
  'Co-Authored-By: Claude <noreply@anthropic.com>' \
  '**Co-Authored-By:** Claude' \
  '**Co-Authored-By:** Claude <noreply@anthropic.com>' \
  'Assisted-by: Claude'; do
  rule deny "gh pr comment 1 --body \"Why.

$line\"" 'attribution'
done

for command in \
  'gh pr create --title "feat: x" --body' \
  'gh pr edit 1 --body' \
  'gh pr comment 1 -b' \
  'gh issue create --title x --body' \
  'gh issue edit 1 --body' \
  'gh issue comment 1 --body' \
  'gh release create v1 --notes' \
  'gh release create v1 -n' \
  'gh release edit v1 --notes'; do
  rule deny "$command \"Closes #1

Assisted-by: Claude\"" 'attribution'
done

rule deny 'gh issue create --title x --body "Generated with Claude Code"' 'attribution'
rule deny 'gh issue create --title "Generated with Claude Code" --body x' 'attribution'
rule deny 'gh issue edit 1 --title "Generated with Claude Code"' 'attribution'
rule deny 'gh release create v1 --title "Generated with Claude Code"' 'attribution'
rule deny 'gh release edit v1 -t "Generated with Claude Code"' 'attribution'
rule deny 'gh pr comment 1 --body "Closes #1\n\nAssisted-by: Claude"' 'attribution'
rule deny 'gh pr comment 1 --body=$'"'"'x\n\nCo-Authored-By: Claude'"'" 'attribution'

# Ordinary mentions pass, and these commands don't need a title or a keyword.
rule none 'gh pr comment 1 --body "The hook reads the Claude Code input."'
rule none 'gh pr comment 1 --body "The **Co-Authored-By:** form is rejected."'
rule none 'gh pr comment 1 --body "**Co-Authored-By:** Ana Ruiz"'
rule none 'gh issue create --title x --body "Clean text about Claude."'
rule none 'gh issue edit 1 --add-label bug'
rule none 'gh issue comment 1 --body "Assisted by a person."'
rule none 'gh release create v1 --title "v1" --notes "Clean"'
rule none 'gh release create v1 --generate-notes'
rule none 'gh release edit v1 --draft=false'
rule none 'gh pr view 1 --json body'
rule none 'gh pr list | grep "Generated with Claude Code"'
rule none 'gh pr comment --help'
rule none 'gh pr create --help'

# A heredoc in the body: the text between its lines is what counts.
rule_stdin none <<'COMMAND'
gh pr create --title "feat: x" --body "$(cat <<'EOF'
It's a body with "quotes" and an unmatched ( parenthesis.

Closes #1
EOF
)"
COMMAND

rule_stdin deny 'attribution' <<'COMMAND'
gh pr create --title "feat: x" --body "$(cat <<'EOF'
It's a body.

Closes #1

**Co-Authored-By:** Claude
EOF
)"
COMMAND

rule_stdin deny 'closing keyword' <<'COMMAND'
gh pr create --title "feat: x" --body "$(cat <<'EOF'
It's a body.
EOF
)"
COMMAND

# A plain heredoc appears in no simple command, so it comes from the raw text.
rule_stdin deny 'attribution' <<'COMMAND'
gh pr comment 1 --body-file - <<'EOF'
Text.

Generated with Claude Code
EOF
COMMAND

rule_stdin none <<'COMMAND'
gh pr create --title "feat: x" --body-file - <<'EOF'
Text.

Closes #1
EOF
COMMAND

rule_stdin deny 'closing keyword' <<'COMMAND'
gh pr create --title "feat: x" -F - <<'EOF'
Text.
EOF
COMMAND

# A variable holding the text is in the raw command too.
rule_stdin deny 'attribution' <<'COMMAND'
BODY='Text.

Co-Authored-By: Claude'
gh pr comment 1 --body "$BODY"
COMMAND

# Standard input the hook can't see.
rule deny 'cat b.md | gh pr comment 1 --body-file -' 'read'
rule deny 'cat b.md | gh pr create --title "feat: x" -F -' 'read'

# The same text that isn't going anywhere is no business of this rule.
rule none 'git log --grep="Generated with Claude Code"'
rule none 'gh pr view 1
grep "Generated with Claude Code" notes.md'

# --- Closing and reviewing, whose text GitHub shows like any comment

for command in \
  'gh pr review 1 --body' \
  'gh pr review 1 -b' \
  'gh pr review 1 --comment --body' \
  'gh pr review 1 -c -b' \
  'gh pr review 1 --approve --body' \
  'gh pr review 1 --request-changes -b' \
  'gh pr close 1 --comment' \
  'gh pr close 1 -c' \
  'gh pr close -d 1 -c' \
  'gh issue close 1 --comment' \
  'gh issue close 1 -c' \
  'gh issue close 1 --reason completed -c'; do
  rule deny "$command \"Co-Authored-By: Claude\"" 'attribution'
done
rule none 'gh pr review 1 --comment --body "Clean text about Claude."'
rule none 'gh pr close 1 -c "Clean text about Claude."'
rule none 'gh issue close 1 --comment "Clean text about Claude."'
rule deny 'gh pr review 1 --body="Co-Authored-By: Claude"' 'attribution'
rule deny 'gh pr review 1 -b"Co-Authored-By: Claude"' 'attribution'
rule deny 'gh pr close 1 --comment="Co-Authored-By: Claude"' 'attribution'
rule deny 'gh pr close 1 -c"Co-Authored-By: Claude"' 'attribution'
rule deny 'gh issue close 1 --comment "Why.\n\nGenerated with Claude Code"' 'attribution'
rule none 'gh pr review 1 --approve'
rule none 'gh pr review 1 --comment --body "--body"'
rule none 'gh pr close 1'
rule none 'gh pr close 1 --delete-branch'
rule none 'gh issue close 1 --reason "not planned"'
rule none 'gh pr close --help'
rule none 'gh issue close --help'
rule none 'gh pr review --help'

# --- gh api, when it writes

for flag in '-f' '--raw-field' '-F' '--field'; do
  rule deny "gh api repos/o/r/issues/1/comments $flag body='Co-Authored-By: Claude'" 'attribution'
  rule deny "gh api repos/o/r/issues/1/comments $flag \"body=Why.\n\nGenerated with Claude Code\"" 'attribution'
  rule deny "gh api -X PATCH repos/o/r/pulls/1 $flag 'body=Assisted-by: Claude'" 'attribution'
  rule none "gh api repos/o/r/issues/1/comments $flag 'body=Clean text about Claude.'"
done
rule deny 'gh api repos/o/r/pulls/1 --raw-field=body="Co-Authored-By: Claude"' 'attribution'
rule deny 'gh api repos/o/r/pulls/1 -f"body=Co-Authored-By: Claude"' 'attribution'
rule deny 'gh api -f "body=Co-Authored-By: Claude" repos/o/r/pulls/1' 'attribution'
rule deny 'gh -R o/r api repos/o/r/pulls/1 -f "body=Co-Authored-By: Claude"' 'attribution'
rule deny "gh api graphql -f query='mutation { addComment(input: {body: \"Co-Authored-By: Claude\"}) { clientMutationId } }'" 'attribution'

# It's a read without fields, and with GET named. Text it's only searching for is fine.
rule none 'gh api repos/o/r/pulls/1'
rule none 'gh api --paginate repos/o/r/issues --jq ".[].body"'
rule none 'gh api -X GET search/issues -f "q=Co-Authored-By: Claude"'
rule none 'gh api --method get search/issues -f "q=Co-Authored-By: Claude"'
rule none 'gh api --method=HEAD search/issues -F "q=Co-Authored-By: Claude"'
rule none 'gh api -XGET search/issues -f "q=Co-Authored-By: Claude"'
rule none 'gh api -X GET search/issues -F q=@gone.md --input gone.md'
rule none 'gh api repos/o/r/pulls/1 --jq "Co-Authored-By: Claude"'
rule none 'gh api repos/o/r/pulls/1 -H "X: Co-Authored-By: Claude"'
rule none 'gh api repos/o/r/pulls/1 -q ".a" -t "{{.x}}" -p preview --cache 1h --hostname x.example'
rule none 'gh api --help'
# Named methods that write, with or without fields.
rule deny 'gh api -X POST repos/o/r/issues -f "body=Co-Authored-By: Claude"' 'attribution'
rule deny 'gh api -XPUT repos/o/r/issues -f "body=Co-Authored-By: Claude"' 'attribution'
rule deny 'gh api --method delete repos/o/r/x -f "body=Co-Authored-By: Claude"' 'attribution'
rule deny 'gh api --method "$METHOD" repos/o/r/x -f "body=Co-Authored-By: Claude"' 'attribution'
rule none 'gh api -X DELETE repos/o/r/issues/comments/1'
rule none 'gh api -X PUT repos/o/r/subscription -F subscribed=true -F ignored=false'

# Text from a file or a heredoc.
printf '{"body": "Why.\\n\\nCo-Authored-By: Claude"}\n' >"$repo/api-attributed.json"
printf '{"body":"Co-Authored-By: Claude"}\n' >"$repo/api-first.json"
printf '{"body": "Clean"}\n' >"$repo/api-clean.json"
printf 'Assisted-by: Claude\n' >"$repo/api-value.md"
rule deny 'gh api repos/o/r/issues --input api-attributed.json' 'attribution'
rule deny 'gh api repos/o/r/issues --input api-first.json' 'attribution'
rule deny 'gh api repos/o/r/issues --input=api-first.json' 'attribution'
rule none 'gh api repos/o/r/issues --input api-clean.json'
rule deny 'gh api repos/o/r/issues -F body=@api-value.md' 'attribution'
rule deny 'gh api repos/o/r/issues --field=body=@api-value.md' 'attribution'
rule none 'gh api repos/o/r/issues -f body=@api-value.md'
rule none 'gh api repos/o/r/issues -F body=@api-clean.json'
rule deny 'gh api repos/o/r/issues --input gone.json' 'read'
rule deny 'gh api repos/o/r/issues -F body=@gone.md' 'read'
rule deny 'cat b.json | gh api repos/o/r/issues --input -' 'read'
rule deny 'cat b.md | gh api repos/o/r/issues -F body=@-' 'read'
rule_stdin deny 'attribution' <<'COMMAND'
gh api repos/o/r/issues --input - <<'EOF'
{"body":"Co-Authored-By: Claude"}
EOF
COMMAND
rule_stdin deny 'attribution' <<'COMMAND'
gh api repos/o/r/issues -F body=@- <<'EOF'
Generated with Claude Code
EOF
COMMAND
rule_stdin none <<'COMMAND'
gh api repos/o/r/issues --input - <<'EOF'
{"body":"Clean text about Claude."}
EOF
COMMAND
# A variable holding the text is in the raw command too.
rule_stdin deny 'attribution' <<'COMMAND'
BODY='Text.

Co-Authored-By: Claude'
gh api repos/o/r/issues -f body="$BODY"
COMMAND

# --- Body files

printf 'Why.\n\nCloses #1\n' >"$repo/clean.md"
printf 'Closes #1\n\nGenerated with Claude Code\n' >"$repo/attributed.md"
printf 'Generated with Claude Code\n' >"$repo/only-attributed.md"
printf 'Closes #1\n\n**Co-Authored-By:** Claude\n' >"$repo/marked.md"
printf 'Why.\n' >"$repo/no-keyword.md"
printf 'Closes #1\n' >"$repo/name with space.md"
printf 'Closes #1\n' >"$repo/sub/clean.md"
outside="$(tmp_dir)/outside.md"
printf 'Closes #1\n' >"$outside"

rule none 'gh pr create --title "feat: x" --body-file clean.md'
rule none 'gh pr create --title "feat: x" -F clean.md'
rule none 'gh pr create --title "feat: x" -Fclean.md'
rule none 'gh pr create --title "feat: x" --body-file=clean.md'
rule none 'gh pr create --title "feat: x" --body-file "name with space.md"'
rule none "gh pr create --title \"feat: x\" --body-file \"$outside\""
real_home=$HOME
HOME=$repo
rule none 'gh pr create --title "feat: x" --body-file ~/clean.md'
HOME=$real_home
rule deny 'gh pr create --title "feat: x" --body-file attributed.md' 'attribution'
rule deny 'gh pr create --title "feat: x" --body-file only-attributed.md' 'attribution'
rule deny 'gh pr create --title "feat: x" -F marked.md' 'attribution'
rule deny 'gh pr create --title "feat: x" --body-file no-keyword.md' 'closing keyword'
rule deny 'gh pr edit 1 --body-file no-keyword.md' 'closing keyword'
rule deny 'gh pr edit 1 --body-file attributed.md' 'attribution'
rule deny 'gh pr comment 1 --body-file attributed.md' 'attribution'
rule deny 'gh issue create --title x -F attributed.md' 'attribution'
rule deny 'gh issue edit 1 -F attributed.md' 'attribution'
rule deny 'gh issue comment 1 -F attributed.md' 'attribution'
rule deny 'gh release create v1 --notes-file attributed.md' 'attribution'
rule deny 'gh release create v1 -F attributed.md' 'attribution'
rule deny 'gh release edit v1 --notes-file attributed.md' 'attribution'
rule none 'gh pr comment 1 --body-file no-keyword.md'
rule none 'gh release create v1 --notes-file no-keyword.md'

# A file that can't be read can't be checked.
for unreadable in gone.md sub '$(mktemp)' '<(echo x)' /dev/stdin; do
  rule deny "gh pr comment 1 --body-file $unreadable" 'read'
done
rule deny 'gh pr create --title "feat: x" --body-file gone.md' 'read'

# A relative name is from where the session's shell is.
cd "$repo/sub" || exit 1
rule none 'gh pr create --title "feat: x" --body-file clean.md'
rule deny 'gh pr create --title "feat: x" --body-file attributed.md' 'read'
cd "$repo" || exit 1

# Without a usable cwd in the input, from the project's root.
no_cwd=$(jq -n '{tool_name: "Bash", tool_input: {command: "gh pr comment 1 --body-file attributed.md"}}')
assert_decision deny "$hook" "$no_cwd"
assert_contains "$(reason_of "$hook" "$no_cwd")" 'attribution'
