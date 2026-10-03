import '../models/candidate_profile.dart';
import '../models/discovery_filters.dart';
import '../models/user_profile.dart';
import 'candidate_service.dart';
import 'location_service.dart';

class DiscoveryService {
  DiscoveryService._();

  static final Map<String, DiscoveryFilters> _sessionFilters = {};

  static DiscoveryFilters? sessionFiltersFor(String? uid) {
    if (uid == null || uid.trim().isEmpty) return null;
    return _sessionFilters[uid];
  }

  static void saveSessionFilters(String? uid, DiscoveryFilters filters) {
    if (uid == null || uid.trim().isEmpty) return;
    _sessionFilters[uid] = filters;
  }

  static void clearSessionFilters(String? uid) {
    if (uid == null || uid.trim().isEmpty) return;
    _sessionFilters.remove(uid);
  }

  static Future<List<CandidateProfile>> _eligiblePool(
    UserProfile currentUser, {
    int limit = 100,
  }) async {
    final uid = currentUser.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('You are not signed in.');
    }

    String? oppositeGender;
    if (currentUser.gender == 'Male') {
      oppositeGender = 'Female';
    } else if (currentUser.gender == 'Female') {
      oppositeGender = 'Male';
    }

    return CandidateService.getEligiblePool(
      currentUserId: uid,
      gender: oppositeGender,
      limit: limit,
    );
  }

  static Future<DiscoveryFilterOptions> loadFilterOptions({
    required UserProfile currentUser,
  }) async {
    final pool = await _eligiblePool(currentUser);

    final countries = <String>{};
    final citiesByCountry = <String, Set<String>>{};
    final maritalStatuses = <String>{'Never Married', 'Divorced', 'Widowed'};

    for (final candidate in pool) {
      final country = candidate.country.trim();
      final city = candidate.city.trim();
      final marital = candidate.maritalStatus.trim();

      if (country.isNotEmpty) {
        countries.add(country);
        if (city.isNotEmpty) {
          citiesByCountry.putIfAbsent(country, () => <String>{}).add(city);
        }
      } else if (city.isNotEmpty) {
        citiesByCountry.putIfAbsent('', () => <String>{}).add(city);
      }

      if (marital.isNotEmpty) {
        maritalStatuses.add(_displayMarital(marital));
      }
    }

    final sortedCountries = countries.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final sortedMarital = maritalStatuses.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final map = <String, List<String>>{};

    for (final entry in citiesByCountry.entries) {
      final values = entry.value.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      map[entry.key] = values;
    }

    return DiscoveryFilterOptions(
      countries: sortedCountries,
      citiesByCountry: map,
      maritalStatuses: sortedMarital,
      educationLevels: List<String>.from(LocationService.educationOptions),
    );
  }

  static Future<List<DiscoveryResult>> discover({
    required UserProfile currentUser,
    required DiscoveryFilters filters,
    int limit = 100,
  }) async {
    final pool = await _eligiblePool(currentUser, limit: limit);
    final results = <DiscoveryResult>[];

    for (final candidate in pool) {
      if (candidate.age < filters.minimumAge ||
          candidate.age > filters.maximumAge) {
        continue;
      }
      if (!_matchesLocation(
        country: filters.country,
        city: filters.city,
        actualCountry: candidate.country,
        actualCity: candidate.city,
      )) {
        continue;
      }
      if (!_matchesMarital(filters.maritalStatus, candidate.maritalStatus)) {
        continue;
      }
      if (!_matchesEducation(filters.education, candidate.education)) {
        continue;
      }
      if (filters.verifiedOnly && !candidate.verified) continue;
      if (!_heightMatches(
        candidate.height,
        filters.minimumHeight,
        filters.maximumHeight,
      )) {
        continue;
      }

      final compatibility = compatibilityFor(currentUser, candidate);
      results.add(
        DiscoveryResult(candidate: candidate, compatibility: compatibility),
      );
    }

    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      if (a.candidate.verified != b.candidate.verified) {
        return a.candidate.verified ? -1 : 1;
      }
      return a.candidate.name.toLowerCase().compareTo(
        b.candidate.name.toLowerCase(),
      );
    });

    return results;
  }

  static CompatibilityAssessment compatibilityFor(
    UserProfile user,
    CandidateProfile candidate,
  ) {
    final preferences = user.preferences;
    var matchedWeight = 0;
    var possibleWeight = 0;
    final strengths = <String>[];
    final differences = <String>[];

    void evaluate({
      required int weight,
      required bool isSpecified,
      required bool matches,
      required String strength,
      required String difference,
    }) {
      if (!isSpecified) return;

      possibleWeight += weight;

      if (matches) {
        matchedWeight += weight;
        strengths.add(strength);
      } else {
        differences.add(difference);
      }
    }

    evaluate(
      weight: 30,
      isSpecified: true,
      matches:
          candidate.age >= preferences.minimumAge &&
          candidate.age <= preferences.maximumAge,
      strength: 'Preferred age range',
      difference: 'Outside your preferred age range',
    );

    evaluate(
      weight: 20,
      isSpecified: _specified(preferences.country),
      matches: _same(preferences.country, candidate.country),
      strength: 'Preferred country',
      difference: 'Different country preference',
    );

    evaluate(
      weight: 15,
      isSpecified: _specified(preferences.city),
      matches: _same(preferences.city, candidate.city),
      strength: 'Preferred city',
      difference: 'Different city preference',
    );

    evaluate(
      weight: 15,
      isSpecified: _specified(preferences.maritalStatus),
      matches: _matchesMarital(
        preferences.maritalStatus,
        candidate.maritalStatus,
      ),
      strength: 'Preferred marital status',
      difference: 'Different marital status preference',
    );

    evaluate(
      weight: 10,
      isSpecified: _specified(preferences.education),
      matches: _matchesEducation(preferences.education, candidate.education),
      strength: 'Preferred education',
      difference: 'Different education preference',
    );

    evaluate(
      weight: 10,
      isSpecified: _specified(preferences.religiousPractice),
      matches: _same(
        preferences.religiousPractice,
        candidate.religiousPractice,
      ),
      strength: 'Religious practice preference',
      difference: 'Different religious practice preference',
    );

    final percentage = possibleWeight == 0
        ? 0
        : ((matchedWeight / possibleWeight) * 100).round();

    return CompatibilityAssessment(
      percentage: percentage.clamp(0, 100).toInt(),
      matchedWeight: matchedWeight,
      possibleWeight: possibleWeight,
      strengths: strengths,
      differences: differences,
    );
  }

  static bool _specified(String? value) {
    final text = value?.trim().toLowerCase();

    return text != null &&
        text.isNotEmpty &&
        !_isAnyLocationValue(text) &&
        text != 'not specified' &&
        text != 'no preference';
  }

  static bool _matches(String? filter, String? actual) {
    final f = filter?.trim().toLowerCase();
    if (f == null || f.isEmpty || _isAnyLocationValue(f)) return true;
    final a = actual?.trim().toLowerCase();
    return a != null && a == f;
  }

  static bool _matchesLocation({
    required String? country,
    required String? city,
    required String? actualCountry,
    required String? actualCity,
  }) {
    // A selected city is always an exact city filter. If country is Any
    // country, deliberately ignore the country and search worldwide only by
    // that city.
    if (!_matches(city, actualCity)) return false;
    if (_isAnyLocationValue(country?.trim().toLowerCase() ?? '')) return true;
    return _matches(country, actualCountry);
  }

  static bool _isAnyLocationValue(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'any' ||
        normalized == 'any country' ||
        normalized == 'any city' ||
        normalized == 'any marital status';
  }

  static bool _matchesMarital(String? filter, String? actual) {
    final rawFilter = filter?.trim().toLowerCase();
    if (rawFilter == null ||
        rawFilter.isEmpty ||
        rawFilter == 'any' ||
        rawFilter == 'any marital status') {
      return true;
    }
    final f = _normalizeMarital(filter);
    if (f == null || f.isEmpty) return true;
    final a = _normalizeMarital(actual);
    return a != null && a == f;
  }

  static String? _normalizeMarital(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    if (text == 'single' ||
        text == 'never married' ||
        text == 'single (never married)') {
      return 'never married';
    }
    return text;
  }

  static String _displayMarital(String value) {
    final normalized = _normalizeMarital(value);
    if (normalized == 'never married') return 'Never Married';
    if (normalized == 'divorced') return 'Divorced';
    if (normalized == 'widowed') return 'Widowed';
    return value.trim();
  }

  static bool educationMeetsMinimum(String? minimum, String? actual) {
    return LocationService.educationMeetsMinimum(minimum, actual);
  }

  static bool _matchesEducation(String? filter, String? actual) =>
      educationMeetsMinimum(filter, actual);

  static bool _same(String? preferred, String? actual) {
    final p = preferred?.trim().toLowerCase();
    final a = actual?.trim().toLowerCase();
    if (p == null ||
        a == null ||
        p.isEmpty ||
        a.isEmpty ||
        _isAnyLocationValue(p)) {
      return false;
    }
    return p == a;
  }

  static double? _heightInches(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;

    // Stored profile heights normally use 5'8", but accept common legacy
    // spellings as well.
    final feetAndInches = RegExp(
      r'''^(\d+)\s*(?:ft|feet|foot|[\u0027’])\s*(\d{1,2})?\s*(?:in|inch|inches|["”])?\s*$''',
    ).firstMatch(text);
    if (feetAndInches != null) {
      final feet = int.parse(feetAndInches.group(1)!);
      final inches = int.tryParse(feetAndInches.group(2) ?? '0') ?? 0;
      if (inches > 11) return null;
      return (feet * 12 + inches).toDouble();
    }

    // A plain value in the normal human-height range is treated as inches.
    final inches = double.tryParse(text);
    if (inches != null && inches >= 36 && inches <= 120) return inches;
    return null;
  }

  static bool heightMeetsRange(String? actual, String? min, String? max) {
    final h = _heightInches(actual);
    final lo = _heightInches(min);
    final hi = _heightInches(max);

    // With no height preference, do not exclude profiles that have no height.
    if (lo == null && hi == null) return true;
    // With a selected range, an unknown height cannot be proven to be inside
    // that range and must therefore be excluded.
    if (h == null) return false;
    if (lo != null && hi != null && lo > hi) return false;
    return (lo == null || h >= lo) && (hi == null || h <= hi);
  }

  static bool _heightMatches(String? actual, String? min, String? max) =>
      heightMeetsRange(actual, min, max);
}
