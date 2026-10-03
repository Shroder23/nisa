import 'localized_text.dart';

import 'package:flutter/material.dart';

import '../models/notification_item.dart';

class NotificationTile extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback? onTap;

  const NotificationTile({super.key, required this.notification, this.onTap});

  IconData _icon() {
    switch (notification.type) {
      case NotificationType.interestReceived:
        return Icons.favorite_rounded;

      case NotificationType.interestAccepted:
        return Icons.favorite;

      case NotificationType.interestDeclined:
        return Icons.heart_broken_rounded;

      case NotificationType.matchCreated:
        return Icons.people_alt_rounded;

      case NotificationType.messageReceived:
        return Icons.chat_bubble_rounded;

      case NotificationType.guardianJoined:
        return Icons.family_restroom_rounded;

      case NotificationType.verificationPending:
        return Icons.pending_actions_rounded;

      case NotificationType.verificationApproved:
        return Icons.verified_rounded;

      case NotificationType.verificationRejected:
        return Icons.gpp_bad_rounded;

      case NotificationType.reportResolved:
        return Icons.report_gmailerrorred_rounded;
    }
  }

  Color _iconColor(BuildContext context) {
    switch (notification.type) {
      case NotificationType.interestReceived:
        return Colors.pink;

      case NotificationType.interestAccepted:
        return Colors.green;

      case NotificationType.interestDeclined:
        return Colors.red;

      case NotificationType.matchCreated:
        return Colors.deepPurple;

      case NotificationType.messageReceived:
        return Colors.blue;

      case NotificationType.guardianJoined:
        return Colors.orange;

      case NotificationType.verificationPending:
        return Colors.amber;

      case NotificationType.verificationApproved:
        return Colors.green;

      case NotificationType.verificationRejected:
        return Colors.red;

      case NotificationType.reportResolved:
        return Colors.teal;
    }
  }

  String _timeAgo() {
    final diff = DateTime.now().difference(notification.createdAt);

    if (diff.inSeconds < 60) {
      return 'Just now';
    }

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }

    if (diff.inHours < 24) {
      return '${diff.inHours} hr ago';
    }

    if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }

    return '${notification.createdAt.day}/${notification.createdAt.month}/${notification.createdAt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;

    return Card(
      elevation: unread ? 3 : 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,

        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: _iconColor(context).withValues(alpha: .12),
              child: Icon(_icon(), color: _iconColor(context)),
            ),

            if (unread)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),

        title: LocalizedText(
          notification.title,
          style: TextStyle(
            fontWeight: unread ? FontWeight.bold : FontWeight.w500,
          ),
        ),

        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(notification.body),

              const SizedBox(height: 6),

              LocalizedText(
                _timeAgo(),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
