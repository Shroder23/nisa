import 'presentation/nisa_premium/nisa_premium.dart';
import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'models/candidate_profile.dart';
import 'models/match.dart';
import 'models/user_profile.dart';
import 'services/interest_service.dart';
import 'services/block_service.dart';
import 'report_user_screen.dart';
import 'services/conversation_service.dart';
import 'services/discovery_service.dart';
import 'services/match_service.dart';
import 'widgets/profile_photo.dart';

class CandidateDetailsScreen extends StatefulWidget {
  final CandidateProfile candidate;
  final UserProfile currentUser;

  /// These are optional so profile details works from Search, Home,
  /// Matches, and Messages without losing older behavior.
  final bool isMatched;
  final MatrimonialMatch? match;

  const CandidateDetailsScreen({
    super.key,
    required this.candidate,
    required this.currentUser,
    this.isMatched = false,
    this.match,
  });

  @override
  State<CandidateDetailsScreen> createState() => _CandidateDetailsScreenState();
}

class _CandidateDetailsScreenState
    extends LanguageAwareState<CandidateDetailsScreen> {
  bool _interestSent = false;
  bool _isCheckingInterest = true;
  bool _isSendingInterest = false;
  bool _isMatched = false;
  bool _openingChat = false;
  bool _isBlockedBetween = false;
  bool _blocking = false;

  @override
  void initState() {
    super.initState();
    _checkExistingInterest();
  }

  Future<void> _checkExistingInterest() async {
    final senderId = widget.currentUser.uid;

    if (senderId == null || senderId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isCheckingInterest = false;
      });
      return;
    }

    try {
      final results = await Future.wait([
        InterestService.findInterest(senderId, widget.candidate.id),
        InterestService.findInterest(widget.candidate.id, senderId),
        MatchService.areMatched(senderId, widget.candidate.id),
        BlockService.isBlockedBetween(senderId, widget.candidate.id),
      ]);

      if (!mounted) return;

      final outgoing = results[0];
      final incoming = results[1];
      final matched =
          widget.isMatched || widget.match != null || results[2] == true;
      final blocked = results[3] == true;

      setState(() {
        _interestSent = outgoing != null || incoming != null;
        _isMatched = matched;
        _isBlockedBetween = blocked;
        _isCheckingInterest = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isCheckingInterest = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Future<void> _sendInterest() async {
    if (_isSendingInterest || _interestSent || _isBlockedBetween) {
      return;
    }

    final senderId = widget.currentUser.uid;

    if (senderId == null || senderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Your account is not properly linked. '
            'Please sign in again.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _isSendingInterest = true;
    });

    try {
      await InterestService.sendInterest(
        senderId: senderId,
        receiverId: widget.candidate.id,
      );

      if (!mounted) return;

      setState(() {
        _interestSent = true;
        _isSendingInterest = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Interest sent successfully.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSendingInterest = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openChat() async {
    if (_openingChat || _isBlockedBetween) return;

    final uid = widget.currentUser.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Please sign in again.')),
      );
      return;
    }

    setState(() => _openingChat = true);

    try {
      final match =
          widget.match ??
          await MatchService.findMatch(uid, widget.candidate.id);

      if (match == null) {
        throw StateError('Messaging is available only after a match.');
      }

      final conversation = await ConversationService.getOrCreateForMatch(
        match,
        uid,
      );

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversation.id,
            otherUserId: widget.candidate.id,
            otherUserName: widget.candidate.name,
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
    } finally {
      if (mounted) {
        setState(() => _openingChat = false);
      }
    }
  }

  Future<void> _reportUser() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportUserScreen(
          reportedUserId: widget.candidate.id,
          reportedUserName: widget.candidate.name,
        ),
      ),
    );
  }

  Future<void> _blockUser() async {
    if (_blocking) return;
    final uid = widget.currentUser.uid;
    if (uid == null || uid.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedText(
          'Block {name}?',
          substitutions: {'name': widget.candidate.name},
        ),
        content: const LocalizedText(
          'You will no longer be able to send interests or messages to each other. The profile will also be hidden from search.',
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
        blockedId: widget.candidate.id,
      );
      if (!mounted) return;
      setState(() {
        _isBlockedBetween = true;
        _blocking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('This user has been blocked.')),
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

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final compatibility = DiscoveryService.compatibilityFor(
      widget.currentUser,
      candidate,
    );

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Profile'),
        centerTitle: true,
        actions: [
          const LanguageSelectorButton(),
          PopupMenuButton<String>(
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
                  leading: Icon(Icons.block),
                  title: LocalizedText('Block'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: NisaPageBody(
        form: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // --------------------------------------------------
            // PROFILE HEADER
            // --------------------------------------------------

            Center(
              child: ProfilePhoto(
                imageUrl: candidate.profilePhoto,
                radius: 55,
                fallbackText: candidate.name,
                showBorder: true,
              ),
            ),

            const SizedBox(height: 18),

            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: LocalizedText(
                      candidate.age > 0
                          ? '${candidate.name}, ${AppLanguageService.formatAgeNumber(candidate.age)}'
                          : candidate.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),

                  if (candidate.verified) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: AppLanguageService.translate('Parent verified'),
                      child: Icon(
                        Icons.verified,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            Center(
              child: LocalizedRichText(
                spanBuilder: () => TextSpan(
                  children: [
                    TextSpan(text: candidate.city),
                    const TextSpan(text: ', '),
                    TextSpan(text: candidate.country),
                  ],
                ),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),

            if (candidate.verificationPending)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(
                  child: LocalizedText(
                    'Verification pending',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),

            const SizedBox(height: 28),

            // --------------------------------------------------
            // COMPATIBILITY
            // --------------------------------------------------
            _InfoCard(
              title: AppLanguageService.translate('Compatibility'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LocalizedText(
                        '{percent}%',
                        substitutions: {
                          'percent': AppLanguageService.formatNumber(
                            compatibility.percentage,
                          ),
                        },
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: LocalizedText(
                          compatibility.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: compatibility.percentage / 100,
                  ),
                  const SizedBox(height: 12),
                  LocalizedText(
                    'Based only on the matrimonial preferences you have specified. '
                    'Use this as a guide for review, not as a judgment of personal suitability.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (compatibility.strengths.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    LocalizedText(
                      'Aligned preferences',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: compatibility.strengths
                          .map(
                            (item) => Chip(
                              avatar: const Icon(Icons.check, size: 16),
                              label: LocalizedText(item),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (compatibility.differences.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: const LocalizedText('Preferences to review'),
                      children: compatibility.differences
                          .map(
                            (item) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.info_outline, size: 20),
                              title: LocalizedText(item),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),

            // --------------------------------------------------
            // ABOUT
            // --------------------------------------------------
            _InfoCard(
              title: AppLanguageService.translate('About'),
              child: LocalizedText(
                candidate.about?.isNotEmpty == true
                    ? candidate.about!
                    : 'No introduction provided.',
              ),
            ),

            // --------------------------------------------------
            // PERSONAL DETAILS
            // --------------------------------------------------
            _InfoCard(
              title: AppLanguageService.translate('Personal Details'),
              child: Column(
                children: [
                  _InfoRow(
                    label: AppLanguageService.translate('Age'),
                    value: AppLanguageService.formatAgeNumber(candidate.age),
                  ),
                  _InfoRow(
                    label: AppLanguageService.translate('City'),
                    value: candidate.city,
                  ),
                  _InfoRow(
                    label: AppLanguageService.translate('Country'),
                    value: candidate.country,
                  ),
                  _InfoRow(
                    label: AppLanguageService.translate('Marital Status'),
                    value: candidate.maritalStatus.isEmpty
                        ? 'Not specified'
                        : candidate.maritalStatus,
                  ),
                  _InfoRow(
                    label: AppLanguageService.translate('Height'),
                    value: candidate.height == null
                        ? 'Not specified'
                        : AppLanguageService.formatHeight(candidate.height!),
                  ),
                ],
              ),
            ),

            // --------------------------------------------------
            // EDUCATION & CAREER
            // --------------------------------------------------
            _InfoCard(
              title: AppLanguageService.translate('Education & Career'),
              child: Column(
                children: [
                  _InfoRow(
                    label: AppLanguageService.translate('Education'),
                    value: candidate.education ?? 'Not specified',
                  ),
                  _InfoRow(
                    label: AppLanguageService.translate('Profession'),
                    value: candidate.profession ?? 'Not specified',
                  ),
                ],
              ),
            ),

            // --------------------------------------------------
            // MATRIMONIAL INFORMATION
            // --------------------------------------------------
            _InfoCard(
              title: AppLanguageService.translate('Matrimonial Information'),
              child: Column(
                children: [
                  _InfoRow(
                    label: AppLanguageService.translate('Religious Practice'),
                    value: candidate.religiousPractice ?? 'Not specified',
                  ),
                  _InfoRow(
                    label: AppLanguageService.translate('Relocation'),
                    value: candidate.relocation ?? 'Not specified',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // --------------------------------------------------
            // MATCH / INTEREST ACTION
            // --------------------------------------------------
            if (_isBlockedBetween)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.block),
                      SizedBox(width: 12),
                      Expanded(
                        child: LocalizedText(
                          'Interaction is unavailable because one of you has blocked the other.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            SizedBox(
              height: 56,
              child: _isBlockedBetween
                  ? const FilledButton(
                      onPressed: null,
                      child: LocalizedText('Interaction Unavailable'),
                    )
                  : _isMatched
                  ? FilledButton.icon(
                      onPressed: _openingChat ? null : _openChat,
                      icon: _openingChat
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chat_bubble_outline),
                      label: const LocalizedText('Message'),
                    )
                  : FilledButton.icon(
                      onPressed:
                          (_interestSent ||
                              _isSendingInterest ||
                              _isCheckingInterest)
                          ? null
                          : _sendInterest,
                      icon: _isCheckingInterest || _isSendingInterest
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _interestSent
                                  ? Icons.check
                                  : Icons.favorite_border,
                            ),
                      label: LocalizedText(
                        _isCheckingInterest
                            ? 'Checking...'
                            : _isSendingInterest
                            ? 'Sending...'
                            : _interestSent
                            ? 'Interest Sent'
                            : 'Send Interest',
                      ),
                    ),
            ),

            const SizedBox(height: 12),

            // --------------------------------------------------
            // PRIVACY MESSAGE
            // --------------------------------------------------
            LocalizedText(
              'Contact details remain private until mutual acceptance.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: 10),

            LocalizedText(
              _isMatched ? 'You are matched. Messaging is now available.' : 'Messaging becomes available after an incoming interest is accepted.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: LocalizedText(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: LocalizedText(value)),
        ],
      ),
    );
  }
}
