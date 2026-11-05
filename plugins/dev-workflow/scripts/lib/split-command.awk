# Reads a shell command and prints each simple command in it on its own line, in the
# order the shell runs them: the contents of a substitution come before the command
# holding it. Run it with: awk -f split-command.awk
#
# Each line keeps the command's original text and quotes, without leading VAR=value
# words, so that rules can read its flags and bodies. A newline inside a command, in
# quotes or a substitution, comes out as the byte 037 to keep it on one line. Readers
# who need the text as written turn it back with tr '\037' '\n'.
#
# What splits and what doesn't:
# - &&, ||, ;, |, |&, & and newlines split. 2>&1, &>out and >|out don't.
# - Quoted text is literal. $(...), `...` and <(...) run, also inside double quotes, so
#   their contents come out as commands of their own.
# - Heredoc bodies and comments are skipped. Hence $(...) in an unquoted heredoc's body
#   isn't seen, though the shell runs it.
# - ( a; b ), { a; b; } and compound commands come down to the commands they run. The
#   headers of for, select and case aren't commands, so they don't come out. A case
#   pattern does, as it can't be told apart without following the whole grammar.
#
# This only reads the text of a command, so it catches mistakes rather than stopping
# anyone. It can't see through eval, sh -c, aliases or functions.
#
# POSIX awk only. The input is one string, S, walked by position; functions take a
# position and return the one after what they read.

{
  S = S separator $0
  separator = "\n"
}

END {
  L = length(S)
  commands(1, "")
}

# The list of commands from i up to the closer, or the end of the text. A word being
# built, the command it joins and the rest of the state belong to one list, so they're
# put back on the way out: a list inside a word mustn't disturb that word.
function commands(i, closer,    c, n, saved_cur, saved_word, saved_fresh, saved_drop, saved_base) {
  saved_cur = cur; saved_word = word; saved_fresh = fresh; saved_drop = drop
  saved_base = heredoc_base
  cur = ""; word = ""; fresh = 1; drop = 0
  heredoc_base = heredoc_count

  while (i <= L) {
    c = substr(S, i, 1)
    n = substr(S, i + 1, 1)

    if (c == "#" && word == "") {
      while (i <= L && substr(S, i, 1) != "\n") i++
    } else if (c == " " || c == "\t") {
      end_word()
      if (cur != "") cur = cur c
      i++
    } else if (c == "\\" && n == "\n") {
      i += 2
    } else if (c == "\n") {
      end_command()
      i++
      if (heredoc_count > heredoc_base) i = skip_heredocs(i, closer != "")
    } else if (c == ";") {
      end_command()
      i++
    } else if (c == "&" && (word ~ /[<>]$/ || n == ">")) {
      word = word c
      i++
    } else if (c == "&") {
      end_command()
      i += (n == "&") ? 2 : 1
    } else if (c == "|" && word ~ />$/) {
      word = word c
      i++
    } else if (c == "|") {
      end_command()
      i += (n == "|" || n == "&") ? 2 : 1
    } else if (c == ")") {
      end_command()
      i++
      if (closer == ")") break
    } else if (c == "(" && word ~ /[<>]$/) {
      n = commands(i + 1, ")")
      word = word substr(S, i, n - i)
      i = n
    } else if (c == "(" && word == "" && fresh) {
      i = commands(i + 1, ")")
      drop = 1
    } else if (c == "(") {
      n = balanced(i)
      word = word substr(S, i, n - i)
      i = n
    } else if (c == "<" && n == "<") {
      i = redirect_in(i)
    } else {
      n = element(i, 0)
      word = word substr(S, i, n - i)
      i = n
    }
  }
  end_command()

  cur = saved_cur; word = saved_word; fresh = saved_fresh; drop = saved_drop
  heredoc_count = heredoc_base
  heredoc_base = saved_base
  return i
}

# Finishes the word being built. While no command has started, it may be something
# that isn't part of the command.
function end_word() {
  if (word == "") return
  if (fresh) {
    if (word ~ /^[A-Za-z_][A-Za-z0-9_]*[+]?=/ || word == "if" || word == "then" ||
        word == "elif" || word == "else" || word == "while" || word == "until" ||
        word == "do" || word == "!" || word == "{") {
      word = ""
      return
    }
    # The rest isn't a command: redirections after a closing word, or a loop or case
    # header.
    if (word == "}" || word == "fi" || word == "done" || word == "esac" ||
        word == "for" || word == "select" || word == "case") {
      word = ""
      drop = 1
      return
    }
    fresh = 0
  }
  cur = cur word
  word = ""
}

function end_command() {
  end_word()
  if (!drop) {
    sub(/[ \t]+$/, "", cur)
    if (cur != "") {
      gsub(/\n/, "\037", cur)
      print cur
    }
  }
  cur = ""
  fresh = 1
  drop = 0
}

