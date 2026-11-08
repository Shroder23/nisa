# Localization decisions

## Punjabi locale offered by the app

Decision recorded 2026-11-07 before changing locale identity: the existing
language selector names the language `Punjabi` and gives its native name as
`پنجابی`. That is Shahmukhi, the Arabic-derived script used for Pakistani
Punjabi. The existing `pa` Flutter locale and Gurmukhi translations conflict
with that visible choice. The app will therefore identify this option as
Punjabi (`pa-Arab-PK`), display its native name in Shahmukhi, and use
right-to-left layout. Hindi remains the separate `hi` locale and is not used as
a Punjabi fallback.

Punjabi strings will be converted as Punjabi text into Shahmukhi, retaining
their wording and meaning. Safety, consent, and verification copy must be
checked after conversion rather than replaced with Hindi or Urdu translations.
