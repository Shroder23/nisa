import 'package:cloud_firestore/cloud_firestore.dart';

class Conversation {
  final String id;
  final String matchId;
  final List<String> participants;
  final DateTime createdAt;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderId;
  final List<String> unreadFor;
  final Map<String, String> participantNames;
  final Map<String, String> participantPhotos;

  const Conversation({
    required this.id,
    required this.matchId,
    required this.participants,
    required this.createdAt,
    this.lastMessage = '',
    this.lastMessageAt,
    this.lastSenderId,
    this.unreadFor = const [],
    this.participantNames = const {},
    this.participantPhotos = const {},
  });

  factory Conversation.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseTimestamp(dynamic value, {DateTime? fallback}) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
      }
      return fallback ?? DateTime.now();
    }

    return Conversation(
      id: id,
      matchId: data['matchId'] as String? ?? id,
      participants: List<String>.from(
        data['participants'] as List? ?? const [],
      ),
      createdAt: parseTimestamp(data['createdAt']),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageAt: data['lastMessageAt'] == null
          ? null
          : parseTimestamp(data['lastMessageAt']),
      lastSenderId: data['lastSenderId'] as String?,
      unreadFor: List<String>.from(data['unreadFor'] as List? ?? const []),
      participantPhotos: Map<String, String>.from(
        (data['participantPhotos'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ) ??
            const {},
      ),
      participantNames: Map<String, String>.from(
        (data['participantNames'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ) ??
            const {},
      ),
    );
  }

  String otherParticipant(String currentUserId) {
    for (final participant in participants) {
      if (participant != currentUserId) return participant;
    }
    return '';
  }
}
