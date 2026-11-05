"""The notes API."""

from collections.abc import Callable, Iterator
from dataclasses import dataclass

from litestar import Litestar, get, post
from litestar.di import NamedDependency, Provide
from litestar.params import JSONBody

from app.notes import Note, Notes, connect


@dataclass(frozen=True)
class NewNote:
    body: str


@get("/notes", sync_to_thread=True)
def list_notes(notes: NamedDependency[Notes]) -> list[Note]:
    return notes.all()


@post("/notes", sync_to_thread=True)
def add_note(notes: NamedDependency[Notes], data: JSONBody[NewNote]) -> Note:
    return notes.add(data.body)


def provide_notes() -> Iterator[Notes]:
    with connect() as notes:
        yield notes


def create_app(notes: Callable[[], Iterator[Notes]] = provide_notes) -> Litestar:
    return Litestar([list_notes, add_note], dependencies={"notes": Provide(notes)})


app = create_app()
