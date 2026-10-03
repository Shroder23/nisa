import 'package:cloud_firestore/cloud_firestore.dart';

enum FamilyRole { father, mother, brother, sister, guardian, other }

enum FamilyInvitationStatus {
  pending,
  emailConfirmed,
  accepted,
  declined,
  cancelled,
}

class FamilyMember {
  final String id;
  final String ownerUid;
  final String name;
  final FamilyRole role;
  final String email;
  final String phone;
  final FamilyInvitationStatus invitationStatus;
  final String invitationId;
  final String? linkedUid;
  final DateTime createdAt;

  const FamilyMember({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.role,
    required this.email,
    required this.phone,
    required this.invitationStatus,
    required this.invitationId,
    required this.linkedUid,
    required this.createdAt,
  });

  factory FamilyMember.fromMap(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];

    return FamilyMember(
      id: id,
      ownerUid: data['ownerUid'] as String? ?? '',
      name: data['name'] as String? ?? '',
      role: FamilyRole.values.firstWhere(
        (value) => value.name == data['role'],
        orElse: () => FamilyRole.other,
      ),
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      invitationStatus: FamilyInvitationStatus.values.firstWhere(
        (value) => value.name == data['invitationStatus'],
        orElse: () => FamilyInvitationStatus.pending,
      ),
      invitationId: data['invitationId'] as String? ?? '',
      linkedUid: data['linkedUid'] as String?,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }
}
