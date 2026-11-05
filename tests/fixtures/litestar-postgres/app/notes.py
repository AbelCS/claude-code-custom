"""Notes in Postgres. This is the only module that talks to the database."""

import os
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass

import psycopg

SCHEMA = """
create table if not exists notes (
  id bigint generated always as identity primary key,
  body text not null check (body <> '')
)
"""


@dataclass(frozen=True)
class Note:
    id: int
    body: str


class Notes:
    def __init__(self, conn: psycopg.Connection) -> None:
        self._conn = conn

    def create_table(self) -> None:
        self._conn.execute(SCHEMA)

    def add(self, body: str) -> Note:
        row = self._conn.execute(
            "insert into notes (body) values (%s) returning id, body", (body,)
        ).fetchone()
        return Note(*row)

    def all(self) -> list[Note]:
        rows = self._conn.execute("select id, body from notes order by id").fetchall()
        return [Note(*row) for row in rows]


@contextmanager
def connect() -> Iterator[Notes]:
    """Notes on the database at DATABASE_URL, committed when the block ends."""
    with psycopg.connect(os.environ["DATABASE_URL"]) as conn:
        yield Notes(conn)
