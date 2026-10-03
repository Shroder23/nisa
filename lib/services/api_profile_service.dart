import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/matrimonial_preferences.dart';
import '../models/candidate_profile.dart';
import '../models/user_profile.dart';
import 'api_auth_service.dart';
import 'location_service.dart';

/// Maps existing Flutter profile models to the PostgreSQL API contract.
class ApiProfileService {
  ApiProfileService._();

  static Future<UserProfile?> getMyProfile() async {
    final response = await ApiAuthService.get('/api/profiles/me');
    final data = _decodeMap(response);
    _checkResponse(response, data);
    if (data == null || data['user_id'] == null || data['full_name'] == null) {
      return null;
    }
    return _profileFromRow(data);
  }

  static Future<CandidateProfile> getPublicProfile(String userId) async {
    final response = await ApiAuthService.get(
      '/api/profiles/${Uri.encodeComponent(userId)}',
    );
    final row = _decodeMap(response);
    _checkResponse(response, row);
    if (row == null || row['user_id'] == null) {
      throw StateError('The server returned an invalid profile.');
    }
    return CandidateProfile.fromMap(row['user_id'].toString(), {
      'name': row['full_name'],
      'age': row['age'],
      'gender': row['gender'],
      'country': row['country'],
      'city': row['city'],
      'height': _heightFromCm(row['height_cm']),
      'maritalStatus': row['marital_status'],
      'religion': row['religion'],
      'sect': row['sect'],
      'education': row['education'],
      'profession': row['profession'],
      'religiousPractice': row['religious_practice'],
      'relocation': row['relocation_preference'],
      'profilePhoto': row['photo_url'],
      'isVerified': row['is_verified'],
      'verificationPending': row['verification_pending'],
      'ageEligibility': (row['age'] is num && (row['age'] as num) >= 18)
          ? 'eligible'
          : null,
    });
  }

  static Future<UserProfile> saveMyProfile(UserProfile profile) async {
    final payload = <String, dynamic>{
      'full_name': profile.name.trim(),
      'date_of_birth': _dateOnly(profile.dateOfBirth),
      'gender': profile.gender,
      'country': _nonEmpty(profile.country, 'Pakistan'),
      'city': _nonEmpty(profile.city, 'Karachi'),
      'height_cm': _heightToCm(profile.height),
      'marital_status': _nonEmpty(
        profile.maritalStatus,
        'Single (Never Married)',
      ),
      'religion': _nonEmpty(profile.religion, 'Islam'),
      'sect': _nonEmpty(profile.sect, 'Sunni'),
      'caste': profile.caste,
      'education': profile.education,
      'education_rank': profile.education == null
          ? null
          : LocationService.educationRank(profile.education!),
      'profession': profile.profession,
      'primary_language': _nonEmpty(profile.language, 'Urdu'),
      'religious_practice': _nonEmpty(profile.religiousPractice, 'Any'),
      'relocation_preference': _nonEmpty(profile.relocation, 'Maybe'),
    };
    final response = await ApiAuthService.putJson('/api/profiles/me', payload);
    final data = _decodeMap(response);
    _checkResponse(response, data);
    if (data == null) {
      throw StateError('The server returned an invalid profile response.');
    }
    return _profileFromRow(data);
  }

  static Future<String> uploadMyProfilePhoto(File photo) async {
    if (!await photo.exists()) {
      throw StateError('The selected profile photo could not be found.');
    }
    if (await photo.length() > 8 * 1024 * 1024) {
      throw StateError('Choose a profile photo that is 8 MB or smaller.');
    }
    final response = await ApiAuthService.postMultipart(
      '/api/profiles/me/photo',
      fields: const {},
      files: {'photo': photo},
    );
    final data = _decodeMap(response);
    _checkResponse(response, data);
    final photoUrl = data?['photo_url']?.toString();
    if (photoUrl == null || photoUrl.isEmpty) {
      throw StateError('The server did not return the uploaded profile photo.');
    }
    return photoUrl;
  }

  static Future<MatrimonialPreferences> getMyPreferences() async {
    final response = await ApiAuthService.get('/api/preferences/me');
    final data = _decodeMap(response);
    _checkResponse(response, data);
    if (data == null) {
      throw StateError('The server returned an invalid preferences response.');
    }
    return _preferencesFromRow(data);
  }

