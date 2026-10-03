import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import 'age_eligibility_service.dart';

class FirestoreService {
  FirestoreService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final CollectionReference<Map<String, dynamic>> _users = _db
      .collection('users');

  static final CollectionReference<Map<String, dynamic>> _publicProfiles = _db
      .collection('public_profiles');

  static final CollectionReference<Map<String, dynamic>> _privateUsers = _db
      .collection('private_users');

  static final CollectionReference<Map<String, dynamic>> _preferences = _db
      .collection('preferences');

  // ============================================================
  // CREATE INITIAL USER RECORD
  // ============================================================

  static Future<void> createIncompleteUser({
    required String uid,
    required String accountType,
    String? email,
    String? phone,
  }) async {
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    batch.set(_users.doc(uid), {
      'uid': uid,
      'accountType': accountType,
      'status': 'onboarding',
      'accountState': 'onboarding',
      'profileComplete': false,

      // The next registration stage is Basic Profile.
      'registrationStep': 'basic_profile',
      'onboardingStep': 'basic_profile',

      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_privateUsers.doc(uid), {
      'uid': uid,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      'updatedAt': now,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ============================================================
  // SAVE BASIC PROFILE DRAFT
  // ============================================================

  static Future<void> saveBasicProfile(UserProfile profile) async {
    final uid = profile.uid;

    if (uid == null || uid.isEmpty) {
      throw StateError('Cannot save profile without Firebase UID.');
    }

    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    batch.set(_users.doc(uid), {
      'uid': uid,
      'accountType': profile.accountType,
      'status': 'onboarding',
      'accountState': 'onboarding',
      'profileComplete': false,
      'registrationStep': 'basic_profile',
      'onboardingStep': 'basic_profile',
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_publicProfiles.doc(uid), {
      ...profile.toPublicJson(),
      'uid': uid,
      'profileActive': false,
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_privateUsers.doc(uid), {
      ...profile.toPrivateJson(),
      'uid': uid,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await batch.commit();
    await AgeEligibilityService.refreshCurrentUser();
  }

  // ============================================================
  // GET ACCOUNT TYPE
  // ============================================================

  static Future<String> getAccountType(String uid) async {
    final snapshot = await _users.doc(uid).get();

    final data = snapshot.data();

    if (data == null) {
      return 'unverified';
    }

    return data['accountType'] as String? ?? 'unverified';
  }

  // ============================================================
  // GET REGISTRATION STEP
  // ============================================================

  static Future<String> getRegistrationStep(String uid) async {
    final snapshot = await _users.doc(uid).get();

    final data = snapshot.data();

    if (data == null) {
      return 'account';
    }

    return data['registrationStep'] as String? ?? 'account';
  }

  // ============================================================
  // SET REGISTRATION STEP
  // ============================================================

  static Future<void> setRegistrationStep({
    required String uid,
    required String step,
  }) async {
    final onboarding = step != 'complete';
    await _users.doc(uid).set({
      'registrationStep': step,
      'onboardingStep': step,
      'accountState': onboarding ? 'onboarding' : 'active',
      'status': onboarding ? 'onboarding' : 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<String> getAgeEligibility(String uid) async {
    final snapshot = await _users.doc(uid).get();
    final data = snapshot.data();
    return data?['ageEligibility'] as String? ?? 'unknown';
  }

  // ============================================================
  // CHECK PROFILE COMPLETION
  // ============================================================

  static Future<bool> isProfileComplete(String uid) async {
    final snapshot = await _users.doc(uid).get();

    final data = snapshot.data();

    if (data == null) {
      return false;
    }

    return data['profileComplete'] == true;
  }

  // ============================================================
  // MARK PROFILE COMPLETE
  // ============================================================

  static Future<void> markProfileComplete(String uid) async {
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(_users.doc(uid), {
      'status': 'active',
      'accountState': 'active',
      'profileComplete': true,
      'registrationStep': 'complete',
      'onboardingStep': 'complete',
      'updatedAt': now,
    }, SetOptions(merge: true));
    // The unverified completion route must also publish the profile. Without
    // this flag it is excluded by the discovery query.
    batch.set(_publicProfiles.doc(uid), {
      'uid': uid,
      'profileActive': true,
      'updatedAt': now,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  // ============================================================
  // SAVE FULL PROFILE
  // ============================================================

  static Future<void> createUserProfile(UserProfile profile) async {
    final uid = profile.uid;

    if (uid == null || uid.isEmpty) {
      throw StateError('Cannot create profile without Firebase UID.');
    }

    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    batch.set(_users.doc(uid), {
      'uid': uid,
      'accountType': profile.accountType,
      'status': 'onboarding',
      'accountState': 'onboarding',
      'profileComplete': false,

      // Profile Details has now been completed.
      'registrationStep': 'basic_profile',
      'onboardingStep': 'profile_details',

      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_publicProfiles.doc(uid), {
      ...profile.toPublicJson(),
      'uid': uid,
      'profileActive': false,
      'updatedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));

    batch.set(_privateUsers.doc(uid), {
      ...profile.toPrivateJson(),
      'uid': uid,
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_preferences.doc(uid), {
      ...profile.preferences.toJson(),
      'uid': uid,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ============================================================
  // COMPLETE PROFILE
  // ============================================================

  static Future<void> completeProfile(UserProfile profile) async {
    final uid = profile.uid;

    if (uid == null || uid.isEmpty) {
      throw StateError('Cannot complete profile without Firebase UID.');
    }

    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    batch.set(_users.doc(uid), {
      'uid': uid,
      'accountType': profile.accountType,
      'status': 'active',
      'accountState': 'active',
      'profileComplete': true,
      'registrationStep': 'complete',
      'onboardingStep': 'complete',
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_publicProfiles.doc(uid), {
      ...profile.toPublicJson(),
      'uid': uid,
      'profileActive': true,
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_privateUsers.doc(uid), {
      ...profile.toPrivateJson(),
      'uid': uid,
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_preferences.doc(uid), {
      ...profile.preferences.toJson(),
      'uid': uid,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ============================================================
  // LOAD USER PROFILE
  // ============================================================

  static Future<UserProfile?> loadUserProfile(String uid) async {
    final publicSnapshot = await _publicProfiles.doc(uid).get();

    if (!publicSnapshot.exists) {
      return null;
    }

    final privateSnapshot = await _privateUsers.doc(uid).get();

    final preferencesSnapshot = await _preferences.doc(uid).get();

    final data = <String, dynamic>{
      ...(publicSnapshot.data() ?? {}),
      ...(privateSnapshot.data() ?? {}),
      'preferences': preferencesSnapshot.data() ?? {},
    };

    return UserProfile.fromJson(data);
  }

  // ============================================================
  // UPDATE PROFILE
  // ============================================================

  static Future<void> updateUserProfile(UserProfile profile) async {
    final uid = profile.uid;

    if (uid == null || uid.isEmpty) {
      throw StateError('Cannot update profile without Firebase UID.');
    }

    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    batch.set(_publicProfiles.doc(uid), {
      ...profile.toPublicJson(),
      'uid': uid,
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_privateUsers.doc(uid), {
      ...profile.toPrivateJson(),
      'uid': uid,
      'updatedAt': now,
    }, SetOptions(merge: true));

    batch.set(_preferences.doc(uid), {
      ...profile.preferences.toJson(),
      'uid': uid,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ============================================================
  // WATCH PROFILE
  // ============================================================

  static Stream<UserProfile?> watchUserProfile(String uid) {
    return _publicProfiles
        .doc(uid)
        .snapshots()
        .asyncMap((_) => loadUserProfile(uid));
  }
}
