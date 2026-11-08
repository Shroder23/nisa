import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'widgets/localized_text.dart';

import 'api_chat_screen.dart';
import 'models/candidate_profile.dart';
import 'models/conversation.dart';
import 'models/interest.dart';
import 'models/user_profile.dart';
import 'services/api_profile_service.dart';
import 'services/api_safety_service.dart';
import 'services/api_social_service.dart';
import 'services/app_language_service.dart';
import 'widgets/api_profile_photo.dart';

class ApiCandidateDetailsScreen extends StatefulWidget {
  final CandidateProfile candidate;
  final UserProfile currentUser;

  const ApiCandidateDetailsScreen({
    super.key,
    required this.candidate,
    required this.currentUser,
  });

  @override
  State<ApiCandidateDetailsScreen> createState() =>
      _ApiCandidateDetailsScreenState();
}

class _ApiCandidateDetailsScreenState
    extends LanguageAwareState<ApiCandidateDetailsScreen> {
  late CandidateProfile _candidate = widget.candidate;
  bool _loading = true;
  bool _loadingRelation = true;
  bool _interestExists = false;
  bool _blocked = false;
  bool _sending = false;
  Conversation? _matchConversation;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadRelation();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ApiProfileService.getPublicProfile(
        widget.candidate.id,
      );
      if (!mounted) return;
      setState(() {
        _candidate = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadRelation() async {
    try {
      final results = await Future.wait<dynamic>([
        ApiSocialService.getSentInterests(),
        ApiSocialService.getIncomingInterests(),
        ApiSocialService.getConversations(),
        ApiSafetyService.isBlockedBetween(widget.candidate.id),
      ]);
      final sent = results[0] as List<Interest>;
      final received = results[1] as List<Interest>;
      final conversations = results[2] as List<Conversation>;
      final myId = widget.currentUser.uid ?? '';
      final matchingConversations = conversations.where((item) {
        return item.otherParticipant(myId) == widget.candidate.id;
      }).toList();
      if (!mounted) return;
      setState(() {
        _interestExists =
            sent.any((item) => item.receiverId == widget.candidate.id) ||
            received.any((item) => item.senderId == widget.candidate.id);
        _matchConversation = matchingConversations.isEmpty
            ? null
            : matchingConversations.first;
        _blocked = results[3] == true;
        _loadingRelation = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRelation = false);
    }
  }

  Future<void> _sendInterest() async {
    if (_sending || _interestExists || _blocked || _matchConversation != null) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ApiSocialService.sendInterest(_candidate.id);
      if (!mounted) return;
      setState(() {
        _interestExists = true;
        _sending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Interest sent successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openChat() async {
    final conversation = _matchConversation;
    if (conversation == null || _blocked) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApiChatScreen(
          conversationId: conversation.id,
          otherUserId: _candidate.id,
          otherUserName: _candidate.name,
          otherUserPhoto: _candidate.profilePhoto,
        ),
      ),
    );
  }

  Future<void> _report() async {
    var reportDetails = '';
    var reason = 'Inappropriate profile';
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const LocalizedText('Report profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                itemHeight: null,
                isDense: false,
                initialValue: reason,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Reason'),
                ),
                items: const [
                  DropdownMenuItem(value: 'Spam', child: LocalizedText('Spam')),
                  DropdownMenuItem(
                    value: 'Inappropriate profile',
                    child: LocalizedText('Inappropriate profile'),
                  ),
                  DropdownMenuItem(
                    value: 'Fake or misleading information',
                    child: LocalizedText('Fake or misleading information'),
                  ),
                  DropdownMenuItem(
                    value: 'Harassment or disrespectful behavior',
                    child: LocalizedText(
                      'Harassment or disrespectful behavior',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Scam or suspicious activity',
                    child: LocalizedText('Scam or suspicious activity'),
                  ),
                  DropdownMenuItem(
                    value: 'Already married / dishonest status',
                    child: LocalizedText('Already married / dishonest status'),
                  ),
                  DropdownMenuItem(
                    value: 'Other',
                    child: LocalizedText('Other'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => reason = value);
                },
              ),
              TextField(
                onChanged: (value) => reportDetails = value,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Details (optional)'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedText('Submit report'),
            ),
          ],
        ),
      ),
    );
    if (submitted == true && mounted) {
      try {
        await ApiSafetyService.submitReport(
          userId: _candidate.id,
          reason: reason,
          details: reportDetails.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: LocalizedText('Report submitted.')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: LocalizedText('Something went wrong. Please try again.'),
            ),
          );
        }
      }
    }
  }

  Future<void> _block() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedText(
          'Block {name}?',
          substitutions: {'name': _candidate.name},
        ),
        content: const LocalizedText(
          'This profile will be hidden, and neither of you can send interests or messages.',
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
    try {
      await ApiSafetyService.blockUser(_candidate.id);
      if (mounted) setState(() => _blocked = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('Something went wrong. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    final location = [
      candidate.city,
      candidate.country,
    ].where((value) => value.trim().isNotEmpty).join(', ');
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Profile'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'report') _report();
              if (value == 'block') _block();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: LocalizedText('Report')),
              PopupMenuItem(value: 'block', child: LocalizedText('Block')),
            ],
          ),
        ],
      ),
      body: NisaPageBody(
        form: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: LocalizedText(
                    'Something went wrong. Please try again.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: ApiProfilePhoto(
                      imageUrl: candidate.profilePhoto,
                      radius: 58,
                      fallbackText: candidate.name,
                      showBorder: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          candidate.age > 0
                              ? '${candidate.name}, ${candidate.age}'
                              : candidate.name,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (candidate.verified) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: AppLanguageService.translate(
                            'Parent verified',
                          ),
                          child: Icon(
                            Icons.verified,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Center(child: Text(location)),
                  ],
                  if (candidate.verificationPending) ...[
                    const SizedBox(height: 6),
                    const Center(child: LocalizedText('Verification pending')),
                  ],
                  const SizedBox(height: 24),
                  _detailsCard('Personal details', [
                    _detail('Gender', candidate.gender),
                    _detail('Marital status', candidate.maritalStatus),
                    _detail('Height', candidate.height),
                    _detail('Country', candidate.country),
                    _detail('City', candidate.city),
                  ]),
                  _detailsCard('Education and career', [
                    _detail('Education', candidate.education),
                    _detail('Profession', candidate.profession),
                  ]),
                  _detailsCard('Matrimonial information', [
                    _detail('Religious practice', candidate.religiousPractice),
                    _detail('Relocation', candidate.relocation),
                  ]),
                  const SizedBox(height: 12),
                  if (_blocked)
                    const LocalizedText(
                      'Interaction is unavailable because one of you has blocked the other.',
                    ),
                  if (!_blocked &&
                      !_loadingRelation &&
                      _matchConversation != null)
                    FilledButton.icon(
                      onPressed: _openChat,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const LocalizedText('Open messages'),
                    )
                  else if (!_blocked && _interestExists)
                    const FilledButton(
                      onPressed: null,
                      child: LocalizedText('Interest already exists'),
                    )
                  else if (!_blocked)
                    FilledButton.icon(
                      onPressed: _loadingRelation || _sending
                          ? null
                          : _sendInterest,
                      icon: const Icon(Icons.favorite_border),
                      label: Text(_sending ? 'Sending…' : 'Send interest'),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _detailsCard(String title, List<Widget> rows) {
    final visible = rows
        .where((row) => row is _ProfileDetailRow && row.value.isNotEmpty)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...visible,
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String? value) =>
      _ProfileDetailRow(label, value?.trim() ?? '');
}

class _ProfileDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileDetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
