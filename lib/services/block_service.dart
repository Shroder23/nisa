import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_block.dart';

class BlockService {
  BlockService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _blocks =>
      _db.collection('blocks');

  static String blockId(String blockerId, String blockedId) =>
      '${blockerId}_$blockedId';

  static Future<void> blockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    if (blockerId.isEmpty || blockedId.isEmpty) {
      throw StateError('Unable to identify the users.');
    }
    if (blockerId == blockedId) {
      throw StateError('You cannot block yourself.');
    }

    await _blocks.doc(blockId(blockerId, blockedId)).set({
      'blockerId': blockerId,
      'blockedId': blockedId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> unblockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    await _blocks.doc(blockId(blockerId, blockedId)).delete();
  }

  static Future<bool> hasBlocked({
    required String blockerId,
    required String blockedId,
  }) async {
    if (blockerId.isEmpty || blockedId.isEmpty) return false;
    final doc = await _blocks.doc(blockId(blockerId, blockedId)).get();
    return doc.exists;
  }

  static Future<bool> isBlockedBetween(String userA, String userB) async {
    if (userA.isEmpty || userB.isEmpty || userA == userB) return false;
    final results = await Future.wait([
      _blocks.doc(blockId(userA, userB)).get(),
      _blocks.doc(blockId(userB, userA)).get(),
    ]);
    return results.any((doc) => doc.exists);
  }

  static Future<Set<String>> blockedUserIds(String userId) async {
    if (userId.isEmpty) return <String>{};
    final snapshot = await _blocks.where('blockerId', isEqualTo: userId).get();
    return snapshot.docs
        .map((doc) => doc.data()['blockedId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static Future<Set<String>> usersWhoBlockedMe(String userId) async {
    if (userId.isEmpty) return <String>{};
    final snapshot = await _blocks.where('blockedId', isEqualTo: userId).get();
    return snapshot.docs
        .map((doc) => doc.data()['blockerId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static Stream<List<UserBlock>> watchMyBlocks(String userId) {
    if (userId.isEmpty) return Stream.value(const <UserBlock>[]);
    return _blocks.where('blockerId', isEqualTo: userId).snapshots().map((
      snapshot,
    ) {
      final blocks = snapshot.docs
          .map((doc) => UserBlock.fromMap(doc.id, doc.data()))
          .toList();
      blocks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return blocks;
    });
  }

  /// Emits both users blocked by [userId] and users who blocked [userId].
  ///
  /// This is intentionally live: Matches, Search, and other relationship
  /// surfaces can hide a user immediately after a block and restore them
  /// immediately after an unblock without deleting the underlying match.
  static Stream<Set<String>> watchBlockedUserIds(String userId) {
    if (userId.isEmpty) return Stream.value(const <String>{});

    return Stream.multi((controller) {
      var blockedByMe = <String>{};
      var blockedMe = <String>{};

      void emit() {
        controller.add({...blockedByMe, ...blockedMe});
      }

      final outgoing = _blocks
          .where('blockerId', isEqualTo: userId)
          .snapshots()
          .listen((snapshot) {
            blockedByMe = snapshot.docs
                .map((doc) => doc.data()['blockedId'] as String? ?? '')
                .where((id) => id.isNotEmpty)
                .toSet();
            emit();
          }, onError: controller.addError);

      final incoming = _blocks
          .where('blockedId', isEqualTo: userId)
          .snapshots()
          .listen((snapshot) {
            blockedMe = snapshot.docs
                .map((doc) => doc.data()['blockerId'] as String? ?? '')
                .where((id) => id.isNotEmpty)
                .toSet();
            emit();
          }, onError: controller.addError);

      controller.onCancel = () async {
        await Future.wait([outgoing.cancel(), incoming.cancel()]);
      };
    });
  }
}
