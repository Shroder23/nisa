import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/conversation.dart';
import '../models/match.dart';
import 'block_service.dart';
import 'candidate_service.dart';

class ConversationService {
  ConversationService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static Stream<int> unreadCount(String uid) {
    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
          int count = 0;

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final rawCounts = data['unreadCounts'];

            if (rawCounts is Map && rawCounts[uid] is num) {
              count += (rawCounts[uid] as num).toInt();
              continue;
            }

            // Backward compatibility for conversations created before
            // per-message unread counts were added.
            final unread = List<String>.from(data['unreadFor'] ?? []);
            if (unread.contains(uid)) count++;
          }

          return count;
        });
  }

  static CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('conversations');

  static Stream<List<Conversation>> watchForUser(String userId) {
    if (userId.isEmpty) return Stream.value(const <Conversation>[]);

    return _conversations
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final conversations = snapshot.docs
              .map((doc) => Conversation.fromMap(doc.id, doc.data()))
              .toList();
          conversations.sort((a, b) {
            final aTime = a.lastMessageAt ?? a.createdAt;
            final bTime = b.lastMessageAt ?? b.createdAt;
            return bTime.compareTo(aTime);
          });
          return conversations;
        });
  }

  static Future<Conversation> getOrCreateForMatch(
    MatrimonialMatch match,
    String currentUserId,
  ) async {
    if (currentUserId.isEmpty) {
      throw StateError('You are not signed in.');
    }
    if (currentUserId != match.userA && currentUserId != match.userB) {
      throw StateError('You are not a participant in this match.');
    }

    final otherUserId = match.userA == currentUserId
        ? match.userB
        : match.userA;
    if (await BlockService.isBlockedBetween(currentUserId, otherUserId)) {
      throw StateError(
        'Messaging is unavailable because one of you has blocked the other.',
      );
    }

    final ref = _conversations.doc(match.id);
    final participants = [match.userA, match.userB]..sort();
    final profiles = await Future.wait(
      participants.map(CandidateService.getCandidateById),
    );

    try {
      await ref.set({
        'matchId': match.id,
        'participants': participants,
        'participantNames': {
          for (var i = 0; i < participants.length; i++)
            participants[i]: profiles[i]?.name ?? 'Nisa Member',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': null,
        'lastSenderId': null,
        'unreadFor': <String>[],
      });

      return Conversation(
        id: match.id,
        matchId: match.id,
        participants: participants,
        createdAt: DateTime.now(),
      );
    } on FirebaseException {
      try {
        final existing = await ref.get();
        final data = existing.data();
        if (existing.exists && data != null) {
          return Conversation.fromMap(existing.id, data);
        }
      } catch (_) {}
      rethrow;
    }
  }

  static Future<Conversation?> getById(String conversationId) async {
    final doc = await _conversations.doc(conversationId).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return Conversation.fromMap(doc.id, data);
  }

  static Future<void> markRead({
    required String conversationId,
    required String userId,
  }) async {
    if (conversationId.isEmpty || userId.isEmpty) return;
    await _conversations.doc(conversationId).update({
      'unreadFor': FieldValue.arrayRemove([userId]),
      'unreadCounts.$userId': 0,
    });
  }
}
