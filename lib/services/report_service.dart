import 'package:cloud_firestore/cloud_firestore.dart';

class ReportService {
  ReportService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> submitReport({
    required String reporterId,
    required String reportedUserId,
    required String reason,
    String details = '',
  }) async {
    if (reporterId.isEmpty || reportedUserId.isEmpty) {
      throw StateError('Unable to identify the users.');
    }
    if (reporterId == reportedUserId) {
      throw StateError('You cannot report yourself.');
    }
    if (reason.trim().isEmpty) {
      throw StateError('Please select a reason.');
    }

    await _db.collection('reports').add({
      'reporterId': reporterId,
      'reportedUserId': reportedUserId,
      'reason': reason.trim(),
      'details': details.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
