import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_auth_service.dart';

class ApiPrivacySettings {
  final bool showOnlineStatus;
  final bool shareReadReceipts;

  const ApiPrivacySettings({
    this.showOnlineStatus = true,
    this.shareReadReceipts = true,
  });

  factory ApiPrivacySettings.fromMap(Map<String, dynamic> data) =>
      ApiPrivacySettings(
        showOnlineStatus: data['show_online_status'] != false,
        shareReadReceipts: data['share_read_receipts'] != false,
      );
}

class ApiPrivacyService {
  ApiPrivacyService._();

  static Future<ApiPrivacySettings> getSettings() async {
    final response = await ApiAuthService.get('/api/privacy/settings');
    final data = _decode(response);
    _check(response, data);
    final settings = data?['settings'];
    if (settings is! Map<String, dynamic>) {
      throw StateError('The server returned invalid privacy settings.');
    }
    return ApiPrivacySettings.fromMap(settings);
  }

  static Future<ApiPrivacySettings> updateSettings(
    ApiPrivacySettings settings,
  ) async {
    final response = await ApiAuthService.putJson('/api/privacy/settings', {
      'show_online_status': settings.showOnlineStatus,
      'share_read_receipts': settings.shareReadReceipts,
    });
    final data = _decode(response);
    _check(response, data);
    final saved = data?['settings'];
    if (saved is! Map<String, dynamic>) {
      throw StateError('The server returned invalid privacy settings.');
    }
    return ApiPrivacySettings.fromMap(saved);
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
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw StateError(
      data?['detail']?.toString() ?? 'Could not update privacy settings.',
    );
  }
}
