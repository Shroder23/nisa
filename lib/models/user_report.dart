import 'package:cloud_firestore/cloud_firestore.dart';

class UserReport {
  final String id;
  final String reporterId;
  final String reportedUserId;
  final String reason;
  final String details;
  final String status;
  final DateTime createdAt;

  const UserReport({
    required this.id,
    required this.reporterId,
    required this.reportedUserId,
    required this.reason,
    required this.details,
    required this.status,
    required this.createdAt,
  });

  factory UserReport.fromMap(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    return UserReport(
      id: id,
      reporterId: data['reporterId'] as String? ?? '',
      reportedUserId: data['reportedUserId'] as String? ?? '',
      reason: data['reason'] as String? ?? '',
      details: data['details'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }
}
