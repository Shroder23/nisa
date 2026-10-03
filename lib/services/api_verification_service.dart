import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_auth_service.dart';

/// PostgreSQL parent/guardian verification for API accounts.
class ApiVerificationService {
  ApiVerificationService._();

  static Future<Map<String, dynamic>> getStatus() async {
    final response = await ApiAuthService.get('/api/verification/status');
    final data = _decode(response);
    _check(response, data);
    return data!;
  }

  static Future<bool> isAdmin() async {
    final response = await ApiAuthService.get(
      '/api/admin/verification/capability',
    );
    final data = _decode(response);
    _check(response, data);
    return data?['is_admin'] == true;
  }

  static Future<void> submit({
    required String guardianName,
    required String relationship,
    required File guardianId,
    required File confirmationVideo,
    required File? authorityProof,
    String reviewerGenderPreference = 'any',
  }) async {
    final authorityFiles = authorityProof == null
        ? null
        : <String, File>{'authority_proof': authorityProof};
    final files = <String, File>{
      'guardian_id': guardianId,
      'confirmation_video': confirmationVideo,
      ...?authorityFiles,
    };
    final response = await ApiAuthService.postMultipart(
      '/api/verification/submit',
      fields: {
        'guardian_name': guardianName.trim(),
        'guardian_relationship': relationship,
        'consent_confirmed': 'true',
        'reviewer_gender_preference': reviewerGenderPreference,
      },
      files: files,
    );
    _check(response, _decode(response));
  }

  static Future<List<Map<String, dynamic>>> getReviewQueue() async {
    final response = await ApiAuthService.get(
      '/api/admin/verification/requests',
    );
    final data = _decode(response);
    _check(response, data);
    final rows = data?['requests'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<http.Response> getEvidence(
    String requestId,
    String kind,
  ) async {
    final response = await ApiAuthService.getProtectedFile(
      '/api/admin/verification/requests/${Uri.encodeComponent(requestId)}/evidence/$kind',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        _decode(response)?['detail']?.toString() ??
            'The private verification evidence could not be loaded.',
      );
    }
    return response;
  }

  static Future<void> review(
    String requestId, {
    required String decision,
    String notes = '',
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/verification/requests/${Uri.encodeComponent(requestId)}/review',
      {'decision': decision, 'notes': notes},
    );
    _check(response, _decode(response));
  }

  static Map<String, dynamic>? _decode(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static void _check(http.Response response, Map<String, dynamic>? data) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data?['detail']?.toString() ??
            'The verification request could not be completed.',
      );
    }
  }
}
