import 'package:cloud_firestore/cloud_firestore.dart';

enum InterestStatus { pending, accepted, declined, cancelled }

extension InterestStatusExtension on InterestStatus {
  String get value {
    switch (this) {
      case InterestStatus.pending:
        return 'pending';
      case InterestStatus.accepted:
        return 'accepted';
      case InterestStatus.declined:
        return 'declined';
      case InterestStatus.cancelled:
        return 'cancelled';
    }
  }

  static InterestStatus fromValue(String? value) {
    switch (value) {
      case 'accepted':
        return InterestStatus.accepted;
      case 'declined':
        return InterestStatus.declined;
      case 'cancelled':
        return InterestStatus.cancelled;
      default:
        return InterestStatus.pending;
    }
  }
}

class Interest {
  final String id;
  final String senderId;
  final String receiverId;

  InterestStatus status;

  final DateTime? createdAt;
  DateTime? updatedAt;
  final String? otherUserName;
  final String? otherUserCity;
  final String? otherUserCountry;

  Interest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.status = InterestStatus.pending,
    this.createdAt,
    this.updatedAt,
    this.otherUserName,
    this.otherUserCity,
    this.otherUserCountry,
  });

  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'status': status.value,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory Interest.fromJson(String id, Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      return null;
    }

    return Interest(
      id: id,
      senderId: json['senderId'] as String? ?? '',
      receiverId: json['receiverId'] as String? ?? '',
      status: InterestStatusExtension.fromValue(json['status'] as String?),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      otherUserName: json['otherUserName'] as String?,
      otherUserCity: json['otherUserCity'] as String?,
      otherUserCountry: json['otherUserCountry'] as String?,
    );
  }
}
