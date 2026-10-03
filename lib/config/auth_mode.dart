/// Temporary switch used to test the PostgreSQL sign-in path independently.
///
/// Enable with --dart-define=NISA_USE_POSTGRES_AUTH_PREVIEW=true. Firebase
/// remains the default until the remaining product screens are migrated.
class AuthMode {
  AuthMode._();

  static const bool usePostgresPreview = bool.fromEnvironment(
    'NISA_USE_POSTGRES_AUTH_PREVIEW',
    defaultValue: false,
  );
}
