import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';

import '../config/server_config.dart';
import 'app_language_service.dart';

/// Authentication and JWT session storage for the PostgreSQL API.
///
/// This service is kept separate from Firebase Auth while app routing and
/// profile onboarding are migrated. Do not mix an API session with a Firebase
/// user in the same flow.
class ApiAuthService {
  ApiAuthService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _accessTokenKey = 'nisa_api_access_token';
  static const String _refreshTokenKey = 'nisa_api_refresh_token';
  static const String _installIdKey = 'nisa_api_install_id';
  static Future<String?>? _refreshInFlight;

  /// Populated after API sign-in or a successful session restoration.
  static final ValueNotifier<Map<String, dynamic>?> currentAccount =
      ValueNotifier<Map<String, dynamic>?>(null);

  static Uri _uri(String path) =>
      Uri.parse('${ServerConfig.postgresApiBaseUrl}$path');

  static Map<String, String> _deviceHeaders() {
    final platform = Platform.operatingSystem;
    final label = switch (platform) {
      'android' => 'Android device',
      'ios' => 'iPhone or iPad',
      'windows' => 'Windows device',
      'macos' => 'Mac device',
      'linux' => 'Linux device',
      _ => 'Nisa app device',
    };
    return {'X-Nisa-Device-Platform': platform, 'X-Nisa-Device-Label': label};
  }

