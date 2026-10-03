import 'dart:async';

import 'package:flutter/material.dart';

import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

import 'models/message.dart';
import 'report_user_screen.dart';
import 'services/api_auth_service.dart';
import 'services/api_safety_service.dart';
import 'services/api_social_service.dart';
import 'services/api_presence_service.dart';
import 'widgets/api_profile_photo.dart';

/// PostgreSQL-backed chat. It polls while visible because the API currently
/// has no websocket or server-sent event route.
class ApiChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String otherUserId;
  final String? otherUserPhoto;

  const ApiChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
    required this.otherUserId,
    this.otherUserPhoto,
  });

  @override
  State<ApiChatScreen> createState() => _ApiChatScreenState();
}

class _ApiChatScreenState extends State<ApiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Message> _messages = const [];
  Timer? _pollTimer;
  bool _requestingMessages = false;
  bool _loading = true;
  bool _sending = false;
  bool _blockedBetween = false;
  bool _blocking = false;
  bool _checkingBlockStatus = false;
  String? _error;

  String get _currentUserId =>
      ApiAuthService.currentAccount.value?['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _refreshBlockStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && !_sending) {
        _refreshBlockStatus().then((_) {
          if (mounted && !_blockedBetween) {
            _loadMessages(showLoading: false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool showLoading = true}) async {
    if (_blockedBetween) return;
    if (_requestingMessages) return;
    _requestingMessages = true;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final messages = await ApiSocialService.getMessages(
        widget.conversationId,
      );
      if (!mounted || _blockedBetween) return;
      try {
        await ApiSocialService.markConversationRead(widget.conversationId);
      } catch (_) {
        // Keep the message list available if updating unread state fails.
      }
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (error.toString().contains('Conversation not found')) {
          _blockedBetween = true;
          _messages = const [];
          _error = null;
          _pollTimer?.cancel();
        } else if (showLoading || _messages.isEmpty) {
          _error = error.toString();
        }
      });
    } finally {
      _requestingMessages = false;
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_sending || _blockedBetween || text.isEmpty) return;
    if (text.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Messages can be up to 2,000 characters.'),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final sent = await ApiSocialService.sendMessage(
        widget.conversationId,
        text,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _messages = [..._messages, sent];
        _error = null;
      });
      try {
        await ApiSocialService.markConversationRead(widget.conversationId);
      } catch (_) {
        // Sending succeeded; unread state can refresh separately.
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refreshBlockStatus() async {
    if (_checkingBlockStatus || _blockedBetween) return;
    _checkingBlockStatus = true;
    try {
      final blocked = await ApiSafetyService.isBlockedBetween(
        widget.otherUserId,
      );
      if (!mounted) return;
      if (blocked) {
        setState(() {
          _blockedBetween = true;
          _messages = const [];
          _error = null;
        });
        _pollTimer?.cancel();
      }
    } catch (_) {
      // The message endpoints still enforce blocks if this status check fails.
    } finally {
      _checkingBlockStatus = false;
    }
  }

  Future<void> _blockUser() async {
    if (_blocking || _blockedBetween) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: LocalizedText(
          'Block {name}?',
          substitutions: {'name': widget.otherUserName},
        ),
        content: const LocalizedText(
          'Neither of you will be able to send interests or messages. They will not be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _blocking = true);
    try {
      await ApiSafetyService.blockUser(widget.otherUserId);
      if (!mounted) return;
      setState(() {
        _blockedBetween = true;
        _messages = const [];
      });
      _pollTimer?.cancel();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('User blocked.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _blocking = false);
    }
  }

  Future<void> _reportUser() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportUserScreen(
          reportedUserId: widget.otherUserId,
          reportedUserName: widget.otherUserName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ApiProfilePhoto(
              imageUrl: widget.otherUserPhoto,
              radius: 19,
              fallbackText: widget.otherUserName,
              enablePreview: false,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.otherUserName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ApiPresenceLabel(
                    userId: widget.otherUserId,
                    style: Theme.of(context).textTheme.labelSmall,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: AppLanguageService.translate('Safety options'),
            onSelected: (value) {
              if (value == 'report') _reportUser();
              if (value == 'block') _blockUser();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'report',
                child: ListTile(
                  leading: Icon(Icons.flag_outlined),
                  title: LocalizedText('Report'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: ListTile(
                  leading: Icon(Icons.block_outlined),
                  title: LocalizedText('Block'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: AppLanguageService.translate('Refresh messages'),
            onPressed: _loading ? null : () => _loadMessages(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => _loadMessages(),
                            child: const LocalizedText('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: LocalizedText(
                        'You matched. Start a respectful conversation.',
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadMessages(),
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[_messages.length - 1 - index];
                        return _ApiMessageBubble(
                          message: message,
                          mine: message.senderId == _currentUserId,
                        );
                      },
                    ),
                  ),
          ),
          if (_blockedBetween)
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LocalizedText(
                  'Messaging is unavailable because one of you has blocked the other.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_sending && !_blocking,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: AppLanguageService.translate(
                            'Write a message…',
                          ),
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending || _blocking ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ApiMessageBubble extends StatelessWidget {
  final Message message;
  final bool mine;

  const _ApiMessageBubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = message.sentAt;
    final messageTime = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(time));
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(message.text, style: const TextStyle(height: 1.35)),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  messageTime,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.seenAt != null
                        ? Icons.done_all
                        : message.deliveredAt != null
                        ? Icons.done_all
                        : Icons.done,
                    size: 15,
                    color: message.seenAt != null
                        ? const Color(0xFF34B7F1)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
