class MatrimonialPreferences {
  int minimumAge;
  int maximumAge;
  String? minimumHeight;
  String? maximumHeight;

  String? country;
  String? city;
  String? maritalStatus;
  String? education;
  String? religiousPractice;

  String relocationPreference;

  MatrimonialPreferences({
    this.minimumAge = 18,
    this.maximumAge = 60,
    this.minimumHeight,
    this.maximumHeight,
    this.country,
    this.city,
    this.maritalStatus = 'Single (Never Married)',
    this.education = 'Intermediate / A-Level',
    this.religiousPractice = 'Any',
    this.relocationPreference = 'Maybe',
  });

  Map<String, dynamic> toJson() {
    return {
      'minimumAge': minimumAge,
      'maximumAge': maximumAge,
      'minimumHeight': minimumHeight,
      'maximumHeight': maximumHeight,
      'country': country,
      'city': city,
      'maritalStatus': maritalStatus,
      'education': education,
      'religiousPractice': religiousPractice,
      'relocationPreference': relocationPreference,
    };
  }

  static String _normalizeRelocationPreference(
    dynamic relocationPreference,
    dynamic legacyValue,
  ) {
    final value = relocationPreference?.toString().trim();

    switch (value) {
      case 'Willing to relocate':
      case 'Willing':
      case 'Yes':
        return 'Willing to relocate';

      case 'Not willing to relocate':
      case 'Not Willing':
      case 'No':
        return 'Not willing to relocate';

      case 'Maybe':
        return 'Maybe';
    }

    if (legacyValue == true) {
      return 'Willing to relocate';
    }

    if (legacyValue == false) {
      return 'Not willing to relocate';
    }

    return 'Willing to relocate';
  }

  factory MatrimonialPreferences.fromJson(Map<String, dynamic> json) {
    return MatrimonialPreferences(
      minimumAge: (json['minimumAge'] as num?)?.toInt() ?? 18,
      maximumAge: (json['maximumAge'] as num?)?.toInt() ?? 60,
      minimumHeight: json['minimumHeight'] as String?,
      maximumHeight: json['maximumHeight'] as String?,
      country: json['country'] as String?,
      city: json['city'] as String?,
      maritalStatus:
          (json['maritalStatus'] as String?)?.trim().isNotEmpty == true
          ? (json['maritalStatus'] as String).trim()
          : 'Single (Never Married)',
      education: (json['education'] as String?)?.trim().isNotEmpty == true
          ? (json['education'] as String).trim()
          : 'Intermediate / A-Level',
      religiousPractice:
          (json['religiousPractice'] as String?)?.trim().isNotEmpty == true
          ? (json['religiousPractice'] as String).trim()
          : 'Any',
      relocationPreference: _normalizeRelocationPreference(
        json['relocationPreference'],
        json['willingToRelocate'],
      ),
    );
  }
}
