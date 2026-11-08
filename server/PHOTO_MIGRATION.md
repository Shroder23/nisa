# Legacy profile photo import

The PostgreSQL photo route expects files in `/data/profile-photos` and rows in
`profile_photos`; the API returns protected URLs such as
`/api/profile-photos/<photo-id>`. The Flutter repair now fetches those URLs with
the signed-in API token. Firebase Storage URLs remain supported during the
transition.

The Firestore JSON export contains photo URL metadata but not the referenced
image bytes. Export the old Firebase Storage objects separately, then use
`photo_manifest_template.csv` to build a CSV mapping them to PostgreSQL account
IDs. Paths in the manifest are relative to the source directory:

```csv
user_id,source_file,display_order
<postgres-user-id>,<path-under-source-root>/primary.jpg,0
<postgres-user-id>,<path-under-source-root>/second.webp,1
```

Copy the photo tree and manifest under the existing photo volume, for example
`/data/profile-photos/legacy-import/`. Run a validation-only pass first:

```sh
python /app/migrate_legacy_photos.py \
  --source-root /data/profile-photos/legacy-import \
  --manifest /data/profile-photos/legacy-import/manifest.csv
```

After checking that all rows point to the intended profiles and orders, run the
same command with `--apply`. The script validates image type, size, dimensions,
and decoding; requires every account to have a profile; and updates only the
listed display orders. It never deletes other photo orders. Keep the original
export until the imported photos have been checked in the app.
