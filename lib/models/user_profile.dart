import 'matrimonial_preferences.dart';
import 'user_photo.dart';

class UserProfile {
  String? uid;
  String accountType;

  String name;
  String gender;
  DateTime dateOfBirth;
  String city;
  String maritalStatus;

  String? country;
  String? height;
  String? education;
  String? profession;
  String? religion;
  String? sect;
  String? caste;
  String? religiousPractice;
  String? language;
  String? relocation;
  String? aboutMe;

  String? profilePhoto;
  List<UserPhoto> photos;
  int photosCount;

  String? phone;
  String? email;

  bool isVerified;
  bool verificationPending;

  MatrimonialPreferences preferences;

  UserProfile({
    this.uid,
    this.accountType = 'unverified',
    required this.name,
    required this.gender,
    required this.dateOfBirth,
    required this.city,
    required this.maritalStatus,
    this.country,
    this.height,
    this.education,
    this.profession,
    this.religion,
    this.sect,
    this.caste,
    this.religiousPractice,
    this.language,
    this.relocation,
    this.aboutMe,
    this.profilePhoto,
    List<UserPhoto>? photos,
    this.photosCount = 0,
    this.phone,
    this.email,
    this.isVerified = false,
    this.verificationPending = false,
    MatrimonialPreferences? preferences,
  }) : photos = photos ?? <UserPhoto>[],
       preferences = preferences ?? MatrimonialPreferences();

  static String? _normalizeRelocation(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();

    switch (text) {
      case 'Yes':
      case 'Willing':
      case 'Willing to relocate':
        return 'Willing to relocate';

      case 'No':
      case 'Not Willing':
      case 'Not willing to relocate':
        return 'Not willing to relocate';

      case 'Maybe':
        return 'Maybe';

      default:
        return null;
    }
  }

  static DateTime _parseDateOfBirth(dynamic value) {
    if (value is DateTime) return value;

    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }

    // Defensive fallback only. Normal profiles should always have DOB in
    // private_users and local storage.
    return DateTime(1900, 1, 1);
  }

  static List<UserPhoto> _parsePhotos(dynamic value) {
    if (value is! List) return <UserPhoto>[];

    return value
        .whereType<Map>()
        .map((item) => UserPhoto.fromMap(Map<String, dynamic>.from(item)))
        .where((photo) => photo.url.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  Map<String, dynamic> toJson() {
    final photoMaps = photos.map((e) => e.toMap()).toList();

    return {
      'uid': uid,
      'accountType': accountType,
      'name': name,
      'gender': gender,
      'dateOfBirth': dateOfBirth.toIso8601String(),
      'city': city,
      'maritalStatus': maritalStatus,
      'country': country,
      'height': height,
      'education': education,
      'profession': profession,
      'religion': religion,
      'sect': sect,
      'caste': caste,
      'religiousPractice': religiousPractice,
      'language': language,
      'relocation': relocation,
      'aboutMe': aboutMe,
      'profilePhoto': profilePhoto,
      'photos': photoMaps,
      'photosCount': photosCount == 0 ? photoMaps.length : photosCount,
      'phone': phone,
      'email': email,
      'isVerified': isVerified,
      'verificationPending': verificationPending,
      'preferences': preferences.toJson(),
    };
  }

  Map<String, dynamic> toPublicJson() {
    final data = toJson();

    data.remove('email');
    data.remove('phone');
    data.remove('dateOfBirth');

    return data;
  }

  Map<String, dynamic> toPrivateJson() {
    return {
      'email': email,
      'phone': phone,
      'dateOfBirth': dateOfBirth.toIso8601String(),
      'profilePhoto': profilePhoto,
      'photosCount': photosCount,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final parsedPhotos = _parsePhotos(json['photos']);
    final parsedProfilePhoto = json['profilePhoto'] as String?;

    return UserProfile(
      uid: json['uid'],
      accountType: json['accountType'] ?? 'unverified',
      name: json['name'] ?? '',
      gender: json['gender'] ?? '',
      dateOfBirth: _parseDateOfBirth(json['dateOfBirth']),
      city: json['city'] ?? '',
      maritalStatus: json['maritalStatus'] ?? '',
      country: json['country'],
      height: json['height'],
      education: json['education'],
      profession: json['profession'],
      religion: json['religion'] as String? ?? 'Islam',
      sect: json['sect'] as String?,
      caste: json['caste'] as String?,
      religiousPractice: json['religiousPractice'],
      language: json['language'],
      relocation: _normalizeRelocation(json['relocation']),
      aboutMe: json['aboutMe'],
      profilePhoto:
          parsedProfilePhoto ??
          (parsedPhotos.isNotEmpty ? parsedPhotos.first.url : null),
      photos: parsedPhotos,
      photosCount: json['photosCount'] is num
          ? (json['photosCount'] as num).toInt()
          : parsedPhotos.length,
      phone: json['phone'],
      email: json['email'],
      isVerified: json['isVerified'] ?? false,
      verificationPending: json['verificationPending'] ?? false,
      preferences: json['preferences'] != null
          ? MatrimonialPreferences.fromJson(
              Map<String, dynamic>.from(json['preferences']),
            )
          : MatrimonialPreferences(),
    );
  }
}
