import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

class ProfileStorage {
  static const String _profileKey = 'nisa_user_profile';

  static Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = jsonEncode(profile.toJson());

    await prefs.setString(_profileKey, jsonString);
  }

  static Future<UserProfile?> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonString = prefs.getString(_profileKey);

    if (jsonString == null) {
      return null;
    }

    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);

      return UserProfile.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteProfile() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_profileKey);
  }

  static Future<bool> hasProfile() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.containsKey(_profileKey);
  }
}
