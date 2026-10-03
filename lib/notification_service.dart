import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/notification_item.dart';

class NotificationService {
  NotificationService._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _collection(String uid) {
    return _db.collection('users').doc(uid).collection('notifications');
  }

  static Future<String> create({
    required String recipientId,
    String? senderId,
    required NotificationType type,
    required String title,
    required String body,
    String? entityId,
  }) async {
    final ref = await _collection(recipientId).add({
      'recipientId': recipientId,
      'senderId': senderId,
      'type': type.name,
      'title': title,
      'body': body,
      'entityId': entityId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  static Stream<List<NotificationItem>> stream(String uid) {
    return _collection(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          final notifications = snapshot.docs
              .map((doc) => NotificationItem.fromMap(doc.id, doc.data()))
              .toList();

          notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return _removeDuplicateVerificationNotifications(notifications);
        });
  }

  static Future<void> markRead(String uid, String notificationId) async {
    final notificationRef = _collection(uid).doc(notificationId);
    final snapshot = await notificationRef.get();

    if (!snapshot.exists) return;

    final data = snapshot.data() ?? <String, dynamic>{};
    final type = data['type']?.toString();
    final entityId = data['entityId']?.toString();

    // Older server versions could create more than one notification for the
    // same verification request. Mark the whole logical notification read so
    // an old duplicate cannot reappear as unread later.
    if ((type == 'verificationApproved' || type == 'verificationRejected') &&
        entityId != null &&
        entityId.isNotEmpty) {
      final all = await _collection(uid).get();
      final batch = _db.batch();

      for (final doc in all.docs) {
        final item = doc.data();
        if (item['type']?.toString() == type &&
            item['entityId']?.toString() == entityId &&
            item['isRead'] != true) {
          batch.update(doc.reference, {'isRead': true});
        }
      }

      await batch.commit();
      return;
    }

    await notificationRef.update({'isRead': true});
  }

  static Future<void> delete(String uid, String notificationId) async {
    await _collection(uid).doc(notificationId).delete();
  }

  static Stream<int> unreadCount(String uid) {
    return _collection(uid).snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) => NotificationItem.fromMap(doc.id, doc.data()))
          .toList();
      return _removeDuplicateVerificationNotifications(items)
          .where((item) => !item.isRead)
          .length;
    });
  }

  static Future<void> markAllRead(String uid) async {
    final snapshot = await _collection(uid)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _db.batch();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  static Stream<bool> hasUnread(String uid) {
    return unreadCount(uid).map((unreadTotal) => unreadTotal > 0);
  }

  static List<NotificationItem> _removeDuplicateVerificationNotifications(
    List<NotificationItem> notifications,
  ) {
    final seenVerification = <String>{};
    final result = <NotificationItem>[];

    for (final notification in notifications) {
      final isVerification =
          (notification.type == NotificationType.verificationApproved ||
              notification.type == NotificationType.verificationRejected) &&
          notification.entityId != null &&
          notification.entityId!.isNotEmpty;

      if (!isVerification) {
        result.add(notification);
        continue;
      }

      final key = '${notification.type.name}:${notification.entityId}';
      if (seenVerification.add(key)) {
        result.add(notification);
      }
    }

    return result;
  }
}
