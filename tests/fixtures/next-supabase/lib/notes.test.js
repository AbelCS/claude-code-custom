import assert from "node:assert/strict";
import { test } from "node:test";
import { noteTitle } from "./notes.js";

test("a note's title is its first line", () => {
  assert.equal(noteTitle("  Shopping \nmilk"), "Shopping");
});

test("a note with an empty first line is untitled", () => {
  assert.equal(noteTitle("\nmilk"), "Untitled");
});
