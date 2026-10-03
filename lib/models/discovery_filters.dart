import 'candidate_profile.dart';

class DiscoveryFilters {
  final int minimumAge;
  final int maximumAge;
  final String? minimumHeight;
  final String? maximumHeight;
  final String? country;
  final String? city;
  final String? maritalStatus;
  final String? education;
  final bool verifiedOnly;
  final bool prioritizeNearby;
  final int? maxDistanceMiles;
  final bool locationScopeExplicit;

  const DiscoveryFilters({
    required this.minimumAge,
    required this.maximumAge,
    this.minimumHeight,
    this.maximumHeight,
    this.country,
    this.city,
    this.maritalStatus,
    this.education,
    this.verifiedOnly = false,
    this.prioritizeNearby = false,
    this.maxDistanceMiles,
    this.locationScopeExplicit = false,
  });

  int get activeFilterCount {
    var count = 1;
    if (country?.trim().isNotEmpty == true) count++;
    if (city?.trim().isNotEmpty == true) count++;
    if (maritalStatus?.trim().isNotEmpty == true) count++;
    if (education?.trim().isNotEmpty == true) count++;
    if (verifiedOnly) count++;
    if (prioritizeNearby) count++;
    return count;
  }
}

class CompatibilityAssessment {
  final int percentage;
  final int matchedWeight;
  final int possibleWeight;
  final List<String> strengths;
  final List<String> differences;

  const CompatibilityAssessment({
    required this.percentage,
    required this.matchedWeight,
    required this.possibleWeight,
    required this.strengths,
    required this.differences,
  });

  String get label {
    if (percentage >= 85) return 'Strong alignment';
    if (percentage >= 70) return 'Good alignment';
    if (percentage >= 50) return 'Some alignment';
    return 'Limited alignment';
  }
}

class DiscoveryResult {
  final CandidateProfile candidate;
  final CompatibilityAssessment compatibility;

  const DiscoveryResult({required this.candidate, required this.compatibility});

  int get score => compatibility.percentage;
  List<String> get reasons => compatibility.strengths;
}

class DiscoveryFilterOptions {
  final List<String> countries;
  final Map<String, List<String>> citiesByCountry;
  final List<String> maritalStatuses;
  final List<String> educationLevels;

  const DiscoveryFilterOptions({
    required this.countries,
    required this.citiesByCountry,
    required this.maritalStatuses,
    required this.educationLevels,
  });

  List<String> citiesFor(String? country) {
    final normalized = country?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return citiesByCountry[normalized] ?? const [];
    }

    final cities = <String>{};
    for (final values in citiesByCountry.values) {
      cities.addAll(values);
    }
    final result = cities.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }
}
