import { noteTitle } from "../lib/notes.js";

export default function Home() {
  return <h1>{noteTitle("Notes\nEach person sees only their own.")}</h1>;
}
