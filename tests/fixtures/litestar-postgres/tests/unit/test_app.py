from collections.abc import Iterator

from litestar.testing import TestClient

from app.main import create_app
from app.notes import Note, Notes


class FakeNotes(Notes):
    """Notes in a list, in place of the database."""

    def __init__(self) -> None:
        self.notes: list[Note] = []

    def add(self, body: str) -> Note:
        note = Note(len(self.notes) + 1, body)
        self.notes.append(note)
        return note

    def all(self) -> list[Note]:
        return list(self.notes)


def test_a_note_added_is_listed() -> None:
    fake = FakeNotes()

    def provide() -> Iterator[Notes]:
        yield fake

    with TestClient(app=create_app(provide)) as client:
        assert client.post("/notes", json={"body": "milk"}).status_code == 201
        assert client.get("/notes").json() == [{"id": 1, "body": "milk"}]
