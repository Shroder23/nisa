import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import 'api_app_state.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'profile_storage.dart';

class AppState {
  static UserProfile? currentUser;

  static User? get firebaseUser {
    if (Firebase.apps.isEmpty) return null;
    return FirebaseAuth.instance.currentUser;
  }

  static bool get isSignedIn {
    if (ApiAppState.isSignedIn) return true;
    return firebaseUser != null;
  }

  static Future<void> setUser(UserProfile profile) async {
    if (ApiAppState.isSignedIn) {
      final saved = await ApiAppState.saveProfile(profile);
      await ApiAppState.savePreferences(profile.preferences);
      currentUser = saved;
      await ProfileStorage.saveProfile(saved);
      return;
    }

    currentUser = profile;

    await ProfileStorage.saveProfile(profile);

    final uid = profile.uid;

    if (uid != null && uid.isNotEmpty) {
      try {
        await FirestoreService.updateUserProfile(profile);
      } catch (error) {
        // Local-first onboarding: retain the draft and retry on a later
        // launch instead of blocking the user on a transient network error.
        debugPrint('Profile sync deferred: $error');
      }
    }
  }

  static Future<void> loadUser() async {
    if (ApiAppState.isSignedIn) {
      final apiProfile = await ApiAppState.restore();
      currentUser = apiProfile;
      if (apiProfile != null) await ProfileStorage.saveProfile(apiProfile);
      return;
    }

    final user = firebaseUser;

    if (user == null) {
      final apiProfile = await ApiAppState.restore();
      currentUser = apiProfile;
      if (apiProfile != null) await ProfileStorage.saveProfile(apiProfile);
      return;
    }

    UserProfile? cloudProfile;
    try {
      cloudProfile = await FirestoreService.loadUserProfile(user.uid);
    } catch (_) {
      // A temporary TLS/server failure must not discard an unfinished local
      // registration draft. The router can reopen Basic Profile from this
      // cached copy and sync it after the connection returns.
      final cachedProfile = await ProfileStorage.loadProfile();
      if (cachedProfile != null && cachedProfile.uid == user.uid) {
        currentUser = cachedProfile;
        return;
      }
      rethrow;
    }

    if (cloudProfile != null) {
      currentUser = cloudProfile;

      await ProfileStorage.saveProfile(cloudProfile);

      return;
    }

    // A missing cloud document can occur while a newly-created Auth account
    // is still being initialized. Preserve a matching local draft.
    final cachedProfile = await ProfileStorage.loadProfile();
    if (cachedProfile != null && cachedProfile.uid == user.uid) {
      currentUser = cachedProfile;
      return;
    }

    currentUser = null;
  }

  static Future<bool> isProfileComplete() async {
    if (ApiAppState.isSignedIn) {
      final account = ApiAppState.currentAccount;
      return account?['account_status'] == 'active' ||
          account?['registration_step'] == 'complete';
    }

    final user = firebaseUser;

    if (user == null) {
      return false;
    }

    return FirestoreService.isProfileComplete(user.uid);
  }

  static Future<String> getRegistrationStep() async {
    if (ApiAppState.isSignedIn) {
      return ApiAppState.currentAccount?['registration_step']?.toString() ??
          'basic_profile';
    }

    final user = firebaseUser;

    if (user == null) {
      return 'account';
    }

    return FirestoreService.getRegistrationStep(user.uid);
  }

  static Future<void> clearUser() async {
    // Clear either session provider if present.
    if (ApiAppState.isSignedIn) await ApiAppState.signOut();
    if (Firebase.apps.isNotEmpty && firebaseUser != null) {
      await AuthService.signOut();
    }
    currentUser = null;
    try {
      await ProfileStorage.deleteProfile();
    } catch (_) {
      debugPrint('Signed out; local profile cache cleanup failed.');
    }
  }
}
