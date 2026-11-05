#!/bin/sh
# shellcheck disable=SC2016 # Dollars and backticks in quotes are the splitter's input.
#
# Tests the command splitter. Hook rules read its lines to decide what a command runs,
# so text that only mentions a command must stay inside the command that holds it.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

splitter="$ROOT/plugins/dev-workflow/scripts/lib/split-command.awk"

# expect <input> <line>...: the splitter prints exactly these lines, in this order.
expect() {
  _input=$1
  shift
  _expected=$(printf '%s\n' "$@")
  _actual=$(printf '%s\n' "$_input" | awk -f "$splitter") || _assert_fail "the splitter failed on: $_input"
  [ "$_actual" = "$_expected" ] || _assert_fail "for input:
$_input
expected:
$_expected
got:
$_actual"
}

nl='
'
tab=$(printf '\t')

# --- Operators

expect 'a && b' 'a' 'b'
expect 'a; b | c' 'a' 'b' 'c'
expect 'a || b' 'a' 'b'
expect 'a |& b' 'a' 'b'
expect 'a & b' 'a' 'b'
expect 'a &' 'a'
expect "a${nl}b" 'a' 'b'
expect 'a;b&&c||d|e' 'a' 'b' 'c' 'd' 'e'
expect ''
expect '  ;  '
expect '  a --flag   value  ' 'a --flag   value'

# Operators that are part of a redirection don't split.
expect 'npm test 2>&1 | tee out' 'npm test 2>&1' 'tee out'
expect 'a >&2; b' 'a >&2' 'b'
expect 'a <&3 && b' 'a <&3' 'b'
expect 'a &>out; b' 'a &>out' 'b'
expect 'a >|out; b' 'a >|out' 'b'

# --- Quotes keep text literal and stay in the output

expect 'git commit -m "x && y"' 'git commit -m "x && y"'
expect "git commit -m 'gh pr merge'" "git commit -m 'gh pr merge'"
expect "echo 'a; b' \"c | d\" && e" "echo 'a; b' \"c | d\"" 'e'
expect "echo \"it's\" && e" "echo \"it's\"" 'e'
expect "echo 'say \"hi' && e" "echo 'say \"hi'" 'e'
expect 'echo "a\"; b" && e' 'echo "a\"; b"' 'e'
expect "echo 'a\\' && e" "echo 'a\\'" 'e'
expect "echo \$'it\\'s; x' && e" "echo \$'it\\'s; x'" 'e'
expect 'echo "a"b"c;d"' 'echo "a"b"c;d"'

# Backslashes
expect 'find . -exec rm {} \; && e' 'find . -exec rm {} \;' 'e'
expect 'echo a\&\&b' 'echo a\&\&b'
expect 'echo \" && e' 'echo \"' 'e'
expect "a \\${nl}  --flag && b" 'a   --flag' 'b'

# A newline inside quotes doesn't end the command. To keep one command to one line it
# comes out as the byte 037, which readers turn back with tr '\037' '\n'.
sep=$(printf '\037')
expect "git commit -m \"a${nl}${nl}gh pr merge 1\"" "git commit -m \"a${sep}${sep}gh pr merge 1\""
expect "git commit -m 'a${nl}gh pr merge 1' && b" "git commit -m 'a${sep}gh pr merge 1'" 'b'

# --- Leading assignments

expect 'A=1 B=2 npm test' 'npm test'
expect 'A="x y" B='"'"'z && w'"'"' C= npm test' 'npm test'
expect 'A=1 && b' 'b'
expect 'A=1'
expect 'a_B9=1 npm test' 'npm test'
expect 'A+=1 npm test' 'npm test'
expect 'A=(1 2) npm test' 'npm test'

# Only leading ones, and only real ones.
expect 'npm test A=1' 'npm test A=1'
expect '"A=1" b' '"A=1" b'
expect '1A=1 b' '1A=1 b'
expect '=1 b' '=1 b'
expect 'a; B=1 c' 'a' 'c'

# --- Substitutions run, in the order the shell runs them, whatever is around them

