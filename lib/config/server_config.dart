class ServerConfig {
  ServerConfig._();

  /// PostgreSQL/FastAPI service confirmed at https://api.nisaesakina.com.
  /// New PostgreSQL-backed services should use this URL explicitly.
  /// Override with --dart-define=NISA_POSTGRES_API_URL=https://your-api-host
  static const String postgresApiBaseUrl = String.fromEnvironment(
    'NISA_POSTGRES_API_URL',
    defaultValue: 'https://api.nisaesakina.com',
  );

  /// Existing Firebase-era photo, location, and verification services still
  /// use the legacy server until each feature is migrated.
  /// Override with --dart-define=NISA_LEGACY_SERVER_URL=https://your-legacy-host
  static const String legacyBaseUrl = String.fromEnvironment(
    'NISA_LEGACY_SERVER_URL',
    defaultValue: 'https://desktop-a37j0mg.tail37875a5.ts.net',
  );

  /// Backwards-compatible URL used by existing legacy service clients.
  static const String baseUrl = String.fromEnvironment(
    'NISA_SERVER_URL',
    defaultValue: 'https://desktop-a37j0mg.tail37875a5.ts.net',
  );
}
