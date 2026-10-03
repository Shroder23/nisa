import 'package:cloud_firestore/cloud_firestore.dart';

enum FamilyInvitationStatus {
  pending,
  emailConfirmed,
  accepted,
  declined,
  cancelled,
}

class FamilyInvitation {
  final String id;
  final String ownerUid;
  final String ownerName;
  final String familyMemberId;
  final String inviteeName;
  final String role;
  final String email;
  final String phone;
  final String contactKey;
  final String? inviteeUid;
  final FamilyInvitationStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const FamilyInvitation({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.familyMemberId,
    required this.inviteeName,
    required this.role,
    required this.email,
    required this.phone,
    required this.contactKey,
    required this.inviteeUid,
    required this.status,
    required this.createdAt,
    required this.respondedAt,
  });

  factory FamilyInvitation.fromMap(String id, Map<String, dynamic> data) {
    DateTime? asDate(dynamic value) =>
        value is Timestamp ? value.toDate() : null;

    return FamilyInvitation(
      id: id,
      ownerUid: data['ownerUid'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? 'Nisa Member',
      familyMemberId: data['familyMemberId'] as String? ?? '',
      inviteeName: data['inviteeName'] as String? ?? '',
      role: data['role'] as String? ?? 'other',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      contactKey: data['contactKey'] as String? ?? '',
      inviteeUid: data['inviteeUid'] as String?,
      status: FamilyInvitationStatus.values.firstWhere(
        (value) => value.name == data['status'],
        orElse: () => FamilyInvitationStatus.pending,
      ),
      createdAt: asDate(data['createdAt']) ?? DateTime.now(),
      respondedAt: asDate(data['respondedAt']),
    );
  }
}
