import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/candidate_profile.dart';
import '../models/discovery_filters.dart';
import '../models/user_profile.dart';
import 'location_service.dart';
import 'api_auth_service.dart';

class ApiDiscoveryPage {
  final List<CandidateProfile> profiles;
  final bool hasMore;

  const ApiDiscoveryPage({required this.profiles, required this.hasMore});
}

/// Reads the preference-matched recommendation feed from PostgreSQL.
class ApiDiscoveryService {
  ApiDiscoveryService._();

  static DiscoveryFilters defaultFiltersFor(
    UserProfile profile, {
    bool prioritizeNearby = false,
    int? maxDistanceMiles,
  }) {
    final preferences = profile.preferences;
    return DiscoveryFilters(
      minimumAge: preferences.minimumAge.clamp(18, 100),
      maximumAge: preferences.maximumAge.clamp(18, 100),
      minimumHeight: preferences.minimumHeight,
      maximumHeight: preferences.maximumHeight,
      country: preferences.country,
      city: preferences.city,
      maritalStatus: _canonicalMaritalFilter(preferences.maritalStatus),
      education: preferences.education,
      prioritizeNearby: prioritizeNearby,
      maxDistanceMiles: prioritizeNearby ? maxDistanceMiles : null,
    );
  }

  static Future<ApiDiscoveryPage> getRecommendations({
    required String currentGender,
    DiscoveryFilters? filters,
    int offset = 0,
    int limit = 50,
  }) async {
    final params = <String, String>{
      'offset': '$offset',
      'limit': '$limit',
      if (currentGender.trim().toLowerCase() == 'male')
        'target_gender': 'female',
      if (currentGender.trim().toLowerCase() == 'female')
        'target_gender': 'male',
      if (filters != null) ..._filterParameters(filters, currentGender),
    };
    final query = Uri(queryParameters: params).query;
    final response = await ApiAuthService.get(
      '/api/discovery/recommendations?$query',
    );
    final data = _decodeMap(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data?['detail']?.toString().trim();
      final diagnostic =
          (detail?.isNotEmpty == true ? detail! : response.body.trim())
              .replaceAll(RegExp(r'\s+'), ' ');
      final excerpt = diagnostic.length > 240
          ? '${diagnostic.substring(0, 240)}…'
          : diagnostic;
      throw StateError(
        'Could not load recommendations (HTTP ${response.statusCode})'
        '${excerpt.isEmpty ? '.' : ': $excerpt'}',
      );
    }

    final rows = data?['profiles'];
    if (rows is! List) {
      return const ApiDiscoveryPage(profiles: [], hasMore: false);
    }
    final hasMore = rows.length >= limit;
    final expectedGender = switch (currentGender.trim().toLowerCase()) {
      'male' => 'female',
      'female' => 'male',
      _ => null,
    };

    final profilesById = <String, CandidateProfile>{};
    for (final raw in rows.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final height = _heightFromCm(row['height_cm']);
      final candidate = CandidateProfile.fromMap(row['id']?.toString() ?? '', {
        'name': row['full_name'] ?? row['display_name'] ?? 'Nisa Member',
        'age': row['age'],
        'gender': row['gender'],
        'country': row['country'],
        'city': row['city'],
        'height': height,
        'maritalStatus': row['marital_status'],
        'education': row['education'],
        'profession': row['profession'],
        'profilePhoto': row['photo_url'],
        'isVerified': row['is_verified'],
        'compatibilityScore': row['compatibility_score'],
        'recommendationReasons': row['recommendation_reasons'],
        'hasExistingInterest': row['has_existing_interest'],
        'distanceBand': row['distance_band'],
      });
      if (candidate.id.isNotEmpty &&
          candidate.age >= 18 &&
          (expectedGender == null ||
              candidate.gender.trim().toLowerCase() == expectedGender)) {
        profilesById.putIfAbsent(candidate.id, () => candidate);
      }
    }
    final profiles = profilesById.values.toList(growable: false);
    return ApiDiscoveryPage(profiles: profiles, hasMore: hasMore);
  }

  static String? _canonicalMaritalFilter(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty || normalized.startsWith('any')) return null;
    if (normalized == 'single' ||
        normalized == 'never married' ||
        normalized == 'single (never married)') {
      return 'Single (Never Married)';
    }
    const supported = {'married', 'separated', 'divorced', 'widowed'};
    if (supported.contains(normalized)) {
      return normalized[0].toUpperCase() + normalized.substring(1);
    }
    return null;
  }

  static Map<String, String> _filterParameters(
    DiscoveryFilters filters,
    String currentGender,
  ) {
    String? anyOrValue(String? value, String anyValue) {
      final normalized = value?.trim() ?? '';
      if (normalized.isEmpty || normalized.toLowerCase().startsWith('any')) {
        return anyValue;
      }
      return normalized;
    }

    int? heightCm(String? value) {
      final match = RegExp(r"(\d+)\s*'\s*(\d+)")
          .firstMatch(value?.trim() ?? '');
      if (match == null) return null;
      final inches =
          int.parse(match.group(1)!) * 12 + int.parse(match.group(2)!);
      return (inches * 2.54).round();
    }

    final education = filters.education?.trim() ?? '';
    final isAnyEducation =
        education.isEmpty || education.toLowerCase().startsWith('any');
    final educationRank = LocationService.educationRank(education);
    final maritalStatus = filters.maritalStatus?.trim() ?? '';
    final normalizedMaritalStatus = switch (maritalStatus.toLowerCase()) {
      'single' ||
      'never married' ||
      'single (never married)' => 'Never Married',
      _ => maritalStatus,
    };
    return {
      'min_age': '${filters.minimumAge}',
      'max_age': '${filters.maximumAge}',
      if (heightCm(filters.minimumHeight) case final value?)
        'min_height_cm': '$value',
      if (heightCm(filters.maximumHeight) case final value?)
        'max_height_cm': '$value',
      if (!filters.prioritizeNearby || filters.locationScopeExplicit) ...{
        'country_filter': anyOrValue(filters.country, 'Any country')!,
        'city_filter': anyOrValue(filters.city, 'Any city')!,
      },
      'prioritize_nearby': '${filters.prioritizeNearby}',
      if (filters.prioritizeNearby && filters.maxDistanceMiles != null)
        'max_distance_miles': '${filters.maxDistanceMiles}',
      'marital_status_filter': anyOrValue(
        normalizedMaritalStatus,
        'Any marital status',
      )!,
      'minimum_education_rank': '${educationRank ?? 0}',
      if (!isAnyEducation && educationRank == null)
        'education_filter': LocationService.normalizeEducationCategory(
          education,
        ),
      'verified_only': '${filters.verifiedOnly}',
    };
  }

  static String? _heightFromCm(dynamic value) {
    if (value is! num || value <= 0) return null;
    final inches = (value / 2.54).round();
    return "${inches ~/ 12}'${inches % 12}\"";
  }

  static Map<String, dynamic>? _decodeMap(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }
}