  /// Returns a random, per-install identifier used only for new-device alerts.
  /// It is not derived from hardware, advertising, or account identifiers.
  static Future<Map<String, String>> _signInDeviceHeaders() async {
    var installId = await _storage.read(key: _installIdKey);
    if (installId == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(installId)) {
      final random = Random.secure();
      installId = List<int>.generate(
        32,
        (_) => random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      await _storage.write(key: _installIdKey, value: installId);
    }
    return {
      ..._deviceHeaders(),
      'X-Nisa-Install-Id': installId,
      'X-Nisa-Language': AppLanguageService.selectedCode.value,
    };
  }

  static Future<bool> emailExists(String email) async {
    final response = await http
        .post(
          _uri('/api/auth/check-email'),
          headers: {'Content-Type': 'application/json', ..._deviceHeaders()},
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError(_errorMessage(response));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['exists'] is! bool) {
      throw StateError('The server returned an invalid email check response.');
    }
    return decoded['exists'] as bool;
  }

  static Future<void> requestEmailCode(String email) async {
    final response = await http
        .post(
          _uri('/api/auth/request-otp'),
          headers: {'Content-Type': 'application/json', ..._deviceHeaders()},
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw StateError(_errorMessage(response));
    }
  }

  /// Verifies the code, stores the API's JWT pair in platform secure storage,
  /// and returns the PostgreSQL account row from the response.
  static Future<ApiAuthSession> verifyEmailCode({
    required String email,
    required String code,
    required String password,
  }) async {
    final response = await http
        .post(
          _uri('/api/auth/verify-otp'),
          headers: {'Content-Type': 'application/json', ..._deviceHeaders()},
          body: jsonEncode({
            'email': email.trim(),
            'code': code.trim(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw StateError(_errorMessage(response));
    }

    return _acceptSessionResponse(response);
  }

  static Future<ApiAuthSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final deviceHeaders = await _signInDeviceHeaders();
    final response = await http
        .post(
          _uri('/api/auth/password-login'),
          headers: {'Content-Type': 'application/json', ...deviceHeaders},
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiAuthException.fromResponse(response);
    }
    return _acceptSessionResponse(response);
  }

  static Future<ApiAuthSession> signInWithGoogle() async {
    const serverClientId = String.fromEnvironment(
      'NISA_GOOGLE_SERVER_CLIENT_ID',
    );
    final googleSignIn = GoogleSignIn(
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    await googleSignIn.signOut();
    final account = await googleSignIn.signIn();
    if (account == null) throw StateError('Google sign-in was cancelled.');
    final googleAuth = await account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google sign-in is not configured. Contact support.');
    }
    final deviceHeaders = await _signInDeviceHeaders();
    final response = await http
        .post(
          _uri('/api/auth/google'),
          headers: {'Content-Type': 'application/json', ...deviceHeaders},
          body: jsonEncode({'id_token': idToken}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(_errorMessage(response));
    return _acceptSessionResponse(response);
  }

  static Future<void> requestPasswordReset(String email) async {
    final response = await http
        .post(
          _uri('/api/auth/request-password-reset'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(_errorMessage(response));
  }

  static Future<ApiAuthSession> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final deviceHeaders = await _signInDeviceHeaders();
    final response = await http
        .post(
          _uri('/api/auth/reset-password'),
          headers: {'Content-Type': 'application/json', ...deviceHeaders},
          body: jsonEncode({
            'email': email.trim(),
            'code': code.trim(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw StateError(_errorMessage(response));
    return _acceptSessionResponse(response);
  }

  static Future<ApiAuthSession> _acceptSessionResponse(
    http.Response response,
  ) async {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['user'] is! Map<String, dynamic> ||
        decoded['tokens'] is! Map<String, dynamic>) {
      throw StateError('The server returned an invalid sign-in response.');
    }

    final user = decoded['user'] as Map<String, dynamic>;
    final tokens = decoded['tokens'] as Map<String, dynamic>;
    final accessToken = tokens['access_token']?.toString();
    final refreshToken = tokens['refresh_token']?.toString();

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      throw StateError('The server did not return a complete sign-in session.');
    }

    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    currentAccount.value = user;

    return ApiAuthSession(user: user);
  }

  /// Restores a PostgreSQL session after app restart. A stale access token is
  /// refreshed once; temporary network errors are surfaced without deleting
  /// the saved refresh token.
  static Future<Map<String, dynamic>?> restoreAccount() async {
    var accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      await clearSession();
      return null;
    }

    if (accessToken == null || accessToken.isEmpty) {
      accessToken = await _refreshAccessToken(refreshToken);
      if (accessToken == null) return null;
    }

    var response = await _getAccount(accessToken);
    if (response.statusCode == 401) {
      accessToken = await _refreshAccessToken(refreshToken);
      if (accessToken == null) return null;
      response = await _getAccount(accessToken);
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        currentAccount.value = decoded;
        return decoded;
      }
      throw StateError('The server returned an invalid account response.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      await clearSession();
      return null;
    }
    throw StateError(_errorMessage(response));
  }

  static Future<http.Response> _getAccount(String accessToken) => http
      .get(_uri('/api/me'), headers: {'Authorization': 'Bearer $accessToken'})
      .timeout(const Duration(seconds: 20));

  /// Sends an authenticated API request and retries once after refreshing a
  /// rejected access token. Callers interpret the final response body/status.
  static Future<http.Response> authorizedRequest(
    Future<http.Response> Function(String accessToken) send,
  ) async {
    var accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      await clearSession();
      throw StateError('Please sign in again.');
    }
    if (accessToken == null || accessToken.isEmpty) {
      accessToken = await _refreshAccessToken(refreshToken);
      if (accessToken == null) throw StateError('Please sign in again.');
    }

    var response = await send(accessToken);
    if (response.statusCode != 401) return response;
    accessToken = await _refreshAccessToken(refreshToken);
    if (accessToken == null) return response;
    response = await send(accessToken);
    if (response.statusCode == 401) await clearSession();
    return response;
  }

  static Future<http.Response> get(String path) => authorizedRequest(
    (token) => http
        .get(_uri(path), headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 20)),
  );

  static Future<http.Response> getProtectedFile(String path) =>
      authorizedRequest((token) async {
        final request = http.Request('GET', _uri(path))
          ..headers['Authorization'] = 'Bearer $token';
        final streamed = await request.send().timeout(
          const Duration(minutes: 2),
        );
        return http.Response.fromStream(streamed);
      });

  static Future<http.Response> postJson(
    String path,
    Map<String, dynamic> body,
  ) => authorizedRequest(
    (token) => http
        .post(
          _uri(path),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20)),
  );

  static Future<http.Response> putJson(
    String path,
    Map<String, dynamic> body,
  ) => authorizedRequest(
    (token) => http
        .put(
          _uri(path),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20)),
  );

  static Future<http.Response> delete(String path) => authorizedRequest(
    (token) => http
        .delete(_uri(path), headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 20)),
  );

  static Future<void> revokeAllSessions() async {
    final response = await postJson('/api/auth/sessions/revoke-all', const {});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_errorMessage(response));
    }
    await clearSession();
  }

