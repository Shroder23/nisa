# Nisa Matchmaker Foundation — client release

## Added
- Matchmaker Network entry in PostgreSQL-backed Profile area.
- Partner application and approval-aware dashboard.
- Represented-client list and consent-request action.
- WhatsApp/plain-text biodata parser with common field aliases.
- CSV and JSON imports with review, required-field validation and duplicate suppression.
- All imported rows are submitted with `publish:false` and private visibility by default.
- CSV export for profiles represented by the logged-in matchmaker.
- Additive server schema and exact API contract in `matchmaker_server_addon/`.
- Parser tests in `test/matchmaker_import_service_test.dart`.

## Intentionally not faked
The uploaded snapshot contains no FastAPI/PostgreSQL server source. Therefore the Flutter screens will become live only after the supplied API contract is implemented in the current server. XLSX/PDF/image OCR import is also not enabled in this client release; CSV/JSON/TXT are supported safely now.

## Local release gate
Run on the development PC:
```
dart format lib test
flutter pub get
flutter analyze
flutter test
flutter run --dart-define="NISA_GOOGLE_SERVER_CLIENT_ID=<existing value>" --dart-define="NISA_USE_POSTGRES_AUTH_PREVIEW=true"
```
Then test: existing registration/login; verification; discovery; interests; matches; messages; notifications; moderator/admin screens; Matchmaker application; approved account dashboard; TXT/CSV/JSON import; duplicate rows; consent request; CSV export.
