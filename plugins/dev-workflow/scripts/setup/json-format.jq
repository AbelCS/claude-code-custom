# jq -r --arg step <indent> --argjson stringify <bool> -f json-format.jq: prints each
# input the way Prettier prints JSON with its defaults, so a project checking its files
# with Prettier passes:
#   - an object that isn't empty always has a line per key, as Prettier keeps an object
#     open when the source has a line break after its brace, which this always writes
#   - an array of nothing but strings, numbers, booleans and null goes on one line when
#     that line fits in 80 columns, counting the comma after it; else a line per item,
#     as does an array holding any object or array
#   - empty ones are {} and [], strings keep jq's escapes, and a newline ends the file
#   - with stringify, for the files Prettier prints as JSON.stringify does, such as
#     package.json, an array that isn't empty always has a line per item
# A tab counts as two columns, Prettier's default tab width. Two cases differ from
# Prettier, and setup writes neither: arrays of short arrays, which it can keep on one
# line, and numbers too many for one line, which it fills across lines.

def _width: gsub("\t"; "  ") | length;

# _print(indent; used; after): the value, starting `used` columns into its first line,
# with `after` more columns after it on its last, as a comma.
def _print($indent; $used; $after):
  ($indent + $step) as $inner
  | if type == "object" then
      if length == 0 then "{}"
      else (length - 1) as $last
        | [to_entries | to_entries[]
            | (.key == $last) as $end
            | ($inner + (.value.key | tojson) + ": ") as $lead
            | $lead + (.value.value | _print($inner; $lead | _width; if $end then 0 else 1 end))
              + (if $end then "" else "," end)]
        | "{\n" + join("\n") + "\n" + $indent + "}"
      end
    elif type == "array" then
      if length == 0 then "[]"
      else
        (if ($stringify | not) and all(.[]; type != "object" and type != "array")
         then "[" + (map(tojson) | join(", ")) + "]" else null end) as $flat
        | if $flat != null and $used + ($flat | _width) + $after <= 80 then $flat
          else (length - 1) as $last
            | [to_entries[]
                | (.key == $last) as $end
                | $inner + (.value | _print($inner; $inner | _width; if $end then 0 else 1 end))
                  + (if $end then "" else "," end)]
            | "[\n" + join("\n") + "\n" + $indent + "]"
          end
      end
    else tojson
    end;

_print(""; 0; 0)