expect 'echo $(npm test)' 'npm test' 'echo $(npm test)'
expect 'echo "$(npm test)"' 'npm test' 'echo "$(npm test)"'
expect 'echo "x $(a; b) y" && c' 'a' 'b' 'echo "x $(a; b) y"' 'c'
expect 'echo $(a $(b))' 'b' 'a $(b)' 'echo $(a $(b))'
expect 'echo "$(a "$(b)")"' 'b' 'a "$(b)"' 'echo "$(a "$(b)")"'
expect 'A=$(npm test) gh pr merge' 'npm test' 'gh pr merge'
expect 'A=$(npm test)' 'npm test'
expect 'echo $(A=1 b)' 'b' 'echo $(A=1 b)'
expect 'echo $(a) | b' 'a' 'echo $(a)' 'b'
expect 'echo ${x:-$(a)}' 'a' 'echo ${x:-$(a)}'
expect 'cat <(a; b)' 'a' 'b' 'cat <(a; b)'
expect 'tee >(a) && b' 'a' 'tee >(a)' 'b'

# Text in single quotes doesn't run, nor does an escaped dollar.
expect "echo '\$(a)'" "echo '\$(a)'"
expect 'echo "\$(a)"' 'echo "\$(a)"'
expect 'echo \$\(a\)' 'echo \$\(a\)'
expect "echo \"'\$(a)'\"" 'a' "echo \"'\$(a)'\""

# Backticks count the same.
expect 'echo `a`' 'a' 'echo `a`'
expect 'echo `a; b`' 'a' 'b' 'echo `a; b`'
expect 'echo "`a && b`" && c' 'a' 'b' 'echo "`a && b`"' 'c'
expect 'echo `a \`b\``' 'b' 'a `b`' 'echo `a \`b\``'
expect "echo '\`a\`'" "echo '\`a\`'"
expect 'echo \`a\`' 'echo \`a\`'
expect 'echo "\`a\`"' 'echo "\`a\`"'
expect 'echo `A=1 b "c; d"`' 'b "c; d"' 'echo `A=1 b "c; d"`'
expect 'echo "`a \"b; c\"`"' 'a "b; c"' 'echo "`a \"b; c\"`"'
expect "cat <<EOF \`a\`${nl}body${nl}EOF${nl}b" 'a' 'cat <<EOF `a`' 'b'

# Arithmetic and parameter expansions hold no commands of their own.
expect 'echo $((1 + 2)) && b' 'echo $((1 + 2))' 'b'
expect 'echo $((a && b))' 'echo $((a && b))'
expect 'echo $(((1 + 2) * 3))' 'echo $(((1 + 2) * 3))'
expect 'echo $(( 1 << 2 )) && b' 'echo $(( 1 << 2 ))' 'b'
expect 'echo $(( $(a) + 1 ))' 'a' 'echo $(( $(a) + 1 ))'
expect 'echo $(( `a` + 1 ))' 'a' 'echo $(( `a` + 1 ))'
expect 'echo $((a) && (b))' 'a' 'b' 'echo $((a) && (b))'
expect 'echo ${x:-a && b} && c' 'echo ${x:-a && b}' 'c'
expect 'echo ${#x} $# && c' 'echo ${#x} $#' 'c'
expect 'echo "${x:-a;b}"' 'echo "${x:-a;b}"'
expect "echo \"\${x:-it's}\" && c" "echo \"\${x:-it's}\"" 'c'

# --- Grouping splits into the commands inside

expect '( a; b )' 'a' 'b'
expect '(a && b) | c' 'a' 'b' 'c'
expect '( a ) > out && b' 'a' 'b'
expect '( a; ( b; c ) )' 'a' 'b' 'c'
expect '{ a; b; }' 'a' 'b'
expect '{ a && b; } | c' 'a' 'b' 'c'
expect '{ a; } > out; c' 'a' 'c'
expect "{${nl}a${nl}b${nl}}" 'a' 'b'
expect 'x=1 ( a )' 'a'

# Only as words where a command starts.
expect 'echo {} }' 'echo {} }'
expect 'echo {a,b}' 'echo {a,b}'
expect 'echo "(a; b)"' 'echo "(a; b)"'

# Compound commands come down to the commands they run.
expect 'if a; then b; elif c; then d; else e; fi' 'a' 'b' 'c' 'd' 'e'
expect 'while a; do b; done < in' 'a' 'b'
expect 'until a; do b; done' 'a' 'b'
expect 'for x in 1 2; do a; done' 'a'
expect 'for x in $(a); do b; done | c' 'a' 'b' 'c'
expect "if a${nl}then${nl}  b${nl}fi" 'a' 'b'
expect '! a && b' 'a' 'b'
expect 'case $x in y) a;; z) b;; esac' 'a' 'z' 'b'
expect 'echo if then done fi' 'echo if then done fi'
expect 'git commit -m done' 'git commit -m done'

