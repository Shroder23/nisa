import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  interestReceived,
  interestAccepted,
  interestDeclined,
  matchCreated,
  messageReceived,
  guardianJoined,
  verificationPending,
  verificationApproved,
  verificationRejected,
  reportResolved,
}

class NotificationItem {
  final String id;
  final String recipientId;
  final String? senderId;
  final NotificationType type;
  final String title;
  final String body;
  final String? entityId;
  final String? targetScreen;
  final bool isRead;
  final DateTime createdAt;

  const NotificationItem({
    required this.id,
    required this.recipientId,
    this.senderId,
    required this.type,
    required this.title,
    required this.body,
    this.entityId,
    this.targetScreen,
    required this.isRead,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'recipientId': recipientId,
    'senderId': senderId,
    'type': type.name,
    'title': title,
    'body': body,
    'entityId': entityId,
    'targetScreen': targetScreen,
    'isRead': isRead,
    'createdAt': createdAt,
  };

  factory NotificationItem.fromMap(String id, Map<String, dynamic> map) {
    final notificationType = _parseType(
      map['type']?.toString(),
      title: map['title']?.toString(),
      body: map['body']?.toString(),
    );

    final timestamp = map['createdAt'];

    DateTime created;

    if (timestamp is Timestamp) {
      created = timestamp.toDate();
    } else if (timestamp is DateTime) {
      created = timestamp;
    } else if (timestamp is String) {
      created = DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      created = DateTime.now();
    }

    return NotificationItem(
      id: id,
      recipientId: map['recipientId'] ?? '',
      senderId: map['senderId'],
      type: notificationType,
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      entityId: map['entityId'],
      targetScreen: map['targetScreen']?.toString(),
      isRead: map['isRead'] == true,
      createdAt: created,
    );
  }

  static NotificationType _parseType(
    String? rawType, {
    String? title,
    String? body,
  }) {
    final key = (rawType ?? '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();

    switch (key) {
      case 'interestreceived':
      case 'interestsent':
      case 'sentinterest':
      case 'newinterest':
        return NotificationType.interestReceived;

      case 'interestaccepted':
      case 'interestconfirmed':
      case 'confirmedinterest':
      case 'interestapproved':
        return NotificationType.interestAccepted;

      case 'interestdeclined':
      case 'interestrejected':
        return NotificationType.interestDeclined;

      case 'matchcreated':
        return NotificationType.matchCreated;

      case 'messagereceived':
      case 'newmessage':
        return NotificationType.messageReceived;

      case 'reportresolved':
        return NotificationType.reportResolved;
    }

    // Older records may not have a recognized type, but their title/body
    // still identifies them as interest notifications.
    final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
    if (text.contains('interest')) {
      if (text.contains('accept') ||
          text.contains('confirm') ||
          text.contains('approved')) {
        return NotificationType.interestAccepted;
      }
      if (text.contains('declin') || text.contains('reject')) {
        return NotificationType.interestDeclined;
      }
      return NotificationType.interestReceived;
    }

    return NotificationType.values.firstWhere(
      (e) => e.name == rawType,
      orElse: () => NotificationType.messageReceived,
    );
  }
}
