import 'presentation/nisa_premium/nisa_premium.dart';
import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/interest.dart';
import 'models/user_profile.dart';
import 'services/interest_service.dart';
import 'services/match_service.dart';

class InterestsScreen extends StatefulWidget {
  final UserProfile profile;

  const InterestsScreen({super.key, required this.profile});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends LanguageAwareState<InterestsScreen> {
  List<Interest> _sent = [];
  List<Interest> _received = [];

  bool _loading = true;
  String? _error;

  String? get _userId => widget.profile.uid;

  @override
  void initState() {
    super.initState();
    _loadInterests();
  }

  Future<void> _loadInterests() async {
    final userId = _userId;

    if (userId == null || userId.isEmpty) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Your account is not properly linked.';
      });

      return;
    }

    try {
      final results = await Future.wait([
        InterestService.interestsForSender(userId),
        InterestService.interestsForReceiver(userId),
      ]);

      if (!mounted) return;

      setState(() {
        _sent = results[0];
        _received = results[1];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Could not load interests.';
      });
    }
  }

  Future<void> _accept(Interest interest) async {
    try {
      await InterestService.acceptInterest(interest.id);

      await MatchService.rebuildForPair(interest.senderId, interest.receiverId);

      await _loadInterests();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Interest accepted. You are now matched if the interest is mutual.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Future<void> _decline(Interest interest) async {
    try {
      await InterestService.declineInterest(interest.id);

      await _loadInterests();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Future<void> _cancel(Interest interest) async {
    try {
      await InterestService.cancelInterest(interest.id);

      await _loadInterests();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  String _statusText(InterestStatus status) {
    switch (status) {
      case InterestStatus.pending:
        return 'Pending';
      case InterestStatus.accepted:
        return 'Accepted';
      case InterestStatus.declined:
        return 'Declined';
      case InterestStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color _statusColor(BuildContext context, InterestStatus status) {
    final scheme = Theme.of(context).colorScheme;

    switch (status) {
      case InterestStatus.pending:
        return scheme.primary;
      case InterestStatus.accepted:
        return Colors.green;
      case InterestStatus.declined:
        return scheme.error;
      case InterestStatus.cancelled:
        return scheme.outline;
    }
  }

  Widget _statusChip(BuildContext context, InterestStatus status) {
    return Chip(
      label: LocalizedText(_statusText(status)),
      avatar: Icon(
        status == InterestStatus.accepted
            ? Icons.check
            : status == InterestStatus.declined
            ? Icons.close
            : status == InterestStatus.cancelled
            ? Icons.cancel_outlined
            : Icons.hourglass_top,
        size: 16,
        color: _statusColor(context, status),
      ),
    );
  }

  Widget _sentCard(Interest interest) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: LocalizedText(
          'Profile',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _statusChip(context, interest.status),
        ),
        trailing: interest.status == InterestStatus.pending
            ? IconButton(
                tooltip: AppLanguageService.translate('Cancel'),
                icon: const Icon(Icons.close),
                onPressed: () => _cancel(interest),
              )
            : null,
      ),
    );
  }

  Widget _receivedCard(Interest interest) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width: 12),
                Expanded(
                  child: LocalizedText(
                    'Someone is interested in you',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _statusChip(context, interest.status),
            if (interest.status == InterestStatus.pending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _decline(interest),
                      child: const LocalizedText('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _accept(interest),
                      child: const LocalizedText('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              LocalizedText(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadInterests,
                child: const LocalizedText('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInterests,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          LocalizedText(
            'Received',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (_received.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: LocalizedText('No received interests yet.')),
            )
          else
            ..._received.map(_receivedCard),

          const SizedBox(height: 28),

          LocalizedText(
            'Sent',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (_sent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: LocalizedText('You have not sent any interests yet.'),
              ),
            )
          else
            ..._sent.map(_sentCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Interests'),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(form: false, child: _content()),
    );
  }
}
