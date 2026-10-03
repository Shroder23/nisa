import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/server_config.dart';
import '../models/admin_verification_request.dart';

class AdminVerificationApiService {
  AdminVerificationApiService._();

  static Uri _uri(String path) {
    final base = ServerConfig.baseUrl.endsWith('/')
        ? ServerConfig.baseUrl.substring(0, ServerConfig.baseUrl.length - 1)
        : ServerConfig.baseUrl;
    return Uri.parse('$base$path');
  }

  static Future<String> _firebaseToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'You must be signed in before using admin verification.',
      );
    }

    // Force refresh once so an old/expired cached token is not sent through
    // the public Funnel endpoint.
    final token = await user.getIdToken(true);
    if (token == null || token.trim().isEmpty) {
      throw StateError('Could not obtain a Firebase authentication token.');
    }
    return token.trim();
  }

  static Future<Map<String, String>> _headers(
    String adminKey, {
    bool json = true,
  }) async {
    final token = await _firebaseToken();

    return {
      // Keep the standard Authorization header for normal/direct requests.
      'Authorization': 'Bearer $token',

      // Also send a dedicated application header. The Nisa FastAPI server
      // accepts this as a fallback when a reverse tunnel/proxy does not
      // preserve Authorization exactly as expected.
      'X-Nisa-Firebase-Token': token,

      'X-Nisa-Admin-Key': adminKey.trim(),
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  static Future<Map<String, String>> protectedMediaHeaders({
    required String adminKey,
  }) {
    return _headers(adminKey, json: false);
  }

  static String resolveUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return '';
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return clean;
    }

    final base = ServerConfig.baseUrl.endsWith('/')
        ? ServerConfig.baseUrl.substring(0, ServerConfig.baseUrl.length - 1)
        : ServerConfig.baseUrl;

    return clean.startsWith('/') ? '$base$clean' : '$base/$clean';
  }

  static Future<List<AdminVerificationRequest>> pendingRequests({
    required String adminKey,
  }) async {
    final response = await http.get(
      _uri('/admin/verification-requests?status=pending'),
      headers: await _headers(adminKey),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Admin request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final items = decoded is Map<String, dynamic> ? decoded['items'] : null;

    if (items is! List) {
      return const <AdminVerificationRequest>[];
    }

    return items
        .whereType<Map>()
        .map(
          (item) => AdminVerificationRequest.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  static Future<AdminVerificationRequest> requestDetails({
    required String adminKey,
    required String requestId,
  }) async {
    final response = await http.get(
      _uri('/admin/verification-requests/$requestId'),
      headers: await _headers(adminKey),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Admin request failed (${response.statusCode}): ${response.body}',
      );
    }

    return AdminVerificationRequest.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  static Future<void> approve({
    required String adminKey,
    required String requestId,
  }) async {
    final response = await http.post(
      _uri('/admin/verification-requests/$requestId/approve'),
      headers: await _headers(adminKey),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Approve failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  static Future<void> reject({
    required String adminKey,
    required String requestId,
    required String reason,
  }) async {
    final response = await http.post(
      _uri('/admin/verification-requests/$requestId/reject'),
      headers: await _headers(adminKey),
      body: jsonEncode({'reason': reason.trim()}),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Reject failed (${response.statusCode}): ${response.body}',
      );
    }
  }
}
