// A note's title is its first line, trimmed, or "Untitled" when that's empty.
export function noteTitle(body) {
  const first = body.split("\n", 1)[0].trim();
  return first === "" ? "Untitled" : first;
}
