import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/matrimonial_preferences.dart';
import '../models/user_profile.dart';
import 'api_auth_service.dart';
import 'api_profile_service.dart';
import 'api_safety_service.dart';

class ApiAccountRestrictionException implements Exception {
  const ApiAccountRestrictionException({
    required this.notice,
    required this.expiresAt,
  });

  final String notice;
  final DateTime expiresAt;
}

/// Session and profile coordinator for the PostgreSQL-backed app flow.
///
/// It deliberately remains separate from AppState, which still owns the
/// Firebase session and Firestore synchronization for the current app flow.
class ApiAppState {
  ApiAppState._();

  static final ValueNotifier<UserProfile?> currentProfile =
      ValueNotifier<UserProfile?>(null);

  static Map<String, dynamic>? get currentAccount =>
      ApiAuthService.currentAccount.value;

  static bool get isSignedIn => currentAccount?['id'] != null;

  static Future<UserProfile?> restore() async {
    final account = await ApiAuthService.restoreAccount();
    if (account == null) {
      currentProfile.value = null;
      return null;
    }
    return loadCurrentProfile();
  }

  /// Loads profile data when ApiAuthService already holds a restored session.
  static Future<UserProfile?> loadCurrentProfile() async {
    final account = currentAccount;
    if (account == null) {
      currentProfile.value = null;
      return null;
    }

    UserProfile? profile;
    try {
      profile = await ApiProfileService.getMyProfile();
    } catch (error) {
      if (error is StateError) {
        try {
          final restrictions = await ApiSafetyService.getAccountRestrictions();
          for (final restriction in restrictions) {
            if (restriction['sanction_type'] != 'temporary_account_ban') {
              continue;
            }
            final notice = restriction['user_notice']?.toString().trim();
            final expiresAt = DateTime.tryParse(
              restriction['expires_at']?.toString() ?? '',
            );
            if (notice != null && notice.isNotEmpty && expiresAt != null) {
              throw ApiAccountRestrictionException(
                notice: notice,
                expiresAt: expiresAt,
              );
            }
          }
        } on ApiAccountRestrictionException {
          rethrow;
        } catch (_) {
          // Preserve the original profile request error if restrictions
          // cannot be loaded or no temporary account ban is active.
        }
      }
      rethrow;
    }
    if (profile == null) {
      final email = account['email']?.toString() ?? '';
      final name = account['display_name']?.toString() ?? '';
      currentProfile.value = UserProfile(
        uid: account['id']?.toString(),
        name: name,
        gender: '',
        dateOfBirth: DateTime(1900, 1, 1),
        city: 'Karachi',
        maritalStatus: 'Single (Never Married)',
        country: 'Pakistan',
        email: email,
      );
      return currentProfile.value;
    }

    profile.email = account['email']?.toString();
    profile.preferences = await ApiProfileService.getMyPreferences();
    currentProfile.value = profile;
    return profile;
  }

  static Future<UserProfile> saveProfile(UserProfile profile) async {
    final saved = await ApiProfileService.saveMyProfile(profile);
    final account = currentAccount;
    saved.email = account?['email']?.toString() ?? profile.email;
    saved.preferences = profile.preferences;
    currentProfile.value = saved;
    return saved;
  }

  static Future<MatrimonialPreferences> savePreferences(
    MatrimonialPreferences preferences,
  ) async {
    final saved = await ApiProfileService.saveMyPreferences(preferences);
    final profile = currentProfile.value;
    if (profile != null) {
      profile.preferences = saved;
      currentProfile.value = profile;
    }
    return saved;
  }

  static Future<Map<String, dynamic>> completeRegistration() async {
    final response = await ApiAuthService.postJson(
      '/api/registration/complete',
      const {},
    );
    Map<String, dynamic>? decoded;
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) decoded = value;
    } catch (_) {
      // The status code below supplies a safe fallback error.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded?['detail'];
      throw StateError(
        detail?.toString() ?? 'The server could not complete registration.',
      );
    }
    final user = decoded?['user'];
    if (user is! Map<String, dynamic>) {
      throw StateError('The server returned an invalid registration response.');
    }
    ApiAuthService.currentAccount.value = user;
    return user;
  }

  static Future<void> signOut() async {
    await ApiAuthService.signOut();
    currentProfile.value = null;
  }

  static Future<void> clearLocalSession() async {
    await ApiAuthService.clearSession();
    currentProfile.value = null;
  }
}