# One piece of a word at i: a quoted string, an expansion or an escaped character, or
# else a single character. Returns the position after it. In double quotes, a quote
# character means nothing.
function element(i, in_dq,    c, n) {
  c = substr(S, i, 1)
  n = substr(S, i + 1, 1)
  if (c == "\\") return i + 2
  if (c == "`") return backticks(i, in_dq)
  if (c == "$" && n == "(") return dollar_paren(i)
  if (c == "$" && n == "{") return expansion(i + 2, in_dq)
  if (in_dq) return i + 1
  if (c == "$" && n == "'") return ansi_quoted(i + 2)
  if (c == "'") return single_quoted(i + 1)
  if (c == "\"") return double_quoted(i + 1)
  return i + 1
}

function single_quoted(i,    n) {
  n = index(substr(S, i), "'")
  return n ? i + n : L + 1
}

function ansi_quoted(i,    c) {
  while (i <= L) {
    c = substr(S, i, 1)
    if (c == "'") return i + 1
    i += (c == "\\") ? 2 : 1
  }
  return i
}

function double_quoted(i) {
  while (i <= L) {
    if (substr(S, i, 1) == "\"") return i + 1
    i = element(i, 1)
  }
  return i
}

# The inside of ${...}, from i.
function expansion(i, in_dq) {
  while (i <= L) {
    if (substr(S, i, 1) == "}") return i + 1
    i = element(i, in_dq)
  }
  return i
}

# Parentheses inside a word, from the opening one at i, as in A=(1 2).
function balanced(i,    c, depth) {
  while (i <= L) {
    c = substr(S, i, 1)
    if (c == "(") {
      depth++
      i++
    } else if (c == ")") {
      i++
      if (--depth == 0) return i
    } else {
      i = element(i, 0)
    }
  }
  return i
}

# $(...) or $((...)), with the dollar at i.
function dollar_paren(i,    end) {
  if (substr(S, i + 2, 1) == "(") {
    end = arithmetic_end(i + 3)
    if (end) return arithmetic(i + 3, end)
  }
  return commands(i + 2, ")")
}

# Where $((...)) ends, given where its text starts, or 0 if its parentheses don't close
# with )) and so it's really $( (a) ... ), as the shell also decides.
function arithmetic_end(i,    c, depth) {
  depth = 2
  while (i <= L) {
    c = substr(S, i, 1)
    if (c == "(") {
      depth++
    } else if (c == ")") {
      if (--depth == 1) return (substr(S, i + 1, 1) == ")") ? i + 2 : 0
    }
    i++
  }
  return 0
}

# The only commands in arithmetic are substitutions.
function arithmetic(i, end,    c) {
  while (i < end) {
    c = substr(S, i, 1)
    if (c == "`" || (c == "$" && substr(S, i + 1, 1) == "(")) {
      i = element(i, 1)
    } else {
      i++
    }
  }
  return end
}

# `...` with the opening one at i. Its text is unescaped once, as the shell does, and
# then read as a command list of its own.
function backticks(i, in_dq,    j, c, n, text, saved) {
  j = i + 1
  text = ""
  while (j <= L) {
    c = substr(S, j, 1)
    if (c == "`") break
    if (c == "\\") {
      n = substr(S, j + 1, 1)
      if (n == "`" || n == "\\" || n == "$" || (in_dq && n == "\"")) text = text n
      else text = text c n
      j += 2
    } else {
      text = text c
      j++
    }
  }
  saved = S
  S = text
  L = length(S)
  commands(1, "")
  S = saved
  L = length(S)
  return j + 1
}

# << or <<< at i, in the word being built. A heredoc's delimiter joins the word and goes
# on the list of bodies to skip after the next newline.
function redirect_in(i,    j, k, c, delimiter, tabs) {
  if (substr(S, i + 2, 1) == "<") {
    word = word "<<<"
    return i + 3
  }
  j = i + 2
  if (substr(S, j, 1) == "-") {
    tabs = 1
    j++
  }
  while (substr(S, j, 1) == " " || substr(S, j, 1) == "\t") j++
  delimiter = ""
  while (j <= L) {
    c = substr(S, j, 1)
    if (c ~ /[ \t\n;&|<>()]/) break
    if (c == "\\") {
      delimiter = delimiter substr(S, j + 1, 1)
      j += 2
    } else if (c == "'" || c == "\"") {
      k = index(substr(S, j + 1), c)
      if (!k) k = L - j + 1
      delimiter = delimiter substr(S, j + 1, k - 1)
      j += k + 1
    } else {
      delimiter = delimiter c
      j++
    }
  }
  heredoc_count++
  heredoc_delimiter[heredoc_count] = delimiter
  heredoc_tabs[heredoc_count] = tabs
  word = word substr(S, i, j - i)
  return j
}

# The waiting heredoc bodies, starting at i, the start of a line. Inside a substitution,
# bash also takes the delimiter directly before the closing parenthesis.
function skip_heredocs(i, nested,    h, e, line, text, d) {
  for (h = heredoc_base + 1; h <= heredoc_count; h++) {
    d = heredoc_delimiter[h]
    while (i <= L) {
      e = index(substr(S, i), "\n")
      line = e ? substr(S, i, e - 1) : substr(S, i)
      text = line
      if (heredoc_tabs[h]) sub(/^\t+/, "", text)
      if (nested && index(text, d ")") == 1) {
        i += length(line) - length(text) + length(d)
        break
      }
      i += length(line) + 1
      if (text == d) break
    }
  }
  heredoc_count = heredoc_base
  return i
}
