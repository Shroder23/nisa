import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

import 'api_conversations_screen.dart';
import 'models/interest.dart';
import 'report_user_screen.dart';
import 'services/api_safety_service.dart';
import 'services/api_social_service.dart';

/// PostgreSQL-backed incoming-interest review and response screen.
class ApiIncomingInterestsScreen extends StatefulWidget {
  const ApiIncomingInterestsScreen({super.key});

  @override
  State<ApiIncomingInterestsScreen> createState() =>
      _ApiIncomingInterestsScreenState();
}

class _ApiIncomingInterestsScreenState
    extends State<ApiIncomingInterestsScreen> {
  List<Interest> _interests = const [];
  final Set<String> _responding = {};
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
      final interests = await ApiSocialService.getIncomingInterests();
      if (!mounted) return;
      setState(() {
        _interests = interests
            .where((interest) => interest.status == InterestStatus.pending)
            .toList();
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

  Future<void> _respond(Interest interest, {required bool accept}) async {
    if (!_responding.add(interest.id)) return;
    setState(() {});
    try {
      final matchId = await ApiSocialService.respondToInterest(
        interest.id,
        accept: accept,
      );
      if (!mounted) return;
      setState(() {
        _interests.removeWhere((item) => item.id == interest.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? (matchId == null
                      ? 'Interest accepted.'
                      : 'Accepted. A match and conversation were created.')
                : 'Interest declined.',
          ),
        ),
      );
      if (accept && matchId != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApiConversationsScreen()),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      _responding.remove(interest.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _report(Interest interest, String name) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportUserScreen(
          reportedUserId: interest.senderId,
          reportedUserName: name,
        ),
      ),
    );
  }

  Future<void> _block(Interest interest, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: LocalizedText('Block {name}?', substitutions: {'name': name}),
        content: const LocalizedText(
          'This profile will be hidden and neither of you can send interests or messages. They will not be notified.',
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
    try {
      await ApiSafetyService.blockUser(interest.senderId);
      if (!mounted) return;
      setState(() => _interests.removeWhere((item) => item.id == interest.id));
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Incoming interests'),
        actions: [
          IconButton(
            tooltip: AppLanguageService.translate('Refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: NisaPageBody(
        form: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _InterestMessage(message: _error!, onRetry: _load)
            : _interests.isEmpty
            ? const _InterestMessage(message: 'No pending interests yet.')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _interests.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _interestCard(_interests[index]),
                ),
              ),
      ),
    );
  }

  Widget _interestCard(Interest interest) {
    final name = interest.otherUserName?.trim().isNotEmpty == true
        ? interest.otherUserName!.trim()
        : 'Nisa member';
    final location = [
      interest.otherUserCity,
      interest.otherUserCountry,
    ].where((value) => value?.trim().isNotEmpty == true).join(', ');
    final waiting = _responding.contains(interest.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(name[0].toUpperCase())),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (location.isNotEmpty) Text(location),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: AppLanguageService.translate('Safety options'),
                  onSelected: (value) {
                    if (value == 'report') _report(interest, name);
                    if (value == 'block') _block(interest, name);
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
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: waiting
                        ? null
                        : () => _respond(interest, accept: false),
                    child: const LocalizedText('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: waiting
                        ? null
                        : () => _respond(interest, accept: true),
                    child: waiting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const LocalizedText('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InterestMessage extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _InterestMessage({required this.message, this.onRetry});

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
