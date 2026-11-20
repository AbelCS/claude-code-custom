# Newer GPT models in Codex's model cache, for hook-session-start.sh. Include it with
# -L <this folder>; don't run it.
#
# A slug counts only in exactly the shape gpt-<major>.<minor>-<family> or
# gpt-<major>-<family>, with a missing minor as 0, short numbers and a lowercase family.
# Anything else, such as codex-auto-review or gpt-reserve, is left out, so nothing but a
# slug in that shape can come out of here.

# The slug as {family, version: [major, minor]}, or nothing if it isn't in that shape.
def gpt_model:
  strings
  | capture("^gpt-(?<major>[0-9]{1,6})(?:\\.(?<minor>[0-9]{1,6}))?-(?<family>[a-z]+)$")
  | {family, version: [(.major | tonumber), (.minor // "0" | tonumber)]};

# Run on the cache: the newest listed slug in the family of $current, if it's newer than
# $current. Nothing if $current isn't in the shape or the cache isn't as expected.
def newer_than($current):
  ($current | gpt_model) as $in_use
  | [.models | arrays | .[] | objects | .slug | strings
      | . as $slug | gpt_model | select(.family == $in_use.family) | {slug: $slug, version}]
  | select(length > 0)
  | max_by(.version)
  | select(.version > $in_use.version)
  | .slug;
