import 'package:flutter/material.dart';

import 'widgets/localized_text.dart';

import 'api_chat_screen.dart';
import 'api_conversations_screen.dart';
import 'api_incoming_interests_screen.dart';
import 'api_my_reports_screen.dart';
import 'api_moderator_logs_screen.dart';
import 'api_moderator_recommendations_screen.dart';
import 'api_moderator_requests_screen.dart';
import 'api_account_restrictions_screen.dart';
import 'models/conversation.dart';
import 'models/notification_item.dart';
import 'services/api_auth_service.dart';
import 'services/api_safety_service.dart';
import 'services/app_language_service.dart';
import 'services/api_social_service.dart';

/// PostgreSQL-backed notifications with destinations for supported actions.
class ApiNotificationsScreen extends StatefulWidget {
  const ApiNotificationsScreen({super.key});

  @override
  State<ApiNotificationsScreen> createState() => _ApiNotificationsScreenState();
}

class _ApiNotificationsScreenState extends State<ApiNotificationsScreen> {
  List<NotificationItem> _notifications = const [];
  final Set<String> _readLocally = {};
  bool _loading = true;
  String? _error;
  bool _markingAllRead = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notifications = await ApiSocialService.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _readLocally.clear();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAllRead) return;
    setState(() => _markingAllRead = true);
    final unread = _notifications
        .where((item) => !item.isRead && !_readLocally.contains(item.id))
        .toList();
    final marked = <String>[];
    try {
      for (final item in unread) {
        await ApiSocialService.markNotificationRead(item.id);
        marked.add(item.id);
      }
      if (!mounted) return;
      setState(() => _readLocally.addAll(marked));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Notifications marked as read.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            'Could not mark all as read: {error}',
            substitutions: {
              'error': error.toString().replaceFirst('Bad state: ', ''),
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _readLocally.addAll(marked);
          _markingAllRead = false;
        });
      }
    }
  }

  Future<void> _open(NotificationItem notification) async {
    if (!notification.isRead && !_readLocally.contains(notification.id)) {
      try {
        await ApiSocialService.markNotificationRead(notification.id);
        if (mounted) setState(() => _readLocally.add(notification.id));
      } catch (_) {
        // A read-state error should not block the target screen.
      }
    }
    if (!mounted) return;

    // The API model intentionally keeps the existing notification enum.
    // New moderation notification types therefore deserialize to its legacy
    // fallback type; route them by their explicit server-provided destination.
    if ({
      'moderator_requests',
      'moderation_cases',
      'moderator_recommendations',
      'moderator_logs',
      'profile',
    }.contains(notification.targetScreen)) {
      await _openTargetScreen(
        notification.targetScreen,
        notificationTitle: notification.title,
        notificationBody: notification.body,
      );
      return;
    }

    switch (notification.type) {
      case NotificationType.interestReceived:
      case NotificationType.interestDeclined:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApiIncomingInterestsScreen()),
        );
        break;
      case NotificationType.interestAccepted:
        await _openTargetScreen(
          notification.targetScreen ?? 'matches',
          notificationTitle: notification.title,
          notificationBody: notification.body,
        );
        break;
      case NotificationType.matchCreated:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApiConversationsScreen()),
        );
        break;
      case NotificationType.messageReceived:
        await _openMessageTarget(notification.entityId);
        break;
      default:
        await _openTargetScreen(
          notification.targetScreen,
          notificationTitle: notification.title,
          notificationBody: notification.body,
        );
    }
  }

  Future<void> _openMessageTarget(String? conversationId) async {
    final id = conversationId?.trim() ?? '';
    if (id.isNotEmpty) {
      try {
        final conversations = await ApiSocialService.getConversations();
        Conversation? target;
        for (final conversation in conversations) {
          if (conversation.id == id) {
            target = conversation;
            break;
          }
        }
        final conversation = target;
        if (conversation != null && mounted) {
          final currentUserId =
              ApiAuthService.currentAccount.value?['id']?.toString() ?? '';
          final otherId = conversation.otherParticipant(currentUserId);
          final name = conversation.participantNames[otherId]?.trim();
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ApiChatScreen(
                conversationId: conversation.id,
                otherUserName: name?.isNotEmpty == true ? name! : 'Nisa member',
                otherUserId: otherId,
              ),
            ),
          );
          return;
        }
      } catch (_) {
        // Fall back to the conversation list if a deep link is stale or offline.
      }
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ApiConversationsScreen()));
  }

  Future<void> _openTargetScreen(
    String? targetScreen, {
    String? notificationTitle,
    String? notificationBody,
  }) async {
    switch (targetScreen) {
      case 'incoming_interests':
      case 'interests':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApiIncomingInterestsScreen()),
        );
        return;
      case 'matches':
      case 'messages':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApiConversationsScreen()),
        );
        return;
      case 'my_reports':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ApiMyReportsScreen()));
        return;
      case 'moderator_requests':
      case 'moderation_cases':
        final isAdministrator = await ApiSafetyService.canReviewModeratorLogs();
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ApiModeratorRequestsScreen(administrator: isAdministrator),
          ),
        );
        return;
      case 'moderator_recommendations':
        final isAdministrator = await ApiSafetyService.canReviewModeratorLogs();
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ApiModeratorRecommendationsScreen(
              administrator: isAdministrator,
            ),
          ),
        );
        return;
      case 'moderator_logs':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApiModeratorLogsScreen()),
        );
        return;
      case 'profile':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ApiAccountRestrictionsScreen(
              notificationTitle: notificationTitle,
              notificationBody: notificationBody,
            ),
          ),
        );
        return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: LocalizedText('This notification has no destination yet.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications
        .where((item) => !item.isRead && !_readLocally.contains(item.id))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Notifications'),
        actions: [
          IconButton(
            tooltip: AppLanguageService.translate('Refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: AppLanguageService.translate('Mark all as read'),
            onPressed: _loading || _markingAllRead || unreadCount == 0
                ? null
                : _markAllRead,
            icon: _markingAllRead
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _NotificationMessage(message: _error!, onRetry: _load)
          : _notifications.isEmpty
          ? const _NotificationMessage(message: 'No notifications yet.')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _notifications.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final notification = _notifications[index];
                  final unread =
                      !notification.isRead &&
                      !_readLocally.contains(notification.id);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: unread
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: Icon(_iconFor(notification.type)),
                    ),
                    title: Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: unread
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(notification.body),
                    trailing: unread
                        ? const Icon(Icons.circle, size: 10)
                        : Text(_formatDate(notification.createdAt)),
                    onTap: () => _open(notification),
                  );
                },
              ),
            ),
    );
  }

  IconData _iconFor(NotificationType type) => switch (type) {
    NotificationType.interestReceived => Icons.favorite_border,
    NotificationType.interestAccepted => Icons.favorite,
    NotificationType.matchCreated => Icons.people_outline,
    NotificationType.messageReceived => Icons.chat_bubble_outline,
    NotificationType.verificationApproved => Icons.verified_outlined,
    NotificationType.verificationPending => Icons.hourglass_top,
    NotificationType.verificationRejected => Icons.gpp_bad_outlined,
    NotificationType.guardianJoined => Icons.family_restroom,
    NotificationType.reportResolved => Icons.flag_outlined,
    NotificationType.interestDeclined => Icons.favorite_border,
  };

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}

class _NotificationMessage extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _NotificationMessage({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocalizedText(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const LocalizedText('Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}
