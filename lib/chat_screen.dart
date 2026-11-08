import 'presentation/nisa_premium/nisa_premium.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/message.dart';
import 'services/app_state.dart';
import 'services/conversation_service.dart';
import 'services/message_service.dart';
import 'services/block_service.dart';
import 'services/presence_service.dart';
import 'report_user_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends LanguageAwareState<ChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _lastMarkedMessageId;
  bool _checkingBlock = true;
  bool _blockedBetween = false;
  bool _blocking = false;
  final Set<String> _receiptRequests = <String>{};

  String? get _currentUserId => AppState.firebaseUser?.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _markConversationRead();
    _checkBlockStatus();
    _setPresence(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setPresence(false);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setPresence(true);
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setPresence(false);
    }
  }

  void _setPresence(bool online) {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;

    final operation = online
        ? PresenceService.markOnline(uid)
        : PresenceService.markOffline(uid);
    operation.catchError((_) {});
  }

  void _syncMessageReceipts(List<Message> messages, String uid) {
    final incoming = messages.where((message) => message.senderId != uid);
    final pending = incoming
        .where((message) => message.seenAt == null)
        .where((message) => _receiptRequests.add(message.id))
        .toList();
    if (pending.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await MessageService.markSeen(
          conversationId: widget.conversationId,
          recipientId: uid,
          messages: pending,
        );
      } catch (_) {
        _receiptRequests.removeAll(pending.map((message) => message.id));
      }
    });
  }

  Future<void> _markConversationRead() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;

    try {
      await ConversationService.markRead(
        conversationId: widget.conversationId,
        userId: uid,
      );
    } catch (_) {
      // Reading a chat should still work even if the badge update fails.
    }
  }

  Future<void> _checkBlockStatus() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() => _checkingBlock = false);
      return;
    }
    try {
      final blocked = await BlockService.isBlockedBetween(
        uid,
        widget.otherUserId,
      );
      if (!mounted) return;
      setState(() {
        _blockedBetween = blocked;
        _checkingBlock = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checkingBlock = false);
    }
  }

  Future<void> _blockUser() async {
    if (_blocking) return;
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedText(
          'Block {name}?',
          substitutions: {'name': widget.otherUserName},
        ),
        content: const LocalizedText(
          'Neither of you will be able to send messages while the block is active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _blocking = true);
    try {
      await BlockService.blockUser(
        blockerId: uid,
        blockedId: widget.otherUserId,
      );
      if (!mounted) return;
      setState(() {
        _blockedBetween = true;
        _blocking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('User blocked. Messaging disabled.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _blocking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Future<void> _reportUser() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportUserScreen(
          reportedUserId: widget.otherUserId,
          reportedUserName: widget.otherUserName,
        ),
      ),
    );
  }

  Future<void> _send() async {
    if (_sending || _blockedBetween || _checkingBlock) return;

    final uid = _currentUserId;
    final text = _controller.text.trim();

    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Please sign in again.')),
      );
      return;
    }

    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      await MessageService.sendMessage(
        conversationId: widget.conversationId,
        senderId: uid,
        text: text,
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException(
          'Firestore is not responding. Check the Firebase quota or connection.',
        ),
      );

      _controller.clear();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final message = e.code == 'resource-exhausted'
          ? 'Message could not be sent because the Firebase quota is exhausted.'
          : 'Could not send message: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: LocalizedText(message)));
    } on TimeoutException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(e.message ?? 'Message send timed out.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<UserPresence>(
          stream: PresenceService.watch(widget.otherUserId),
          builder: (context, snapshot) {
            final presence = snapshot.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(widget.otherUserName),
                if (presence != null)
                  Text(
                    presence.label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            );
          },
        ),
        centerTitle: true,
        actions: [
          const LanguageSelectorButton(),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'report') _reportUser();
              if (value == 'block') _blockUser();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'report', child: LocalizedText('Report')),
              PopupMenuItem(value: 'block', child: LocalizedText('Block')),
            ],
          ),
        ],
      ),
      body: NisaPageBody(
        form: false,
        child: uid == null || uid.isEmpty
            ? const Center(child: LocalizedText('You are not signed in.'))
            : Column(
                children: [
                  Expanded(
                    child: StreamBuilder<List<Message>>(
                      stream: MessageService.watchMessages(
                        widget.conversationId,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: LocalizedText(
                                'Something went wrong. Please try again.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final messages = snapshot.data!;

                        _syncMessageReceipts(messages, uid);

                        if (messages.isNotEmpty) {
                          final newest = messages.first;
                          if (newest.senderId != uid &&
                              newest.id != _lastMarkedMessageId) {
                            _lastMarkedMessageId = newest.id;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _markConversationRead();
                            });
                          }
                        }

                        if (messages.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: LocalizedText(
                                'You matched. Start a respectful conversation.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final mine = message.senderId == uid;

                            return _MessageBubble(message: message, mine: mine);
                          },
                        );
                      },
                    ),
                  ),
                  if (_blockedBetween)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.block),
                              SizedBox(width: 10),
                              Expanded(
                                child: LocalizedText(
                                  'Messaging is unavailable because one of you has blocked the other.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                              enabled: !_blockedBetween && !_checkingBlock,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 2000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: AppLanguageService.translate(
                                  'Write a message...',
                                ),
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed:
                                (_sending || _blockedBetween || _checkingBlock)
                                ? null
                                : _send,
                            icon: _sending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool mine;

  const _MessageBubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
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
              alignment: AlignmentDirectional.centerStart,
              child: LocalizedText(
                message.text,
                style: const TextStyle(height: 1.35),
              ),
            ),
            const SizedBox(height: 4),
            LocalizedText(
              _formatTime(message.sentAt),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (mine) ...[
              const SizedBox(height: 2),
              Icon(
                message.seenAt != null
                    ? Icons.done_all
                    : message.deliveredAt != null
                    ? Icons.done_all
                    : Icons.done,
                size: 16,
                color: message.seenAt != null
                    ? Colors.blue
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}
