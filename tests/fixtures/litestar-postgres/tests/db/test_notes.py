"""The data-access layer against a real Postgres, which scripts/db-test.sh starts."""

import psycopg
import pytest

from app.notes import Note, connect


def test_notes_come_back_in_the_order_they_were_added() -> None:
    with connect() as notes:
        notes.create_table()
        notes.add("first")
        notes.add("second")
    with connect() as notes:
        assert notes.all() == [Note(1, "first"), Note(2, "second")]


def test_an_empty_note_is_refused() -> None:
    with pytest.raises(psycopg.errors.CheckViolation), connect() as notes:
        notes.add("")
