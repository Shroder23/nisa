import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/message.dart';
import '../models/notification_item.dart';
import 'block_service.dart';
import 'notification_service.dart';

class MessageService {
  MessageService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _messages(
    String conversationId,
  ) {
    return _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages');
  }

  static Stream<List<Message>> watchMessages(String conversationId) {
    return _messages(conversationId)
        .orderBy('sentAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Message.fromMap(doc.id, conversationId, doc.data()))
              .toList(),
        );
  }

  /// Check only the latest message when the conversation list is shown.
  /// The list must not open a live 100-message stream for every row.
  static Future<void> markLatestDelivered({
    required String conversationId,
    required String recipientId,
  }) async {
    final snapshot = await _messages(conversationId)
        .orderBy('sentAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return;

    final doc = snapshot.docs.first;
    final message = Message.fromMap(doc.id, conversationId, doc.data());
    if (message.senderId == recipientId || message.deliveredAt != null) return;

    await doc.reference.update({'deliveredAt': FieldValue.serverTimestamp()});
  }

  static Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
  }) async {
    final cleanText = text.trim();
    if (conversationId.isEmpty || senderId.isEmpty) {
      throw StateError('Unable to identify the conversation or sender.');
    }
    if (cleanText.isEmpty) return;
    if (cleanText.length > 2000) {
      throw StateError('Messages are limited to 2000 characters.');
    }

    final conversationRef = _db.collection('conversations').doc(conversationId);
    final conversationSnapshot = await conversationRef.get();
    final conversationData = conversationSnapshot.data();
    if (!conversationSnapshot.exists || conversationData == null) {
      throw StateError('Conversation no longer exists.');
    }

    final participants = List<String>.from(
      conversationData['participants'] as List? ?? const [],
    );
    if (!participants.contains(senderId)) {
      throw StateError('You are not a participant in this conversation.');
    }

    final otherParticipants = participants
        .where((id) => id != senderId)
        .toList();
    if (otherParticipants.isEmpty) {
      throw StateError('Conversation participant is unavailable.');
    }
    if (await BlockService.isBlockedBetween(
      senderId,
      otherParticipants.first,
    )) {
      throw StateError('You can no longer message this user.');
    }

    final messageRef = _messages(conversationId).doc();
    final batch = _db.batch();

    final unreadCounts = <String, dynamic>{
      ...Map<String, dynamic>.from(
        conversationData['unreadCounts'] as Map? ?? const {},
      ),
    };

    for (final recipientId in otherParticipants) {
      final existing = unreadCounts[recipientId];
      unreadCounts[recipientId] = (existing is num ? existing.toInt() : 0) + 1;
    }

    batch.set(messageRef, {
      'senderId': senderId,
      'text': cleanText,
      'sentAt': FieldValue.serverTimestamp(),
    });
    batch.update(conversationRef, {
      'lastMessage': cleanText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': senderId,
      'unreadFor': otherParticipants,
      'unreadCounts': unreadCounts,
    });
    try {
      await batch.commit().timeout(const Duration(seconds: 12));
    } on FirebaseException catch (error) {
      if (error.code == 'resource-exhausted') {
        throw StateError(
          'Firebase quota exhausted. Please try again after the quota resets.',
        );
      }
      rethrow;
    } on TimeoutException {
      throw StateError(
        'Firestore is not responding. Please check the Firebase quota or connection.',
      );
    }

    final participantNames = Map<String, dynamic>.from(
      conversationData['participantNames'] as Map? ?? const {},
    );
    final senderName = participantNames[senderId]?.toString() ?? 'Someone';
    for (final recipientId in otherParticipants) {
      // The message is committed. Notification delivery is secondary and
      // must not keep the send button spinning.
      () async {
        try {
          await NotificationService.create(
            recipientId: recipientId,
            senderId: senderId,
            type: NotificationType.messageReceived,
            title: 'New message from $senderName',
            body: cleanText,
            entityId: conversationId,
          );
        } catch (_) {
          // The message is already saved; an alert failure is non-fatal.
        }
      }();
    }
  }

  static Future<void> markDelivered({
    required String conversationId,
    required String recipientId,
    required Iterable<Message> messages,
  }) async {
    final pending = messages
        .where(
          (message) =>
              message.senderId != recipientId && message.deliveredAt == null,
        )
        .toList();
    if (pending.isEmpty) return;

    final batch = _db.batch();
    for (final message in pending) {
      batch.update(_messages(conversationId).doc(message.id), {
        'deliveredAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static Future<void> markSeen({
    required String conversationId,
    required String recipientId,
    required Iterable<Message> messages,
  }) async {
    final pending = messages
        .where(
          (message) =>
              message.senderId != recipientId && message.seenAt == null,
        )
        .toList();
    if (pending.isEmpty) return;

    final batch = _db.batch();
    for (final message in pending) {
      batch.update(_messages(conversationId).doc(message.id), {
        'deliveredAt': FieldValue.serverTimestamp(),
        'seenAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
