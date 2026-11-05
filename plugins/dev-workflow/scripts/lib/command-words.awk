# Reads split-command.awk's output in word mode, each word ended by the byte 036, and
# prints each simple command as the words it runs, in the same form. Run it with:
#   awk -f split-command.awk -v 'WORD_END=\036' | DW_ROOT=<project> awk -f command-words.awk
#
# So a rule can read `git merge x` however it was written:
# - Quotes are gone. A newline in a word stays the byte 037, and $'...' is decoded too.
#   Text inside a substitution may lose quote characters, which no rule depends on.
# - Redirections are gone, wherever they are, except heredocs and here-strings, whose
#   words start with <<, so a rule can tell that stdin holds text.
# - Leading VAR=value words and the prefixes env, sudo, command, exec and nohup are gone,
#   with their options. `command -v` only asks about a command, so it stays as it is.
# - git and gh lose a path to them and their own options before the subcommand.
# - Any other command loses a leading ./ or path to the project's root, as in
#   ./scripts/check, so that it compares with how the project file names it.
#
# A command with nothing left, like `exec 2>&1`, prints nothing.

BEGIN {
  END_OF_WORD = "\036"
  NEWLINE = "\037"
  ROOT = ENVIRON["DW_ROOT"]
  ENV_VALUE = "^(-[A-Za-z]*[uCSP]|--unset|--chdir|--split-string)$"
  SUDO_VALUE = "^(-[A-Za-z]*[ugUhpCrtTDR]|--(user|group|other-user|host|prompt|close-from|role|type|command-timeout|chdir|chroot))$"
  EXEC_VALUE = "^-[cl]*a$"
  GIT_VALUE = "^(-C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)$"
  GH_VALUE = "^(-R|--repo|--hostname)$"
}

{
  count = split($0, raw, END_OF_WORD)
  n = 0
  for (i = 1; i <= count; i++) {
    # Each word is ended, not separated, so split finds an empty piece after the last.
    if (i == count && raw[i] == "") break
    if (is_redirection(raw[i])) {
      if (raw[i] ~ /^[0-9]*(&>>?|>>?[&|]?|<[&>]?)$/) i++
    } else {
      words[++n] = unquote(raw[i])
    }
  }

  first = after_prefixes(1)
  if (first > n) next

  name = base(words[first])
  if (name == "git") {
    print_command("git", after_git_options(first + 1))
  } else if (name == "gh") {
    print_gh(first + 1)
  } else if (name ~ /^(dropdb|docker|docker-compose)$/) {
    print_command(name, first + 1)
  } else {
    print_command(from_project(words[first]), first + 1)
  }
}

function base(path) {
  sub(/.*\//, "", path)
  return path
}

function from_project(path) {
  sub(/^\.\//, "", path)
  if (ROOT != "" && index(path, ROOT "/") == 1) path = substr(path, length(ROOT) + 2)
  return path
}

# Reads the raw word, so that a quoted ">" is text. << and <( are not redirections here.
function is_redirection(word) {
  if (word ~ /^[0-9]*<</ || word ~ /^[0-9]*[<>]\(/) return 0
  return word ~ /^[0-9]*(&>|[<>])/
}

# The position of the first word after any assignments and prefixes.
function after_prefixes(p,    name) {
  while (p <= n) {
    name = base(words[p])
    if (words[p] ~ /^[A-Za-z_][A-Za-z0-9_]*[+]?=/) p++
    else if (name == "env") p = after_options(p + 1, ENV_VALUE)
    else if (name == "sudo") p = after_options(p + 1, SUDO_VALUE)
    else if (name == "exec") p = after_options(p + 1, EXEC_VALUE)
    else if (name == "nohup") p++
    else if (name == "command" && words[p + 1] !~ /^-p*[vV]/) p = after_options(p + 1, "^$")
    else break
  }
  return p
}

# Steps over a prefix's options. Those matching value_flags use up the next word too.
function after_options(p, value_flags) {
  while (p <= n && words[p] ~ /^-/) {
    if (words[p] == "--") return p + 1
    if (words[p] ~ value_flags) p++
    p++
  }
  return p
}

function after_git_options(p) {
  return after_options(p, GIT_VALUE)
}

function print_command(name, p,    i, line) {
  line = name END_OF_WORD
  for (i = p; i <= n; i++) line = line words[i] END_OF_WORD
  print line
}

# gh takes its flags anywhere, so they're dropped up to the end of the subcommand's name.
function print_gh(p,    found, name_words) {
  name_words = "gh"
  while (p <= n && found < 2) {
    if (words[p] ~ GH_VALUE) {
      p += 2
    } else if (words[p] ~ /^-/) {
      p++
    } else {
      name_words = name_words END_OF_WORD words[p]
      found++
      p++
    }
  }
  print_command(name_words, p)
}

# The word as the command receives it, leaving expansions as they are written.
function unquote(word,    out, i, len, c, next_c, state) {
  out = ""
  len = length(word)
  i = 1
  while (i <= len) {
    c = substr(word, i, 1)
    next_c = substr(word, i + 1, 1)
    if (state == "single") {
      if (c == "'") state = ""
      else out = out c
      i++
    } else if (state == "ansi") {
      if (c == "\\") {
        out = out ansi_escape(next_c)
        i += 2
      } else {
        if (c == "'") state = ""
        else out = out c
        i++
      }
    } else if (state == "double") {
      if (c == "\"") {
        state = ""
        i++
      } else if (c == "\\" && next_c == NEWLINE) {
        i += 2
      } else if (c == "\\" && next_c != "" && index("\\\"$`", next_c)) {
        out = out next_c
        i += 2
      } else {
        out = out c
        i++
      }
    } else if (c == "'") {
      state = "single"
      i++
    } else if (c == "\"") {
      state = "double"
      i++
    } else if (c == "$" && next_c == "'") {
      state = "ansi"
      i += 2
    } else if (c == "$" && next_c == "\"") {
      state = "double"
      i += 2
    } else if (c == "\\") {
      out = out next_c
      i += 2
    } else {
      out = out c
      i++
    }
  }
  return out
}

function ansi_escape(c) {
  if (c == "n") return NEWLINE
  if (c == "t") return "\t"
  if (c == "\\" || c == "'" || c == "\"") return c
  return "\\" c
}
