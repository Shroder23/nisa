class CandidateProfile {
  final String id;
  final String name;
  final int age;
  final String gender;
  final String city;
  final String country;
  final String? education;
  final String? profession;
  final String? height;
  final String maritalStatus;
  final String? religiousPractice;
  final String? about;
  final bool verified;
  final bool verificationPending;
  final String? relocation;
  final bool ageEligible;
  final String? profilePhoto;
  final int photosCount;
  final int compatibilityScore;
  final List<String> recommendationReasons;
  final bool hasExistingInterest;
  final String? distanceBand;

  const CandidateProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.city,
    required this.country,
    this.education,
    this.profession,
    this.height,
    required this.maritalStatus,
    this.religiousPractice,
    this.about,
    required this.verified,
    this.verificationPending = false,
    this.relocation,
    this.ageEligible = false,
    this.profilePhoto,
    this.photosCount = 0,
    this.compatibilityScore = 0,
    this.recommendationReasons = const [],
    this.hasExistingInterest = false,
    this.distanceBand,
  });

  factory CandidateProfile.fromMap(String id, Map<String, dynamic> data) {
    final dateOfBirth = _parseDate(data['dateOfBirth']);
    final rawAge = data['age'];
    final age = rawAge is num
        ? rawAge.toInt()
        : dateOfBirth == null
        ? 0
        : _calculateAge(dateOfBirth);

    return CandidateProfile(
      id: id,
      name: data['name'] as String? ?? 'Nisa Member',
      age: age,
      gender: data['gender'] as String? ?? '',
      city: data['city'] as String? ?? '',
      country: data['country'] as String? ?? '',
      education: data['education'] as String?,
      profession: data['profession'] as String?,
      height: data['height'] as String?,
      maritalStatus: data['maritalStatus'] as String? ?? '',
      religiousPractice: data['religiousPractice'] as String?,
      about: (data['aboutMe'] as String?) ?? (data['about'] as String?),
      verified: data['isVerified'] as bool? ?? false,
      verificationPending: data['verificationPending'] as bool? ?? false,
      relocation: _normalizeRelocation(
        data['relocation'],
        data['willingToRelocate'],
      ),
      // Older public documents may not contain ageEligibility. An explicit
      // eligible flag is accepted, while the published age is the safe
      // fallback because dateOfBirth is intentionally private.
      ageEligible: data['ageEligibility'] == 'eligible' || age >= 18,
      profilePhoto: _firstPhotoUrl(data),
      photosCount: data['photosCount'] is num
          ? (data['photosCount'] as num).toInt()
          : 0,
      compatibilityScore: data['compatibilityScore'] is num
          ? (data['compatibilityScore'] as num).toInt()
          : 0,
      recommendationReasons: data['recommendationReasons'] is List
          ? (data['recommendationReasons'] as List).whereType<String>().toList(
              growable: false,
            )
          : const [],
      hasExistingInterest: data['hasExistingInterest'] as bool? ?? false,
      distanceBand: data['distanceBand'] as String?,
    );
  }

  static String? _firstPhotoUrl(Map<String, dynamic> data) {
    for (final key in const [
      'profilePhoto',
      'photoUrl',
      'photoURL',
      'imageUrl',
      'avatarUrl',
    ]) {
      final direct = data[key];
      if (direct is String && direct.trim().isNotEmpty) return direct.trim();
    }

    final photos = data['photos'];

    if (photos is List) {
      final directStrings = photos
          .whereType<String>()
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList();
      if (directStrings.isNotEmpty) return directStrings.first;

      final valid = photos.whereType<Map>().toList()
        ..sort((a, b) {
          final aOrder = a['order'] is num ? (a['order'] as num).toInt() : 0;
          final bOrder = b['order'] is num ? (b['order'] as num).toInt() : 0;
          return aOrder.compareTo(bOrder);
        });

      for (final photo in valid) {
        final url = photo['url'];
        if (url is String && url.trim().isNotEmpty) {
          return url.trim();
        }
      }
    }

    return null;
  }

  static String? _normalizeRelocation(dynamic relocation, dynamic legacyBool) {
    final value = relocation?.toString().trim();

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

    if (legacyBool == true) return 'Willing to relocate';
    if (legacyBool == false) return 'Not willing to relocate';

    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value;

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  static int _calculateAge(DateTime dateOfBirth) {
    final today = DateTime.now();

    var age = today.year - dateOfBirth.year;

    final hasHadBirthdayThisYear =
        today.month > dateOfBirth.month ||
        (today.month == dateOfBirth.month && today.day >= dateOfBirth.day);

    if (!hasHadBirthdayThisYear) {
      age--;
    }

    return age;
  }
}
