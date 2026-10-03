import 'package:cloud_firestore/cloud_firestore.dart';

enum VerificationRequestStatus { pending, approved, rejected, cancelled }

class VerificationRequest {
  final String id;
  final String userId;
  final String guardianMemberId;
  final String guardianName;
  final String guardianRole;
  final String rejectionReason;
  final VerificationRequestStatus status;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  const VerificationRequest({
    required this.id,
    required this.userId,
    required this.guardianMemberId,
    required this.guardianName,
    required this.guardianRole,
    required this.rejectionReason,
    required this.status,
    required this.submittedAt,
    required this.reviewedAt,
  });

  factory VerificationRequest.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return VerificationRequest(
      id: id,
      userId: data['userId'] as String? ?? '',
      guardianMemberId: data['guardianMemberId'] as String? ?? '',
      guardianName: data['guardianName'] as String? ?? '',
      guardianRole: data['guardianRole'] as String? ?? '',
      rejectionReason: data['rejectionReason'] as String? ?? '',
      status: _status(data['status'] as String?),
      submittedAt: _date(data['submittedAt']),
      reviewedAt: _date(data['reviewedAt']),
    );
  }

  static VerificationRequestStatus _status(String? status) {
    switch (status) {
      case 'approved':
        return VerificationRequestStatus.approved;
      case 'rejected':
        return VerificationRequestStatus.rejected;
      case 'cancelled':
        return VerificationRequestStatus.cancelled;
      case 'pending':
      default:
        return VerificationRequestStatus.pending;
    }
  }

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
