# Matchmaker API contract expected by the Flutter package

All routes require the existing Nisa bearer-token authentication. Never trust a matchmaker_id from the client; derive it from the authenticated user.

- `GET /api/matchmakers/me` -> 404 if no application; otherwise matchmaker account JSON.
- `POST /api/matchmakers/apply` body `{business_name, phone, notes}` -> pending account. Rate-limit and reject duplicate applications.
- `GET /api/matchmakers/profiles` -> only profiles owned by authenticated approved matchmaker.
- `POST /api/matchmakers/profiles/import` body `{profiles:[...], publish:false}` -> server revalidates every row, normalizes email/phone, computes duplicate/source hashes, inserts only PRIVATE drafts, and returns `{created, skipped, errors}`.
- `POST /api/matchmakers/profiles/{id}/request-consent` -> ownership check; create consent event; send notification/email through existing Nisa notification infrastructure; do not reveal profile to discovery.

## Required invariants
1. Imported profiles never become `users` automatically.
2. Imported profiles never enter discovery while consent is absent/revoked.
3. A matchmaker can read/update only profiles they represent unless an explicit cross-bureau introduction workflow grants limited access.
4. Phone/email are private and excluded from discovery/search responses.
5. Every export, consent change, claim, introduction, and administrative override is audited.
6. Server-side duplicate checks must run even though the client performs convenience dedupe.
7. Claiming a profile requires authenticated proof/OTP and creates a link to `users`; it must not copy credentials.
8. Moderator/admin approval of matchmakers must use existing capability checks, not a client-provided role.
