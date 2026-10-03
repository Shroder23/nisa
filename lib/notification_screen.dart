import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/notification_item.dart';
import 'incoming_interests_screen.dart';
import 'services/app_state.dart';
import 'services/notification_service.dart';
import 'widgets/notification_tile.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  Future<void> _openIncomingInterests(BuildContext context) async {
    var profile = AppState.currentUser;

    if (profile == null) {
      try {
        await AppState.loadUser();
        profile = AppState.currentUser;
      } catch (_) {
        // A temporary restore failure should not crash the notification list.
      }
    }

    if (profile == null) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Your profile is still loading.'),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final resolvedProfile = profile;
    final navigator = Navigator.of(context);

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => IncomingInterestsScreen(profile: resolvedProfile),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // Opening the screen clears only the unread badge. It must never remove
    // notification documents; users can still review them later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markNotificationsAsRead();
    });
  }

  Future<void> _markNotificationsAsRead() async {
    final currentUser = AppState.currentUser;
    final uid = currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      await NotificationService.markAllRead(uid);
    } catch (_) {
      // The list remains usable if the badge update temporarily fails.
      // The unread count will retry through its Firestore stream.
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AppState.currentUser;

    if (currentUser == null || currentUser.uid == null) {
      return Scaffold(
        appBar: AppBar(
          title: const LocalizedText('Notifications'),
          centerTitle: true,
          actions: const [LanguageSelectorButton()],
        ),
        body: const Center(child: LocalizedText('You are not signed in.')),
      );
    }

    final uid = currentUser.uid!;

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Notifications'),
        centerTitle: true,
        actions: [
          const LanguageSelectorButton(),
          IconButton(
            tooltip: AppLanguageService.translate('Mark all as read'),
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              await NotificationService.markAllRead(uid);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: LocalizedText('All notifications marked as read.'),
                  ),
                );
              }
            },
          ),
        ],
      ),

      body: StreamBuilder<List<NotificationItem>>(
        stream: NotificationService.stream(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: LocalizedText(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data!;

          if (notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                await Future.delayed(const Duration(milliseconds: 300));
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),

                  Icon(
                    Icons.notifications_none_rounded,
                    size: 80,
                    color: Colors.grey,
                  ),

                  SizedBox(height: 20),

                  Center(
                    child: LocalizedText(
                      'No notifications yet',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  SizedBox(height: 12),

                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: LocalizedText(
                      'When someone sends an interest,\naccepts your request,\nor sends you a message,\nyou will see it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, height: 1.5),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await Future.delayed(const Duration(milliseconds: 300));
            },

            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),

              itemCount: notifications.length,

              itemBuilder: (context, index) {
                final notification = notifications[index];

                return Dismissible(
                  key: ValueKey(notification.id),

                  background: Container(
                    color: Colors.red,

                    alignment: Alignment.centerRight,

                    padding: const EdgeInsets.only(right: 24),

                    child: const Icon(Icons.delete, color: Colors.white),
                  ),

                  direction: DismissDirection.endToStart,

                  onDismissed: (_) async {
                    await NotificationService.delete(uid, notification.id);

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: LocalizedText('Notification deleted'),
                        ),
                      );
                    }
                  },

                  child: NotificationTile(
                    notification: notification,

                    onTap: () async {
                      if (!notification.isRead) {
                        try {
                          await NotificationService.markRead(
                            uid,
                            notification.id,
                          );
                        } catch (error) {
                          // Read-state failure must never block navigation.
                          debugPrint('Notification mark-read failed: $error');
                        }
                      }

                      if (!context.mounted) return;

                      switch (notification.type) {
                        case NotificationType.interestReceived:
                          await _openIncomingInterests(context);
                          break;

                        case NotificationType.interestAccepted:
                          await _openIncomingInterests(context);
                          break;

                        case NotificationType.interestDeclined:
                          await _openIncomingInterests(context);
                          break;

                        case NotificationType.messageReceived:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: LocalizedText('Open conversation'),
                            ),
                          );

                          break;

                        case NotificationType.matchCreated:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: LocalizedText('New match')),
                          );

                          break;

                        case NotificationType.verificationApproved:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: LocalizedText('Verification approved'),
                            ),
                          );

                          break;

                        case NotificationType.verificationRejected:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: LocalizedText('Verification rejected'),
                            ),
                          );

                          break;

                        case NotificationType.verificationPending:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: LocalizedText('Verification pending'),
                            ),
                          );

                          break;

                        case NotificationType.guardianJoined:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: LocalizedText('Guardian linked'),
                            ),
                          );

                          break;

                        case NotificationType.reportResolved:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: LocalizedText('Report resolved'),
                            ),
                          );

                          break;
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
