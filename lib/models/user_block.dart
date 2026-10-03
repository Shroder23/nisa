import 'package:cloud_firestore/cloud_firestore.dart';

class UserBlock {
  final String id;
  final String blockerId;
  final String blockedId;
  final DateTime createdAt;

  const UserBlock({
    required this.id,
    required this.blockerId,
    required this.blockedId,
    required this.createdAt,
  });

  factory UserBlock.fromMap(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    return UserBlock(
      id: id,
      blockerId: data['blockerId'] as String? ?? '',
      blockedId: data['blockedId'] as String? ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }
}
