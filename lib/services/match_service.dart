import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/match.dart';
import 'block_service.dart';

class MatchService {
  MatchService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('matches');

  static String matchIdFor(String userA, String userB) {
    final users = [userA, userB]..sort();
    return '${users[0]}_${users[1]}';
  }

  static Future<bool> areMatched(String userA, String userB) async {
    if (userA.isEmpty || userB.isEmpty || userA == userB) {
      return false;
    }

    final matchId = matchIdFor(userA, userB);

    // Query only matches owned by userA. This avoids a direct read of a
    // non-existent document, which participant-only Firestore rules deny.
    final snapshot = await _collection
        .where('participants', arrayContains: userA)
        .get();

    return snapshot.docs.any((doc) => doc.id == matchId);
  }

  static Future<MatrimonialMatch?> findMatch(String userA, String userB) async {
    if (userA.isEmpty || userB.isEmpty || userA == userB) {
      return null;
    }

    final doc = await _collection.doc(matchIdFor(userA, userB)).get();

    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;

    return _fromData(data, doc.id);
  }

  static Stream<List<MatrimonialMatch>> watchMatchesForUser(String userId) {
    if (userId.isEmpty) {
      return Stream.value(const <MatrimonialMatch>[]);
    }

    return Stream.multi((controller) {
      var allMatches = <MatrimonialMatch>[];
      var blockedUserIds = <String>{};

      void emitVisibleMatches() {
        final visible = allMatches.where((match) {
          final otherUserId = match.userA == userId ? match.userB : match.userA;
          return otherUserId.isNotEmpty &&
              !blockedUserIds.contains(otherUserId);
        }).toList();

        controller.add(visible);
      }

      final matchSubscription = _collection
          .where('participants', arrayContains: userId)
          .snapshots()
          .listen((snapshot) {
            allMatches =
                snapshot.docs
                    .map((doc) => _fromData(doc.data(), doc.id))
                    .toList()
                  ..sort((a, b) => b.matchedAt.compareTo(a.matchedAt));
            emitVisibleMatches();
          }, onError: controller.addError);

      final blockSubscription = BlockService.watchBlockedUserIds(userId)
          .listen((ids) {
            blockedUserIds = ids;
            emitVisibleMatches();
          }, onError: controller.addError);

      controller.onCancel = () async {
        await Future.wait([
          matchSubscription.cancel(),
          blockSubscription.cancel(),
        ]);
      };
    });
  }

  static Future<List<MatrimonialMatch>> matchesForUser(String userId) async {
    if (userId.isEmpty) return [];

    final snapshot = await _collection
        .where('participants', arrayContains: userId)
        .get();

    final matches = snapshot.docs
        .map((doc) => _fromData(doc.data(), doc.id))
        .where((match) {
          final otherUserId = match.userA == userId ? match.userB : match.userA;
          return otherUserId.isNotEmpty;
        })
        .toList();

    final blockedSets = await Future.wait([
      BlockService.blockedUserIds(userId),
      BlockService.usersWhoBlockedMe(userId),
    ]);
    final blockedUserIds = <String>{...blockedSets[0], ...blockedSets[1]};
    matches.removeWhere((match) {
      final otherUserId = match.userA == userId ? match.userB : match.userA;
      return blockedUserIds.contains(otherUserId);
    });

    matches.sort((a, b) => b.matchedAt.compareTo(a.matchedAt));

    return matches;
  }

  /// Creates a match after one incoming interest has been accepted.
  ///
  /// There is deliberately no pre-read of a missing match document.
  /// That lets Firestore keep match reads participant-only.
  static Future<MatrimonialMatch> createFromAcceptedInterest({
    required String senderId,
    required String receiverId,
  }) async {
    if (senderId.isEmpty || receiverId.isEmpty) {
      throw ArgumentError('Sender and receiver IDs cannot be empty.');
    }

    if (senderId == receiverId) {
      throw StateError('A user cannot match with themselves.');
    }

    final interestId = '${senderId}_$receiverId';

    final interestSnapshot = await _firestore
        .collection('interests')
        .doc(interestId)
        .get();

    if (!interestSnapshot.exists) {
      throw StateError('The interest no longer exists.');
    }

    final interestData = interestSnapshot.data();
    if (interestData == null) {
      throw StateError('The interest contains no data.');
    }

    if (interestData['senderId'] != senderId ||
        interestData['receiverId'] != receiverId) {
      throw StateError('Interest participants do not match.');
    }

    if (interestData['status'] != 'accepted') {
      throw StateError('The interest has not been accepted.');
    }

    final users = [senderId, receiverId]..sort();
    final matchId = '${users[0]}_${users[1]}';
    final matchRef = _collection.doc(matchId);

    try {
      await matchRef.set({
        'id': matchId,
        'userA': users[0],
        'userB': users[1],
        'participants': users,
        'matchedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('MatchService: created $matchId');

      return MatrimonialMatch(
        id: matchId,
        userA: users[0],
        userB: users[1],
        matchedAt: DateTime.now(),
      );
    } on FirebaseException {
      // If the deterministic match already exists, the write is treated as
      // an update and is intentionally denied by our rules. In that case,
      // reading the existing participant-owned match is safe and allowed.
      final existing = await matchRef.get();
      final data = existing.data();

      if (existing.exists && data != null) {
        debugPrint('MatchService: match already exists: $matchId');
        return _fromData(data, existing.id);
      }

      rethrow;
    }
  }

  static Future<MatrimonialMatch?> rebuildForPair(
    String userA,
    String userB,
  ) async {
    if (userA.isEmpty || userB.isEmpty || userA == userB) {
      return null;
    }

    final interestAB = await _firestore
        .collection('interests')
        .doc('${userA}_$userB')
        .get();

    if (interestAB.data()?['status'] == 'accepted') {
      return createFromAcceptedInterest(senderId: userA, receiverId: userB);
    }

    final interestBA = await _firestore
        .collection('interests')
        .doc('${userB}_$userA')
        .get();

    if (interestBA.data()?['status'] == 'accepted') {
      return createFromAcceptedInterest(senderId: userB, receiverId: userA);
    }

    return null;
  }

  static MatrimonialMatch _fromData(
    Map<String, dynamic> data,
    String documentId,
  ) {
    final timestamp = data['matchedAt'];

    DateTime matchedAt;
    if (timestamp is Timestamp) {
      matchedAt = timestamp.toDate();
    } else if (timestamp is DateTime) {
      matchedAt = timestamp;
    } else if (timestamp is String) {
      matchedAt = DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      matchedAt = DateTime.now();
    }

    return MatrimonialMatch(
      id: data['id'] as String? ?? documentId,
      userA: data['userA'] as String? ?? '',
      userB: data['userB'] as String? ?? '',
      matchedAt: matchedAt,
    );
  }
}
