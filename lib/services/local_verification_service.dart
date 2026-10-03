import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/server_config.dart';
import '../models/verification_request.dart';
import '../models/notification_item.dart';
import 'age_eligibility_service.dart';
import 'notification_service.dart';

class VerificationSubmissionResult {
  final String requestId;
  final String status;
  final bool verified;

  const VerificationSubmissionResult({
    required this.requestId,
    required this.status,
    required this.verified,
  });
}

class LocalVerificationService {
  LocalVerificationService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Stream<VerificationRequest?> watchLatestRequest() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    return _db
        .collection('verification_requests')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;

          final list = snapshot.docs
              .map(
                (doc) => VerificationRequest.fromFirestore(doc.id, doc.data()),
              )
              .toList();

          list.sort(
            (a, b) => (b.submittedAt ?? DateTime(1970)).compareTo(
              a.submittedAt ?? DateTime(1970),
            ),
          );

          return list.first;
        });
  }

  static Future<VerificationSubmissionResult> submit({
    required File idFile,
    required File videoFile,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in.');
    }

    if (!idFile.existsSync()) {
      throw StateError('Parent ID file was not found.');
    }

    if (!videoFile.existsSync()) {
      throw StateError('Parent video file was not found.');
    }

    // Resolve age before uploading private documents or a large video.
    // The server independently enforces the same requirement on submission.
    final eligibility = await AgeEligibilityService.refreshCurrentUser();
    if (!eligibility.isEligible) {
      throw StateError(
        eligibility.isBlocked
            ? 'You must be 18 or older to submit verification.'
            : 'We could not confirm your age. Your saved date of birth is '
                  'missing or invalid. Please contact support to correct your profile.',
      );
    }

    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Unable to obtain Firebase token.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ServerConfig.baseUrl}/api/verification/submit'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.headers['X-Nisa-Firebase-Token'] = token;
    request.files.add(
      await http.MultipartFile.fromPath(
        'parent_id',
        idFile.path,
        contentType: _mediaTypeForId(idFile.path),
      ),
    );

    request.files.add(
      await http.MultipartFile.fromPath(
        'confirmation_video',
        videoFile.path,
        contentType: _mediaTypeForVideo(videoFile.path),
      ),
    );

    http.StreamedResponse response;
    try {
      response = await request.send().timeout(const Duration(minutes: 4));
    } on TimeoutException {
      throw StateError('Upload timed out. Check the Nisa server connection.');
    } on SocketException {
      throw StateError(
        'Cannot reach Nisa server. Check server, PC IP, Wi-Fi, and firewall.',
      );
    }

    final body = await response.stream.bytesToString();
    Map<String, dynamic>? data;

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      data = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data?['detail'];
      throw StateError(
        detail is String ? detail : 'Upload failed (${response.statusCode}).',
      );
    }

    final requestId = data?['requestId'] as String? ?? '';
    final status = data?['status'] as String? ?? '';
    final verified = data?['verified'] == true;

    if (requestId.isEmpty) {
      throw StateError('Server returned no request ID.');
    }

    if (verified || status != 'pending') {
      throw StateError('Server returned an unexpected verification state.');
    }

    try {
      await NotificationService.create(
        recipientId: user.uid,
        type: NotificationType.verificationPending,
        title: 'Verification submitted',
        body: 'Your verification request is under review.',
        entityId: requestId,
      );
    } catch (_) {
      // Upload succeeded; notification persistence is non-fatal.
    }

    return VerificationSubmissionResult(
      requestId: requestId,
      status: status,
      verified: verified,
    );
  }

  static MediaType _mediaTypeForId(String path) {
    final lower = path.toLowerCase();

    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.pdf')) return MediaType('application', 'pdf');

    return MediaType('image', 'jpeg');
  }

  static MediaType _mediaTypeForVideo(String path) {
    final lower = path.toLowerCase();

    if (lower.endsWith('.mov')) return MediaType('video', 'quicktime');
    if (lower.endsWith('.m4v')) return MediaType('video', 'x-m4v');
    if (lower.endsWith('.webm')) return MediaType('video', 'webm');
    if (lower.endsWith('.3gp')) return MediaType('video', '3gpp');

    return MediaType('video', 'mp4');
  }
}
