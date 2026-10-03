import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_auth_service.dart';

/// PostgreSQL-backed family and guardian invitations for API accounts.
class ApiFamilyService {
  ApiFamilyService._();

  static Future<List<Map<String, dynamic>>> getMembers() async {
    final response = await ApiAuthService.get('/api/family/members');
    final data = _decode(response);
    _check(response, data);
    final rows = data?['members'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<void> createInvitation({
    required String name,
    required String role,
    required String email,
    required String phone,
  }) async {
    final response = await ApiAuthService.postJson('/api/family/members', {
      'name': name.trim(),
      'role': role,
      'email': email.trim().toLowerCase(),
      'phone': _normalizePhone(phone),
    });
    _check(response, _decode(response));
  }

  static Future<void> removeMember(String memberId) async {
    final response = await ApiAuthService.delete(
      '/api/family/members/${Uri.encodeComponent(memberId)}',
    );
    _check(response, _decode(response));
  }

  static Future<List<Map<String, dynamic>>> getIncomingInvitations() async {
    final response = await ApiAuthService.get(
      '/api/family/invitations/incoming',
    );
    final data = _decode(response);
    _check(response, data);
    final rows = data?['invitations'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<void> respondToInvitation(
    String invitationId, {
    required bool accept,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/family/invitations/${Uri.encodeComponent(invitationId)}/respond',
      {'accept': accept},
    );
    _check(response, _decode(response));
  }

  static String _normalizePhone(String value) {
    final trimmed = value.trim();
    final prefix = trimmed.startsWith('+') ? '+' : '';
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return '$prefix$digits';
  }

  static Map<String, dynamic>? _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static void _check(http.Response response, Map<String, dynamic>? data) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data?['detail']?.toString() ??
            'The family request could not be completed.',
      );
    }
  }
}
