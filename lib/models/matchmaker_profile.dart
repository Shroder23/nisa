class MatchmakerProfile {
  const MatchmakerProfile({
    this.id,
    required this.fullName,
    required this.gender,
    this.age,
    this.city = '',
    this.country = 'Pakistan',
    this.height = '',
    this.maritalStatus = '',
    this.education = '',
    this.profession = '',
    this.religion = 'Islam',
    this.sect = '',
    this.phone = '',
    this.email = '',
    this.partnerPreferences = '',
    this.notes = '',
    this.consentStatus = 'pending',
    this.verificationStatus = 'unverified',
    this.visibility = 'private',
    this.externalReference = '',
  });

  final String? id;
  final String fullName;
  final String gender;
  final int? age;
  final String city;
  final String country;
  final String height;
  final String maritalStatus;
  final String education;
  final String profession;
  final String religion;
  final String sect;
  final String phone;
  final String email;
  final String partnerPreferences;
  final String notes;
  final String consentStatus;
  final String verificationStatus;
  final String visibility;
  final String externalReference;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'full_name': fullName,
    'gender': gender,
    'age': age,
    'city': city,
    'country': country,
    'height': height,
    'marital_status': maritalStatus,
    'education': education,
    'profession': profession,
    'religion': religion,
    'sect': sect,
    'phone': phone,
    'email': email,
    'partner_preferences': partnerPreferences,
    'notes': notes,
    'consent_status': consentStatus,
    'verification_status': verificationStatus,
    'visibility': visibility,
    'external_reference': externalReference,
  };

  factory MatchmakerProfile.fromJson(Map<String, dynamic> json) =>
      MatchmakerProfile(
        id: json['id']?.toString(),
        fullName: (json['full_name'] ?? json['name'] ?? '').toString(),
        gender: (json['gender'] ?? '').toString(),
        age: int.tryParse(json['age']?.toString() ?? ''),
        city: (json['city'] ?? '').toString(),
        country: (json['country'] ?? 'Pakistan').toString(),
        height: (json['height'] ?? '').toString(),
        maritalStatus: (json['marital_status'] ?? '').toString(),
        education: (json['education'] ?? '').toString(),
        profession: (json['profession'] ?? '').toString(),
        religion: (json['religion'] ?? 'Islam').toString(),
        sect: (json['sect'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        partnerPreferences: (json['partner_preferences'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
        consentStatus: (json['consent_status'] ?? 'pending').toString(),
        verificationStatus: (json['verification_status'] ?? 'unverified')
            .toString(),
        visibility: (json['visibility'] ?? 'private').toString(),
        externalReference: (json['external_reference'] ?? '').toString(),
      );
}
