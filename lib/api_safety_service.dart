import 'dart:convert';

import 'package:http/http.dart' as http;

import 'services/api_auth_service.dart';

/// PostgreSQL-backed blocking and member report operations.
class ApiSafetyService {
  ApiSafetyService._();

  static Future<List<Map<String, dynamic>>> getMyBlocks() async {
    final response = await ApiAuthService.get('/api/blocks');
    final data = _decode(response);
    _check(response, data);
    final rows = data?['blocks'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<void> blockUser(String userId) async {
    final response = await ApiAuthService.postJson(
      '/api/blocks/${Uri.encodeComponent(userId)}',
      const {},
    );
    _check(response, _decode(response));
  }

  static Future<void> unblockUser(String userId) async {
    final response = await ApiAuthService.delete(
      '/api/blocks/${Uri.encodeComponent(userId)}',
    );
    _check(response, _decode(response));
  }

  static Future<bool> isBlockedBetween(String userId) async {
    final response = await ApiAuthService.get(
      '/api/blocks/${Uri.encodeComponent(userId)}/status',
    );
    final data = _decode(response);
    _check(response, data);
    return data?['is_blocked_between'] == true;
  }

  static Future<bool> canReviewReports() async {
    final response = await ApiAuthService.get('/api/admin/reports/capability');
    final data = _decode(response);
    _check(response, data);
    return data?['is_admin'] == true;
  }

  static Future<bool> canReviewModeratorLogs() async {
    final response = await ApiAuthService.get(
      '/api/admin/moderation/capability',
    );
    final data = _decode(response);
    _check(response, data);
    return data?['is_admin'] == true;
  }

  static Future<Map<String, dynamic>> searchAdminUsers({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final queryParameters = <String, String>{
      'query': query,
      'offset': '$offset',
      'limit': '$limit',
    };
    final response = await ApiAuthService.get(
      '/api/admin/users?${Uri(queryParameters: queryParameters).query}',
    );
    final data = _decode(response);
    _check(response, data);
    final rows = data?['users'];
    return {
      'users': rows is List
          ? rows
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : const <Map<String, dynamic>>[],
      'next_offset': data?['next_offset'],
    };
  }

  static Future<List<Map<String, dynamic>>> getAdminUserActivity(
    String userId,
  ) async {
    final response = await ApiAuthService.get(
      '/api/admin/users/${Uri.encodeComponent(userId)}/activity',
    );
    final data = _decode(response);
    _check(response, data);
    final rows = data?['activities'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<void> setAdminUserModerator({
    required String userId,
    required String reviewerGender,
    required bool canReviewVerification,
    required bool canReviewReports,
    String reason = '',
  }) async {
    final response = await ApiAuthService.putJson(
      '/api/admin/users/${Uri.encodeComponent(userId)}/moderator-role',
      {
        'reviewer_gender': reviewerGender,
        'can_review_verification': canReviewVerification,
        'can_review_reports': canReviewReports,
        'reason': reason,
      },
    );
    _check(response, _decode(response));
  }

  static Future<void> removeAdminUserModerator({
    required String userId,
    required String reason,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/users/${Uri.encodeComponent(userId)}/moderator-role/remove',
      {'reason': reason},
    );
    _check(response, _decode(response));
  }

  static Future<void> permanentlyBanAdminUser({
    required String userId,
    required String reason,
    required bool denyEmail,
    String? denyPhone,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/moderation/users/${Uri.encodeComponent(userId)}/permanent-ban',
      {
        'reason': reason,
        'deny_email': denyEmail,
        if (denyPhone != null && denyPhone.trim().isNotEmpty)
          'deny_phone': denyPhone.trim(),
      },
    );
    _check(response, _decode(response));
  }

  static Future<void> deleteAdminUser({
    required String userId,
    required String reason,
    required bool denyEmail,
    String? denyPhone,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/users/${Uri.encodeComponent(userId)}/delete',
      {
        'reason': reason,
        'deny_email': denyEmail,
        if (denyPhone != null && denyPhone.trim().isNotEmpty)
          'deny_phone': denyPhone.trim(),
      },
    );
    _check(response, _decode(response));
  }

  static Future<List<Map<String, dynamic>>> getAccountRestrictions() async {
    final response = await ApiAuthService.get('/api/account/restrictions');
    final data = _decode(response);
    _check(response, data);
    final rows = data?['restrictions'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<Map<String, dynamic>> getModeratorLogsPage({
    int? beforeId,
  }) async {
    final query = beforeId == null ? '' : '?before_id=$beforeId';
    final response = await ApiAuthService.get(
      '/api/admin/moderation/logs$query',
    );
    final data = _decode(response);
    _check(response, data);
    final rows = data?['logs'];
    return {
      'logs': rows is List
          ? rows
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : const <Map<String, dynamic>>[],
      'next_before_id': data?['next_before_id'],
    };
  }

  static Future<List<Map<String, dynamic>>> getAdminModerationCases() async {
    final response = await ApiAuthService.get('/api/admin/moderation/cases');
    final data = _decode(response);
    _check(response, data);
    final rows = data?['cases'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<void> decideAdminModerationCase(
    String caseId, {
    required String decision,
    required String notes,
    bool denyEmail = false,
    String? denyPhone,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/moderation/cases/${Uri.encodeComponent(caseId)}/decision',
      {
        'decision': decision,
        'notes': notes,
        'deny_email': denyEmail,
        if (denyPhone != null && denyPhone.trim().isNotEmpty)
          'deny_phone': denyPhone.trim(),
      },
    );
    _check(response, _decode(response));
  }

  static Future<Map<String, dynamic>> getModeratorUiCapability() async {
    final response = await ApiAuthService.get(
      '/api/admin/moderation/moderator-capability',
    );
    final data = _decode(response);
    _check(response, data);
    return data ?? const {};
  }

  static Future<List<Map<String, dynamic>>> getModeratorWitnesses() async {
    final response = await ApiAuthService.get(
      '/api/admin/moderation/witnesses',
    );
    final data = _decode(response);
    _check(response, data);
    final rows = data?['moderators'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getMyPermanentBanRequests() async {
    final response = await ApiAuthService.get(
      '/api/admin/moderation/my-requests',
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

  static Future<Map<String, dynamic>> submitModeratorRecommendation({
    required String category,
    required String title,
    required String details,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/moderation/recommendations',
      {'category': category, 'title': title, 'details': details},
    );
    final data = _decode(response);
    _check(response, data);
    return data ?? const {};
  }

  static Future<List<Map<String, dynamic>>>
  getModeratorRecommendations() async {
    final response = await ApiAuthService.get(
      '/api/admin/moderation/recommendations',
    );
    final data = _decode(response);
    _check(response, data);
    final rows = data?['recommendations'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<void> updateModeratorRecommendation({
    required String recommendationId,
    required String status,
    required String adminNote,
  }) async {
    final response = await ApiAuthService.putJson(
      '/api/admin/moderation/recommendations/${Uri.encodeComponent(recommendationId)}',
      {'status': status, 'admin_note': adminNote},
    );
    _check(response, _decode(response));
  }

  static Future<void> overrideModeratorSanction({
    required String sanctionId,
    required String reason,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/moderation/sanctions/${Uri.encodeComponent(sanctionId)}/override',
      {'reason': reason},
    );
    _check(response, _decode(response));
  }

  static Future<void> overrideModeratorDecision({
    required int logId,
    required String reason,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/moderation/logs/$logId/override',
      {'reason': reason},
    );
    _check(response, _decode(response));
  }

  static Future<void> permanentlyBanUser({
    required String userId,
    required String reason,
    bool denyEmail = false,
    String? denyPhone,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/moderation/users/${Uri.encodeComponent(userId)}/permanent-ban',
      {
        'reason': reason,
        'deny_email': denyEmail,
        if (denyPhone != null && denyPhone.trim().isNotEmpty)
          'deny_phone': denyPhone.trim(),
      },
    );
    _check(response, _decode(response));
  }

  static Future<List<Map<String, dynamic>>> getMyReports() async {
    final response = await ApiAuthService.get('/api/reports/mine');
    final data = _decode(response);
    _check(response, data);
    final rows = data?['reports'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getReportQueue({
    String? triageCategory,
  }) async {
    final query = triageCategory == null
        ? ''
        : '?triage_category=${Uri.encodeQueryComponent(triageCategory)}';
    final response = await ApiAuthService.get('/api/admin/reports$query');
    final data = _decode(response);
    _check(response, data);
    final rows = data?['reports'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static Future<Map<String, dynamic>> getReportMetrics() async {
    final response = await ApiAuthService.get('/api/admin/reports/metrics');
    final data = _decode(response);
    _check(response, data);
    final metrics = data?['metrics'];
    return metrics is Map<String, dynamic>
        ? metrics
        : const <String, dynamic>{};
  }

  static Future<void> moderateReport(
    String reportId, {
    required String decision,
    String? outcomeCode,
    int? priority,
    String notes = '',
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/reports/${Uri.encodeComponent(reportId)}/decision',
      {
        'decision': decision,
        'notes': notes,
        'outcome_code': outcomeCode,
        'priority': priority,
      },
    );
    _check(response, _decode(response));
  }

  static Future<void> createModerationSanction({
    required String targetUserId,
    required String sanctionType,
    required String reasonCode,
    required String reason,
    required String userNotice,
    required int durationDays,
    String? otherUserId,
    String? reportId,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/moderation/sanctions',
      {
        'target_user_id': targetUserId,
        'sanction_type': sanctionType,
        'reason_code': reasonCode,
        'reason': reason,
        'user_notice': userNotice,
        'duration_days': durationDays,
        'other_user_id': ?otherUserId,
        'report_id': ?reportId,
      },
    );
    _check(response, _decode(response));
  }

  static Future<void> revokeModerationSanction(String sanctionId) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/moderation/sanctions/${Uri.encodeComponent(sanctionId)}/revoke',
      const {},
    );
    _check(response, _decode(response));
  }

  static Future<Map<String, dynamic>> proposePermanentBan({
    required String targetUserId,
    required String reason,
    String? reportId,
    String? proposalId,
    String? witnessUserId,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/moderation/permanent-ban-proposals',
      {
        'target_user_id': targetUserId,
        'reason': reason,
        'report_id': ?reportId,
        'proposal_id': ?proposalId,
        'witness_user_id': ?witnessUserId,
      },
    );
    final data = _decode(response);
    _check(response, data);
    return data ?? const {};
  }

  static Future<void> submitReportAppeal(
    String reportId,
    String details,
  ) async {
    final response = await ApiAuthService.postJson(
      '/api/reports/${Uri.encodeComponent(reportId)}/appeal',
      {'details': details},
    );
    _check(response, _decode(response));
  }

  static Future<void> decideReportAppeal(
    String reportId, {
    required String decision,
    String notes = '',
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/admin/reports/${Uri.encodeComponent(reportId)}/appeal-decision',
      {'decision': decision, 'notes': notes},
    );
    _check(response, _decode(response));
  }

  static Future<void> submitReport({
    required String userId,
    required String reason,
    required String details,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/reports/${Uri.encodeComponent(userId)}',
      {'reason': reason, 'details': details},
    );
    _check(response, _decode(response));
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
            'The safety request could not be completed.',
      );
    }
  }
}
