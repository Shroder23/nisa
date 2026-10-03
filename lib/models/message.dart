import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final DateTime? seenAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.deliveredAt,
    this.seenAt,
  });

  factory Message.fromMap(
    String id,
    String conversationId,
    Map<String, dynamic> data,
  ) {
    final value = data['sentAt'];

    DateTime sentAt;
    if (value is Timestamp) {
      sentAt = value.toDate();
    } else if (value is DateTime) {
      sentAt = value;
    } else if (value is String) {
      sentAt = DateTime.tryParse(value) ?? DateTime.now();
    } else {
      sentAt = DateTime.now();
    }

    return Message(
      id: id,
      conversationId: conversationId,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      sentAt: sentAt,
      deliveredAt: _parseTimestamp(data['deliveredAt']),
      seenAt: _parseTimestamp(data['seenAt']),
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
