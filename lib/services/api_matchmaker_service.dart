import 'dart:convert';

import '../models/matchmaker_profile.dart';
import 'api_auth_service.dart';

class ApiMatchmakerService {
  static Future<Map<String, dynamic>?> getMyPartnerAccount() async {
    final r = await ApiAuthService.get('/api/matchmakers/me');
    if (r.statusCode == 404) {
      return null;
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError('Could not load matchmaker account.');
    }
    final v = jsonDecode(r.body);
    return v is Map<String, dynamic> ? v : null;
  }

  static Future<Map<String, dynamic>> apply({
    required String businessName,
    required String phone,
    String notes = '',
  }) async {
    final r = await ApiAuthService.postJson('/api/matchmakers/apply', {
      'business_name': businessName,
      'phone': phone,
      'notes': notes,
    });
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError('Could not submit matchmaker application.');
    }
    return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
  }

  static Future<List<MatchmakerProfile>> listProfiles() async {
    final r = await ApiAuthService.get('/api/matchmakers/profiles');
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError('Could not load represented profiles.');
    }
    final v = jsonDecode(r.body);
    final rows = v is List
        ? v
        : (v is Map ? (v['profiles'] as List? ?? const []) : const []);
    return rows
        .whereType<Map>()
        .map((e) => MatchmakerProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> importProfiles(
    List<MatchmakerProfile> profiles,
  ) async {
    final r = await ApiAuthService.postJson(
      '/api/matchmakers/profiles/import',
      {'profiles': profiles.map((e) => e.toJson()).toList(), 'publish': false},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError('The server rejected the profile import.');
    }
    return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
  }

  static Future<void> requestConsent(String profileId) async {
    final r = await ApiAuthService.postJson(
      '/api/matchmakers/profiles/${Uri.encodeComponent(profileId)}/request-consent',
      const {},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError('Could not send consent request.');
    }
  }
}
