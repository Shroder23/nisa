import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/server_config.dart';

class AgeEligibilityResult {
  final String eligibility;
  final String source;
  final int? age;
  const AgeEligibilityResult({
    required this.eligibility,
    required this.source,
    this.age,
  });
  bool get isEligible => eligibility == 'eligible';
  bool get isBlocked => eligibility == 'blocked';
}

class AgeEligibilityService {
  AgeEligibilityService._();
  static final _auth = FirebaseAuth.instance;
  static Future<AgeEligibilityResult> refreshCurrentUser() async {
    final u = _auth.currentUser;
    if (u == null) throw StateError('You must be signed in.');
    final token = await u.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Unable to obtain Firebase token.');
    }
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${ServerConfig.baseUrl}/api/age/refresh'),
            headers: {
              'Authorization': 'Bearer $token',
              'X-Nisa-Firebase-Token': token,
            },
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw StateError(
        'Age check timed out. Check the Nisa server connection.',
      );
    } on SocketException {
      throw StateError(
        'Cannot reach Nisa server. Check server, PC IP, Wi-Fi, and firewall.',
      );
    }
    Map<String, dynamic>? data;
    try {
      final d = jsonDecode(res.body);
      if (d is Map<String, dynamic>) data = d;
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = data?['detail'];
      throw StateError(
        detail is String
            ? detail
            : 'Age eligibility check failed (${res.statusCode}).',
      );
    }
    final raw = data?['age'];
    return AgeEligibilityResult(
      eligibility: data?['ageEligibility'] as String? ?? 'unknown',
      source: data?['ageSignalSource'] as String? ?? 'none',
      age: raw is num ? raw.toInt() : null,
    );
  }

  static Future<AgeEligibilityResult> updateDateOfBirth(
    DateTime dateOfBirth,
  ) async {
    final u = _auth.currentUser;
    if (u == null) {
      throw StateError('You must be signed in.');
    }

    final token = await u.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Unable to obtain Firebase token.');
    }

    final dob =
        '${dateOfBirth.year.toString().padLeft(4, '0')}-'
        '${dateOfBirth.month.toString().padLeft(2, '0')}-'
        '${dateOfBirth.day.toString().padLeft(2, '0')}';

    http.Response res;

    try {
      res = await http
          .post(
            Uri.parse('${ServerConfig.baseUrl}/api/age/update-dob'),
            headers: {'Authorization': 'Bearer $token'},
            body: {'date_of_birth': dob},
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw StateError(
        'Age update timed out. Check the Nisa server connection.',
      );
    } on SocketException {
      throw StateError(
        'Cannot reach Nisa server. Check server, internet, and firewall.',
      );
    }

    Map<String, dynamic>? data;

    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    } catch (_) {}

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = data?['detail'];
      throw StateError(
        detail is String ? detail : 'Age update failed (${res.statusCode}).',
      );
    }

    final rawAge = data?['age'];

    return AgeEligibilityResult(
      eligibility: data?['ageEligibility'] as String? ?? 'unknown',
      source: data?['ageSignalSource'] as String? ?? 'declared',
      age: rawAge is num ? rawAge.toInt() : null,
    );
  }
}
