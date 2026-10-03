import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/conversation.dart';
import '../models/interest.dart';
import '../models/message.dart';
import '../models/notification_item.dart';
import 'api_auth_service.dart';

/// PostgreSQL-backed social and messaging operations.
///
/// These methods are available to API-session screens. Firebase-backed screens
/// should continue using their existing services until the app router is
/// switched to an API session.
class ApiSocialService {
  ApiSocialService._();

  static Future<List<NotificationItem>> getNotifications() async {
    final response = await ApiAuthService.get('/api/notifications');
    final data = _decodeMap(response);
    _checkResponse(response, data);
    return _list(data!['notifications']).map((row) {
      final rawType = row['notification_type']?.toString() ?? '';
      final type = switch (rawType) {
        'incoming_interest' => 'interest_received',
        'interest_accepted' => 'interest_accepted',
        'interest_declined' => 'interest_declined',
        'new_message' => 'message_received',
        _ => rawType,
      };
      return NotificationItem.fromMap(row['id']?.toString() ?? '', {
        'recipientId': row['recipient_id'],
        'senderId': row['actor_id'],
        'type': type,
        'title': row['title'],
        'body': row['body'],
        'entityId': row['target_id'],
        'targetScreen': row['target_screen'],
        'isRead': row['is_read'],
        'createdAt': row['created_at'],
      });
    }).toList();
  }

  static Future<void> markNotificationRead(String notificationId) async {
    final response = await ApiAuthService.postJson(
      '/api/notifications/${Uri.encodeComponent(notificationId)}/read',
      const {},
    );
    _checkResponse(response, _decodeMap(response));
  }

  static Future<List<Interest>> getIncomingInterests() async {
    final response = await ApiAuthService.get('/api/interests/incoming');
    final data = _decodeMap(response);
    _checkResponse(response, data);
    return _list(data!['interests']).map(_interestFromRow).toList();
  }

  static Future<List<Interest>> getSentInterests() async {
    final response = await ApiAuthService.get('/api/interests/sent');
    final data = _decodeMap(response);
    _checkResponse(response, data);
    return _list(data!['interests']).map(_interestFromRow).toList();
  }

  static Future<Interest> sendInterest(String receiverId) async {
    final response = await ApiAuthService.postJson(
      '/api/interests/${Uri.encodeComponent(receiverId)}',
      const {},
    );
    final data = _decodeMap(response);
    _checkResponse(response, data);
    return _interestFromRow(data!);
  }

  static Future<String?> respondToInterest(
    String interestId, {
    required bool accept,
  }) async {
    final response = await ApiAuthService.postJson(
      '/api/interests/${Uri.encodeComponent(interestId)}/respond',
      {'status': accept ? 'accepted' : 'declined'},
    );
    final data = _decodeMap(response);
    _checkResponse(response, data);
    return data?['match_id']?.toString();
  }

  static Future<List<Conversation>> getConversations() async {
    final response = await ApiAuthService.get('/api/conversations');
    final data = _decodeMap(response);
    _checkResponse(response, data);
    final currentUserId = _currentUserId;
    return _list(data!['conversations']).map((row) {
      final otherId = row['other_user_id']?.toString() ?? '';
      final lastMessageAt = _date(row['last_message_at']);
      final unreadCount = (row['unread_count'] as num?)?.toInt() ?? 0;
      return Conversation.fromMap(row['id']?.toString() ?? '', {
        'matchId': row['id']?.toString(),
        'participants': [currentUserId, otherId],
        'createdAt': lastMessageAt?.toIso8601String(),
        'lastMessage': row['last_message'] ?? '',
        'lastMessageAt': lastMessageAt?.toIso8601String(),
        'participantNames': {
          if (otherId.isNotEmpty) otherId: row['other_user_name'] ?? '',
        },
        'participantPhotos': {
          if (otherId.isNotEmpty) otherId: row['other_user_photo'] ?? '',
        },
        'unreadFor': unreadCount > 0 ? [currentUserId] : const <String>[],
      });
    }).toList();
  }

  static Future<List<Message>> getMessages(String conversationId) async {
    final response = await ApiAuthService.get(
      '/api/conversations/${Uri.encodeComponent(conversationId)}/messages',
    );
    final data = _decodeMap(response);
    _checkResponse(response, data);
    return _list(data!['messages']).map((row) {
      return Message.fromMap(row['id']?.toString() ?? '', conversationId, {
        'senderId': row['sender_id'],
        'text': row['body'],
        'sentAt': row['sent_at'],
        'deliveredAt': row['delivered_at'],
        'seenAt': row['read_at'],
      });
    }).toList();
  }

  static Future<Message> sendMessage(String conversationId, String text) async {
    final response = await ApiAuthService.postJson(
      '/api/conversations/${Uri.encodeComponent(conversationId)}/messages',
      {'body': text},
    );
    final data = _decodeMap(response);
    _checkResponse(response, data);
    final row = _map(data!['message']);
    return Message.fromMap(row['id']?.toString() ?? '', conversationId, {
      'senderId': row['sender_id'],
      'text': row['body'],
      'sentAt': row['sent_at'],
      'deliveredAt': row['delivered_at'],
      'seenAt': row['read_at'],
    });
  }

  static Future<void> markConversationRead(String conversationId) async {
    final response = await ApiAuthService.postJson(
      '/api/conversations/${Uri.encodeComponent(conversationId)}/read',
      const {},
    );
    _checkResponse(response, _decodeMap(response));
  }

  static Future<int> unreadMessageCount() async {
    final response = await ApiAuthService.get('/api/messages/unread-count');
    final data = _decodeMap(response);
    _checkResponse(response, data);
    return (data?['unread_count'] as num?)?.toInt() ?? 0;
  }

  static String get _currentUserId {
    final id = ApiAuthService.currentAccount.value?['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Restore the API session before loading conversations.');
    }
    return id;
  }

  static Interest _interestFromRow(Map<String, dynamic> row) => Interest(
    id: row['id']?.toString() ?? '',
    senderId: row['sender_id']?.toString() ?? '',
    receiverId: row['receiver_id']?.toString() ?? '',
    status: InterestStatusExtension.fromValue(row['status']?.toString()),
    createdAt: _date(row['created_at']),
    updatedAt: _date(row['updated_at']),
    otherUserName: (row['sender_name'] ?? row['receiver_name'])?.toString(),
    otherUserCity: (row['sender_city'] ?? row['receiver_city'])?.toString(),
    otherUserCountry: (row['sender_country'] ?? row['receiver_country'])
        ?.toString(),
  );

  static DateTime? _date(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : <Map<String, dynamic>>[];

  static Map<String, dynamic>? _decodeMap(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static void _checkResponse(
    http.Response response,
    Map<String, dynamic>? data,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final detail = data?['detail']?.toString();
    throw StateError(detail ?? 'Nisa could not complete this request.');
  }
}
