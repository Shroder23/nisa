import 'package:flutter/material.dart';

import 'widgets/localized_text.dart';

import 'models/conversation.dart';
import 'services/api_auth_service.dart';
import 'services/api_social_service.dart';
import 'services/app_language_service.dart';
import 'services/api_presence_service.dart';
import 'api_chat_screen.dart';
import 'widgets/api_profile_photo.dart';

/// PostgreSQL-backed conversation list.
class ApiConversationsScreen extends StatefulWidget {
  final bool onlyWithMessages;
  final bool showAppBar;

  const ApiConversationsScreen({
    super.key,
    this.onlyWithMessages = false,
    this.showAppBar = true,
  });

  @override
  State<ApiConversationsScreen> createState() => _ApiConversationsScreenState();
}

class _ApiConversationsScreenState
    extends LanguageAwareState<ApiConversationsScreen> {
  List<Conversation> _conversations = const [];
  bool _loading = true;
  String? _error;

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
      final conversations = await ApiSocialService.getConversations();
      if (widget.onlyWithMessages) {
        conversations.removeWhere((item) => item.lastMessage.trim().isEmpty);
      }
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
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

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        ApiAuthService.currentAccount.value?['id']?.toString() ?? '';
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const LocalizedText('Messages'),
              actions: [
                IconButton(
                  tooltip: AppLanguageService.translate('Refresh'),
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ConversationMessage(message: _error!, onRetry: _load)
          : _conversations.isEmpty
          ? const _ConversationMessage(
              message: 'No messages yet. Start a conversation from one of your matches.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _conversations.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final conversation = _conversations[index];
                  final otherId = conversation.otherParticipant(currentUserId);
                  final name =
                      conversation.participantNames[otherId]
                              ?.trim()
                              .isNotEmpty ==
                          true
                      ? conversation.participantNames[otherId]!.trim()
                      : 'Nisa member';
                  final unread = conversation.unreadFor.contains(currentUserId);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: ApiProfilePhoto(
                      imageUrl: conversation.participantPhotos[otherId],
                      radius: 29,
                      fallbackText: name,
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ApiPresenceLabel(
                            userId: otherId,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                            compact: true,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            conversation.lastMessage.isEmpty
                                ? 'Matched. Start a conversation.'
                                : conversation.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: unread
                        ? Badge(
                            smallSize: 10,
                            child: const Icon(Icons.chevron_right),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ApiChatScreen(
                            conversationId: conversation.id,
                            otherUserName: name,
                            otherUserId: otherId,
                            otherUserPhoto:
                                conversation.participantPhotos[otherId],
                          ),
                        ),
                      );
                      if (mounted) await _load();
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _ConversationMessage extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _ConversationMessage({required this.message, this.onRetry});

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