  static Future<MatrimonialPreferences> saveMyPreferences(
    MatrimonialPreferences preferences,
  ) async {
    final payload = <String, dynamic>{
      'min_age': preferences.minimumAge,
      'max_age': preferences.maximumAge,
      'min_height_cm': _heightToCm(preferences.minimumHeight),
      'max_height_cm': _heightToCm(preferences.maximumHeight),
      'preferred_country': _nonEmpty(preferences.country, 'Pakistan'),
      'preferred_city': _nonEmpty(preferences.city, 'Karachi'),
      'preferred_marital_status': _nonEmpty(
        preferences.maritalStatus,
        'Single (Never Married)',
      ),
      'minimum_education': preferences.education,
      'minimum_education_rank': preferences.education == null
          ? null
          : LocationService.educationRank(preferences.education!),
      'preferred_religion': 'Islam',
      'preferred_religious_practice': _nonEmpty(
        preferences.religiousPractice,
        'Any',
      ),
      'relocation_preference': _nonEmpty(
        preferences.relocationPreference,
        'Maybe',
      ),
    };
    final response = await ApiAuthService.putJson(
      '/api/preferences/me',
      payload,
    );
    final data = _decodeMap(response);
    _checkResponse(response, data);
    if (data == null) {
      throw StateError('The server returned an invalid preferences response.');
    }
    return _preferencesFromRow(data);
  }

  static UserProfile _profileFromRow(Map<String, dynamic> row) {
    final preferences = _preferencesFromRow(row);
    return UserProfile.fromJson({
      'uid': row['user_id'] ?? row['id'],
      'accountType': row['account_type'] ?? 'unverified',
      'name': row['full_name'] ?? row['display_name'] ?? '',
      'gender': row['gender'] ?? '',
      'dateOfBirth': row['date_of_birth'],
      'city': row['city'] ?? 'Karachi',
      'maritalStatus': row['marital_status'] ?? 'Single (Never Married)',
      'country': row['country'] ?? 'Pakistan',
      'height': _heightFromCm(row['height_cm']),
      'education': row['education'],
      'profession': row['profession'],
      'religion': row['religion'] ?? 'Islam',
      'sect': row['sect'] ?? 'Sunni',
      'caste': row['caste'],
      'religiousPractice': row['religious_practice'] ?? 'Any',
      'language': row['primary_language'] ?? 'Urdu',
      'relocation': row['relocation_preference'] ?? 'Maybe',
      'profilePhoto': row['photo_url'],
      'isVerified': row['is_verified'] ?? false,
      'verificationPending': row['verification_pending'] ?? false,
      'preferences': preferences.toJson(),
      'email': row['email'],
    });
  }

  static MatrimonialPreferences _preferencesFromRow(Map<String, dynamic> row) =>
      MatrimonialPreferences.fromJson({
        'minimumAge': row['min_age'],
        'maximumAge': row['max_age'],
        'minimumHeight': _heightFromCm(row['min_height_cm']),
        'maximumHeight': _heightFromCm(row['max_height_cm']),
        'country': row['preferred_country'],
        'city': row['preferred_city'],
        'maritalStatus': row['preferred_marital_status'],
        'education': row['minimum_education'],
        'religiousPractice': row['preferred_religious_practice'],
        'relocationPreference': row['relocation_preference'],
      });

  static int? _heightToCm(String? value) {
    final text = value?.trim() ?? '';
    final match = RegExp(r'''^(\d+)\s*'\s*(\d+)\s*"?$''').firstMatch(text);
    if (match == null) return null;
    final feet = int.tryParse(match.group(1)!);
    final inches = int.tryParse(match.group(2)!);
    if (feet == null || inches == null || inches > 11) return null;
    return (((feet * 12) + inches) * 2.54).round();
  }

  static String? _heightFromCm(dynamic value) {
    if (value is! num || value <= 0) return null;
    final totalInches = (value / 2.54).round();
    return "${totalInches ~/ 12}'${totalInches % 12}\"";
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _nonEmpty(String? value, String fallback) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  static Map<String, dynamic>? _decodeMap(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static void _checkResponse(
    http.Response response,
    Map<String, dynamic>? data,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw StateError(
      data?['detail']?.toString() ?? 'Unable to save your profile.',
    );
  }
}