# A real command directly after a closer or a loop header isn't hidden by it.
expect 'if (npm test) then gh pr merge 1; fi' 'npm test' 'gh pr merge 1'
expect 'if { npm test; } then gh pr merge 1; fi' 'npm test' 'gh pr merge 1'
expect 'while (a) do gh pr merge 1; done' 'a' 'gh pr merge 1'
expect 'if a; then (b) else gh pr merge 1; fi' 'a' 'b' 'gh pr merge 1'
expect 'if a; then { b; } else gh pr merge 1; fi' 'a' 'b' 'gh pr merge 1'
expect 'case $x in (a) gh pr merge 1;; esac' 'gh pr merge 1'
expect 'case $x in (a | b) gh pr merge 1;; esac && c' 'gh pr merge 1' 'c'
expect 'for x do gh pr merge 1; done' 'gh pr merge 1'
expect 'for ((i=0;i<1;i++)) do gh pr merge 1; done' 'gh pr merge 1'
expect 'for ((i=0;i<1;i++)); do gh pr merge 1; done' 'gh pr merge 1'
expect 'select x do gh pr merge 1; done' 'gh pr merge 1'
expect "for x${nl}do gh pr merge 1; done" 'gh pr merge 1'
expect '( a ) b' 'a' 'b'
expect 'echo $(for x do a; done) b' 'a' 'echo $(for x do a; done) b'
expect 'for x in $(if (a) then b; fi) c; do d; done' 'a' 'b' 'd'

# Only redirections are dropped after a closer, with a target apart or attached.
expect '( a ) 2>&1 > out | b' 'a' 'b'
expect '{ a; } 2> err >> out && b' 'a' 'b'
expect 'if a; then b; fi >&2; c' 'a' 'b' 'c'
expect 'for x in 1; do a; done < <(b) && c' 'a' 'b' 'c'
expect "( a ) <<EOF${nl}gh pr merge${nl}EOF${nl}b" 'a' 'b'
expect 'while (a) > out do b; done' 'a' 'b'

# A reserved word directly before a parenthesis is still that word.
expect 'if(npm test);then gh pr merge 1;fi' 'npm test' 'gh pr merge 1'
expect 'if a;then(b);else(c);fi' 'a' 'b' 'c'
expect 'while(a)do gh pr merge 1;done' 'a' 'gh pr merge 1'
expect 'for((i=0;i<1;i++))do gh pr merge 1;done' 'gh pr merge 1'
expect '!(a) && b' 'a' 'b'
expect '{(a);}' 'a'
expect 'time(a)' 'a'
expect 'iffy(a) && b' 'iffy(a)' 'b'
expect '"if"(a) && b' '"if"(a)' 'b'

# time is a keyword like !, with the one option it has.
expect 'time npm test && gh pr merge 1' 'npm test' 'gh pr merge 1'
expect 'time -p npm test' 'npm test'
expect 'A=1 time a' 'a'
expect '! time a' 'a'
expect 'echo time -p' 'echo time -p'

# --- Comments

expect 'a # b && c' 'a'
expect '# only a comment'
expect "a${nl}# b && c${nl}d" 'a' 'd'
expect "a # it's${nl}b" 'a' 'b'
expect 'echo a#b && c' 'echo a#b' 'c'
expect 'echo "# a" && c' 'echo "# a"' 'c'
expect "echo '# a' && c" "echo '# a'" 'c'
expect 'echo \# a && c' 'echo \# a' 'c'
expect "echo \$(a # b)${nl}) && c" 'a' "echo \$(a # b)${sep})" 'c'

# --- Heredocs

expect "cat <<EOF${nl}gh pr merge${nl}EOF${nl}&& b" 'cat <<EOF' 'b'
expect "cat <<EOF && b${nl}gh pr merge${nl}EOF" 'cat <<EOF' 'b'
expect "cat <<EOF${nl}gh pr merge${nl}EOF${nl}b" 'cat <<EOF' 'b'
expect "cat <<EOF | a; b${nl}body${nl}EOF${nl}c" 'cat <<EOF' 'a' 'b' 'c'

# Every way to write the delimiter.
expect "cat <<'EOF'${nl}gh pr merge${nl}EOF${nl}b" "cat <<'EOF'" 'b'
expect "cat <<\"EOF\"${nl}gh pr merge${nl}EOF${nl}b" 'cat <<"EOF"' 'b'
expect "cat <<\\EOF${nl}gh pr merge${nl}EOF${nl}b" 'cat <<\EOF' 'b'
expect "cat <<E'O'F${nl}gh pr merge${nl}EOF${nl}b" "cat <<E'O'F" 'b'
expect "cat << EOF${nl}gh pr merge${nl}EOF${nl}b" 'cat << EOF' 'b'
expect "cat <<'A B'${nl}gh pr merge${nl}A B${nl}b" "cat <<'A B'" 'b'
expect "cat <<EOF>out${nl}gh pr merge${nl}EOF${nl}b" 'cat <<EOF>out' 'b'

