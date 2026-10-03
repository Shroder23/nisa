import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_item.dart';

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

          return notifications;
        });
  }

  static Future<void> markRead(String uid, String notificationId) async {
    await _collection(uid).doc(notificationId).update({'isRead': true});
  }

  static Future<void> delete(String uid, String notificationId) async {
    await _collection(uid).doc(notificationId).delete();
  }

  static Stream<int> unreadCount(String uid) {
    return _collection(uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  static Future<void> markAllRead(String uid) async {
    final snapshot = await _collection(uid)
        .where('isRead', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = _db.batch();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  static Stream<bool> hasUnread(String uid) {
    return unreadCount(uid).map((unreadTotal) => unreadTotal > 0);
  }
}