  static Future<http.Response> postMultipart(
    String path, {
    required Map<String, String> fields,
    required Map<String, File> files,
  }) => authorizedRequest((token) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields);
    for (final entry in files.entries) {
      request.files.add(
        await http.MultipartFile.fromPath(entry.key, entry.value.path),
      );
    }
    final streamed = await request.send().timeout(const Duration(minutes: 2));
    return http.Response.fromStream(streamed);
  });

  static Future<String?> _refreshAccessToken(String refreshToken) {
    final current = _refreshInFlight;
    if (current != null) return current;
    final future = _performRefreshAccessToken(refreshToken);
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
  }

  static Future<String?> _performRefreshAccessToken(String refreshToken) async {
    // A delayed 401 may arrive after another request already rotated this
    // refresh token. Reuse the stored replacement instead of sending the old
    // token again and triggering server-side reuse detection.
    final storedRefreshToken = await _storage.read(key: _refreshTokenKey);
    if (storedRefreshToken != null && storedRefreshToken != refreshToken) {
      return _storage.read(key: _accessTokenKey);
    }

    final response = await http
        .post(
          _uri('/api/auth/refresh'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 401) {
      await clearSession();
      return null;
    }
    if (response.statusCode != 200) {
      throw StateError(_errorMessage(response));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('The server returned an invalid refresh response.');
    }
    final accessToken = decoded['access_token']?.toString();
    final newRefreshToken = decoded['refresh_token']?.toString();
    if (accessToken == null ||
        accessToken.isEmpty ||
        newRefreshToken == null ||
        newRefreshToken.isEmpty) {
      throw StateError('The server did not return refreshed session tokens.');
    }

    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: newRefreshToken);
    return accessToken;
  }

  static Future<void> signOut() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (accessToken != null && refreshToken != null) {
      try {
        await http
            .post(
              _uri('/api/auth/logout'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $accessToken',
              },
              body: jsonEncode({'refresh_token': refreshToken}),
            )
            .timeout(const Duration(seconds: 10));
      } finally {
        await clearSession();
      }
      return;
    }
    await clearSession();
  }

  static Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    currentAccount.value = null;
  }

  static String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detailValue = decoded['detail'];
        final detail = detailValue is Map<String, dynamic>
            ? detailValue['message']?.toString()
            : detailValue?.toString();
        if (detail != null && detail.isNotEmpty) {
          if (response.statusCode >= 500 &&
              detail.toLowerCase() == 'internal server error') {
            return AppLanguageService.translate(
              'The server could not complete this request. Check the API logs for the cause.',
            );
          }
          final key = detail.replaceFirst(RegExp(r'\s*\(HTTP\s+\d+\)\.?$'), '');
          final translated = AppLanguageService.translate(key);
          return response.statusCode >= 500
              ? translated
              : '$translated (HTTP ${response.statusCode}).';
        }
      }
    } catch (_) {
      // Use the generic message for non-JSON proxy or network responses.
    }
    if (response.statusCode >= 500) {
      return AppLanguageService.translate(
        'The server could not complete this request. Check the API logs for the cause.',
      );
    }
    return 'Nisa sign-in failed. The API returned HTTP ${response.statusCode}. Please try again.';
  }
}

/// Structured authentication failure returned by the API.
///
/// Callers must branch on [code], never on HTTP status alone: an ordinary
/// incorrect password remains indistinguishable from an unknown email.
class ApiAuthException implements Exception {
  final String code;
  final String message;

  const ApiAuthException({required this.code, required this.message});

  factory ApiAuthException.fromResponse(http.Response response) {
    String? code;
    String? message;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic>) {
          code = detail['code']?.toString();
          message = detail['message']?.toString();
        } else {
          message = detail?.toString();
        }
      }
    } catch (_) {
      // Fall through to the existing generic API error formatting.
    }
    return ApiAuthException(
      code: code ?? 'authentication_failed',
      message: message ?? ApiAuthService._errorMessage(response),
    );
  }

  @override
  String toString() => message;
}

class ApiAuthFailureCode {
  ApiAuthFailureCode._();

  static const passwordSetupRequired = 'password_setup_required';

  static bool requiresPasswordSetup(Object error) =>
      error is ApiAuthException && error.code == passwordSetupRequired;
}

class ApiAuthSession {
  final Map<String, dynamic> user;

  const ApiAuthSession({required this.user});

  String get userId => user['id']?.toString() ?? '';
  String get email => user['email']?.toString() ?? '';
}