# <<- ends on a delimiter after tabs; << doesn't.
expect "cat <<-EOF${nl}${tab}gh pr merge${nl}${tab}${tab}EOF${nl}b" 'cat <<-EOF' 'b'
expect "cat <<-'EOF'${nl}${tab}gh pr merge${nl}${tab}EOF${nl}b" "cat <<-'EOF'" 'b'
expect "cat <<EOF${nl}${tab}EOF${nl}gh pr merge${nl}EOF${nl}b" 'cat <<EOF' 'b'
expect "cat <<EOF${nl}EOF2${nl} EOF${nl}gh pr merge${nl}EOF${nl}b" 'cat <<EOF' 'b'

# Nothing in the body counts, quotes included. Two in a row each get their body.
expect "cat <<EOF${nl}it's \$(a) \`b\` \"${nl}EOF${nl}c" 'cat <<EOF' 'c'
expect "cat <<A <<B${nl}one${nl}A${nl}two${nl}B${nl}c" 'cat <<A <<B' 'c'
expect "cat <<A; cat <<B${nl}one${nl}A${nl}two${nl}B${nl}c" 'cat <<A' 'cat <<B' 'c'
expect "cat <<EOF${nl}gh pr merge" 'cat <<EOF'

# Not heredocs.
expect 'cat <<< "a && b" && c' 'cat <<< "a && b"' 'c'
expect 'echo "<<EOF"' 'echo "<<EOF"'
expect "echo '<<EOF'${nl}b" "echo '<<EOF'" 'b'
expect "echo \\<\\<EOF${nl}b" 'echo \<\<EOF' 'b'
expect "# <<EOF${nl}b" 'b'

# Inside a substitution: the way multi-line messages are usually passed. The outer
# command keeps its whole text, for rules that read the message.
expect "git commit -m \"\$(cat <<'EOF'${nl}feat: x${nl}${nl}gh pr merge 1${nl}EOF${nl})\" && b" \
  "cat <<'EOF'" \
  "git commit -m \"\$(cat <<'EOF'${sep}feat: x${sep}${sep}gh pr merge 1${sep}EOF${sep})\"" \
  'b'
expect "echo \$(cat <<EOF${nl}gh pr merge${nl}EOF${nl}) && b" \
  'cat <<EOF' \
  "echo \$(cat <<EOF${sep}gh pr merge${sep}EOF${sep})" \
  'b'
expect "echo \"\$(cat <<EOF${nl}gh pr merge${nl}EOF)\" && b" \
  'cat <<EOF' \
  "echo \"\$(cat <<EOF${sep}gh pr merge${sep}EOF)\"" \
  'b'
expect "( cat <<EOF${nl}gh pr merge${nl}EOF${nl}) && b" 'cat <<EOF' 'b'

# --- Word mode: with WORD_END set, each word ends with it instead of keeping its spaces

# expect_words <input> <line>...: as expect, with | ending each word.
expect_words() {
  _input=$1
  shift
  _expected=$(printf '%s\n' "$@")
  _actual=$(printf '%s\n' "$_input" | awk -v 'WORD_END=|' -f "$splitter") || _assert_fail "the splitter failed on: $_input"
  [ "$_actual" = "$_expected" ] || _assert_fail "for input:
$_input
expected:
$_expected
got:
$_actual"
}

expect_words "a  b${tab}c" 'a|b|c|'
expect_words "A=1 a \"b c\" 'd e'" "a|\"b c\"|'d e'|"
expect_words 'gh pr merge --body "" && x' 'gh|pr|merge|--body|""|' 'x|'
expect_words 'if (a b); then c; fi' 'a|b|' 'c|'
expect_words 'a $(b c) d' 'b|c|' 'a|$(b c)|d|'
expect_words 'a "$(b "c d")" e' 'b|"c d"|' 'a|"$(b "c d")"|e|'
expect_words 'a 2>&1 b' 'a|2>&1|b|'
expect_words "a <<EOF${nl}it's${nl}EOF${nl}b c" 'a|<<EOF|' 'b|c|'
