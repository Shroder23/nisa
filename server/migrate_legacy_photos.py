#!/usr/bin/env python3
"""Import exported legacy profile images into Nisa's protected photo store.

Manifest columns: user_id,source_file,display_order
The source_file path is relative to --source-root. A first run is a dry run;
pass --apply to write the image files and PostgreSQL rows.
"""

import argparse
import csv
import os
import re
import shutil
import subprocess
import uuid
from pathlib import Path



SAFE_NAME = re.compile(r"^[0-9a-f]{32}\.(?:jpg|jpeg|png|webp)$")
ALLOWED_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
SIGNATURES = {
    ".jpg": lambda data: data.startswith(b"\xff\xd8\xff"),
    ".jpeg": lambda data: data.startswith(b"\xff\xd8\xff"),
    ".png": lambda data: data.startswith(b"\x89PNG\r\n\x1a\n"),
    ".webp": lambda data: data[:4] == b"RIFF" and data[8:12] == b"WEBP",
}


def database_connection():
    import psycopg
    from psycopg.rows import dict_row

    password_path = os.getenv("DB_PASSWORD_FILE", "/run/secrets/postgres_password")
    password = Path(password_path).read_text(encoding="utf-8").strip()
    return psycopg.connect(
        host=os.getenv("DB_HOST", "postgres"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.getenv("DB_NAME", "nisa"),
        user=os.getenv("DB_USER", "nisa_app"),
        password=password,
        row_factory=dict_row,
    )


def safe_source(source_root: Path, relative: str) -> Path:
    path = (source_root / relative).resolve()
    if not path.is_relative_to(source_root):
        raise ValueError("source_file must stay inside the source directory")
    return path


def validate_image(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix not in ALLOWED_SUFFIXES:
        raise ValueError("only JPEG, PNG, and WebP photos are supported")
    size = path.stat().st_size
    if size < 1 or size > 8 * 1024 * 1024:
        raise ValueError("photo size must be between 1 byte and 8 MB")
    with path.open("rb") as image:
        signature = image.read(12)
    if not SIGNATURES[suffix](signature):
        raise ValueError("file contents do not match the image extension")
    ffprobe = shutil.which("ffprobe")
    ffmpeg = shutil.which("ffmpeg")
    if not ffprobe or not ffmpeg:
        raise ValueError("ffprobe and ffmpeg are required for image validation")
    probe = subprocess.run(
        [ffprobe, "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height", "-of", "csv=s=x:p=0", str(path)],
        capture_output=True, text=True, timeout=15, check=False,
    )
    if probe.returncode != 0:
        raise ValueError("image could not be decoded")
    try:
        width, height = (int(value) for value in probe.stdout.strip().split("x", 1))
    except (TypeError, ValueError):
        raise ValueError("image dimensions could not be read")
    if width < 1 or height < 1 or width > 8000 or height > 8000 or width * height > 40_000_000:
        raise ValueError("image dimensions exceed the server limit")
    decoded = subprocess.run(
        [ffmpeg, "-nostdin", "-v", "error", "-i", str(path), "-frames:v", "1",
         "-vf", "scale=64:64", "-f", "null", "-"],
        capture_output=True, timeout=15, check=False,
    )
    if decoded.returncode != 0:
        raise ValueError("image could not be decoded")
    return suffix


def load_manifest(path: Path, source_root: Path):
    records = []
    seen = set()
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        required = {"user_id", "source_file", "display_order"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("manifest needs user_id, source_file, display_order columns")
        for line, row in enumerate(reader, start=2):
            user_id = (row.get("user_id") or "").strip()
            relative = (row.get("source_file") or "").strip()
            try:
                order = int(row.get("display_order", ""))
            except ValueError:
                raise ValueError(f"line {line}: display_order must be an integer")
            if not user_id or not relative or order not in range(5):
                raise ValueError(f"line {line}: user_id, source_file, and order 0-4 are required")
            key = (user_id, order)
            if key in seen:
                raise ValueError(f"line {line}: duplicate user_id and display_order")
            seen.add(key)
            source = safe_source(source_root, relative)
            if not source.is_file():
                raise ValueError(f"line {line}: file not found: {relative}")
            suffix = validate_image(source)
            records.append((user_id, source, order, suffix))
    return records


def validate_users(records):
    user_ids = sorted({record[0] for record in records})
    with database_connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            "SELECT user_id FROM profiles WHERE user_id = ANY(%s)",
            (user_ids,),
        )
        found = {row["user_id"] for row in cursor.fetchall()}
    missing = sorted(set(user_ids) - found)
    if missing:
        raise ValueError(f"No profile row exists for {len(missing)} manifest user_id(s)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--apply", action="store_true", help="write files and database rows")
    parser.add_argument("--photo-root", default=os.getenv("PROFILE_PHOTO_STORAGE_DIR", "/data/profile-photos"), type=Path)
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    records = load_manifest(args.manifest, source_root)
    if not records:
        print("No photos listed; nothing to import.")
        return
    validate_users(records)
    if not args.apply:
        print(
            f"Validated {len(records)} photo(s) for {len({row[0] for row in records})} "
            "existing profile(s). Dry run only; pass --apply to import."
        )
        return

    args.photo_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    for user_id, source, order, suffix in records:
        destination_name = f"{uuid.uuid4().hex}{suffix}"
        destination = args.photo_root / destination_name
        try:
            shutil.copyfile(source, destination)
            destination.chmod(0o600)
            old_name = None
            with database_connection() as connection, connection.cursor() as cursor:
                cursor.execute("SELECT 1 FROM profiles WHERE user_id = %s", (user_id,))
                if cursor.fetchone() is None:
                    raise ValueError(f"no profile row exists for user_id {user_id}")
                cursor.execute(
                    """SELECT id, file_path FROM profile_photos
                       WHERE user_id = %s AND display_order = %s
                       ORDER BY created_at LIMIT 1 FOR UPDATE""",
                    (user_id, order),
                )
                existing = cursor.fetchone()
                if existing:
                    cursor.execute(
                        "UPDATE profile_photos SET file_path = %s WHERE id = %s",
                        (destination_name, existing["id"]),
                    )
                    old_name = existing["file_path"]
                else:
                    cursor.execute(
                        """INSERT INTO profile_photos (user_id, file_path, display_order)
                           VALUES (%s, %s, %s) RETURNING id""",
                        (user_id, destination_name, order),
                    )
                    photo_id = cursor.fetchone()["id"]
                    old_name = None
                if order == 0:
                    if existing:
                        photo_id = existing["id"]
                    cursor.execute(
                        "UPDATE profiles SET photo_url = %s, updated_at = NOW() WHERE user_id = %s",
                        (f"/api/profile-photos/{photo_id}", user_id),
                    )
            if old_name and SAFE_NAME.fullmatch(old_name):
                (args.photo_root / old_name).unlink(missing_ok=True)
            print(f"Imported user_id={user_id} photo_order={order}")
        except Exception:
            destination.unlink(missing_ok=True)
            raise


if __name__ == "__main__":
    main()
