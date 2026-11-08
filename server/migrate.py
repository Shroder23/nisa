"""Apply the ordered Nisa PostgreSQL migrations exactly once.

Each file is executed in its own transaction and recorded with a SHA-256
checksum. A changed migration that was already applied is rejected instead of
silently drifting production schema.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

import psycopg


ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "migrations.txt"


def read_secret(path: str) -> str:
    return Path(path).read_text(encoding="utf-8").strip()


def connection_parameters() -> dict[str, object]:
    password_file = os.getenv("DB_PASSWORD_FILE")
    password = (
        read_secret(password_file)
        if password_file
        else os.environ["DB_PASSWORD"]
    )
    return {
        "host": os.getenv("DB_HOST", "localhost"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.getenv("DB_NAME", "nisa"),
        "user": os.getenv("DB_USER", "nisa_app"),
        "password": password,
    }


def migration_files() -> list[Path]:
    names = [
        line.strip()
        for line in MANIFEST.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    files = [ROOT / name for name in names]
    missing = [str(path) for path in files if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"Missing migration files: {', '.join(missing)}")
    return files


def main() -> None:
    with psycopg.connect(**connection_parameters()) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT pg_advisory_lock(hashtext('nisa_schema_migrations'))")
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    filename TEXT PRIMARY KEY,
                    checksum_sha256 TEXT NOT NULL,
                    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
        connection.commit()

        try:
            for path in migration_files():
                sql = path.read_text(encoding="utf-8")
                checksum = hashlib.sha256(sql.encode("utf-8")).hexdigest()
                with connection.cursor() as cursor:
                    cursor.execute(
                        "SELECT checksum_sha256 FROM schema_migrations WHERE filename = %s",
                        (path.name,),
                    )
                    applied = cursor.fetchone()
                    if applied:
                        if applied[0] != checksum:
                            raise RuntimeError(
                                f"Applied migration changed on disk: {path.name}"
                            )
                        print(f"skip {path.name}")
                        continue
                    print(f"apply {path.name}")
                    cursor.execute(sql)
                    cursor.execute(
                        "INSERT INTO schema_migrations(filename, checksum_sha256) VALUES (%s, %s)",
                        (path.name, checksum),
                    )
                connection.commit()
        finally:
            with connection.cursor() as cursor:
                cursor.execute("SELECT pg_advisory_unlock(hashtext('nisa_schema_migrations'))")
            connection.commit()


if __name__ == "__main__":
    main()
