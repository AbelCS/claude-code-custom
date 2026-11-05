# Checks the input against the JSON Schema in $schema[0], and prints one message per
# problem, as "<where>: <what>". Only the keywords the project file's schema uses are
# known: type, const, required, properties, additionalProperties, items, minLength,
# pattern, not and allOf. A part's x-error, when it has one, replaces the message for
# its own keywords. Patterns are jq's regular expressions.

def where($path; $key):
  if $path == "" then $key
  elif ($key | type) == "number" then "\($path)[\($key)]"
  else "\($path).\($key)" end;

def say($path; $s; $what):
  "\(if $path == "" then "the file" else $path end): \($s["x-error"] // $what)";

def json_type:
  if type == "number" and . == floor then "integer" else type end;

def type_ok($want):
  json_type as $have
  | [$want] | flatten
  | any(. == $have or (. == "number" and $have == "integer"));

def check($s; $path):
  . as $v
  | if ($s | has("type")) and ($v | type_ok($s.type) | not) then
      say($path; $s; "has to be \([$s.type] | flatten | join(" or "))")
    else
      (if ($s | has("const")) and $v != $s.const then
         say($path; $s; "has to be \($s.const | tojson)")
       else empty end),
      (if ($v | type) == "string" then
         (if ($s | has("minLength")) and ($v | length) < $s.minLength then
            say($path; $s; "can't be empty")
          else empty end),
         (if ($s | has("pattern")) and ($v | test($s.pattern) | not) then
            say($path; $s; "doesn't match \($s.pattern)")
          else empty end)
       else empty end),
      (if ($s | has("not")) and ([$v | check($s.not; $path)] | length) == 0 then
         say($path; $s; "isn't allowed")
       else empty end),
      (($s.allOf // [])[] as $part | $v | check($part; $path)),
      (if ($v | type) == "object" then
         (($s.required // [])[] as $key
          | select($v | has($key) | not)
          | "\(where($path; $key)): is missing. \($s.properties[$key].description // "")"
          | sub(" $"; "")),
         (($v | keys_unsorted[]) as $key
          | if ($s.properties // {} | has($key)) then
              $v[$key] | check($s.properties[$key]; where($path; $key))
            elif $s.additionalProperties == false then
              "\(where($path; $key)): isn't a field this file has"
            elif ($s.additionalProperties | type) == "object" then
              $v[$key] | check($s.additionalProperties; where($path; $key))
            else empty end)
       else empty end),
      (if ($v | type) == "array" and ($s | has("items")) then
         $v | to_entries[] as $item | $item.value | check($s.items; where($path; $item.key))
       else empty end)
    end;

check($schema[0]; "")
