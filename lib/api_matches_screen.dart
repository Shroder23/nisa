import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'api_candidate_details_screen.dart';
import 'api_chat_screen.dart';
import 'models/candidate_profile.dart';
import 'models/conversation.dart';
import 'models/user_profile.dart';
import 'services/api_auth_service.dart';
import 'services/api_profile_service.dart';
import 'services/api_presence_service.dart';
import 'services/api_social_service.dart';
import 'services/app_language_service.dart';
import 'widgets/api_profile_photo.dart';
import 'widgets/localized_text.dart';

/// PostgreSQL-backed list of accepted matches.
class ApiMatchesScreen extends StatefulWidget {
  final bool showAppBar;
  final UserProfile? currentUser;

  const ApiMatchesScreen({super.key, this.showAppBar = true, this.currentUser});

  @override
  State<ApiMatchesScreen> createState() => _ApiMatchesScreenState();
}

class _ApiMatchesScreenState extends LanguageAwareState<ApiMatchesScreen> {
  late Future<List<Conversation>> _matches =
      ApiSocialService.getConversations();

  Future<void> _refresh() async {
    final request = ApiSocialService.getConversations();
    setState(() {
      _matches = request;
    });
    await request;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        ApiAuthService.currentAccount.value?['id']?.toString() ?? '';
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const LocalizedText('Matches'),
              actions: [
                IconButton(
                  tooltip: AppLanguageService.translate('Refresh'),
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      body: NisaPageBody(
        form: false,
        child: FutureBuilder<List<Conversation>>(
          future: _matches,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MatchesMessage(
                message: 'Could not load matches: ${snapshot.error}',
                onRetry: _refresh,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final matches = snapshot.data!;
            if (matches.isEmpty) {
              return const _MatchesMessage(
                message: 'No matches yet. When you accept an incoming interest, the match will appear here.',
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: matches.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final match = matches[index];
                  final otherId = match.otherParticipant(currentUserId);
                  final name =
                      match.participantNames[otherId]?.trim().isNotEmpty == true
                      ? match.participantNames[otherId]!.trim()
                      : 'Nisa member';
                  return _MatchCard(
                    conversation: match,
                    otherUserId: otherId,
                    fallbackName: name,
                    fallbackPhoto: match.participantPhotos[otherId],
                    currentUser: widget.currentUser,
                    onReturn: _refresh,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MatchCard extends StatefulWidget {
  final Conversation conversation;
  final String otherUserId;
  final String fallbackName;
  final String? fallbackPhoto;
  final UserProfile? currentUser;
  final Future<void> Function() onReturn;

  const _MatchCard({
    required this.conversation,
    required this.otherUserId,
    required this.fallbackName,
    required this.fallbackPhoto,
    required this.currentUser,
    required this.onReturn,
  });

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  late final Future<CandidateProfile> _candidate =
      ApiProfileService.getPublicProfile(widget.otherUserId);
  bool _openingChat = false;

  Future<void> _openProfile(CandidateProfile candidate) async {
    final user = widget.currentUser;
    if (user == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            ApiCandidateDetailsScreen(currentUser: user, candidate: candidate),
      ),
    );
    if (mounted) await widget.onReturn();
  }

  Future<void> _openChat(CandidateProfile? candidate) async {
    if (_openingChat) return;
    setState(() => _openingChat = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ApiChatScreen(
            conversationId: widget.conversation.id,
            otherUserName: candidate?.name ?? widget.fallbackName,
            otherUserId: widget.otherUserId,
            otherUserPhoto: candidate?.profilePhoto ?? widget.fallbackPhoto,
          ),
        ),
      );
      if (mounted) await widget.onReturn();
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CandidateProfile>(
    future: _candidate,
    builder: (context, snapshot) {
      final candidate = snapshot.data;
      final name = candidate?.name ?? widget.fallbackName;
      final photo = candidate?.profilePhoto ?? widget.fallbackPhoto;
      final details = candidate == null
          ? 'Matched on Nisa'
          : [
              if (candidate.age > 0)
                AppLanguageService.formatAgeNumber(candidate.age),
              if (candidate.city.isNotEmpty) candidate.city,
              if (candidate.country.isNotEmpty) candidate.country,
              if (candidate.profession?.trim().isNotEmpty == true)
                candidate.profession!.trim(),
            ].join(' · ');
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                leading: ApiProfilePhoto(
                  imageUrl: photo,
                  radius: 31,
                  fallbackText: name,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        candidate != null && candidate.age > 0
                            ? '${candidate.name}, ${AppLanguageService.formatAgeNumber(candidate.age)}'
                            : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (candidate?.verified == true)
                      const Icon(
                        Icons.verified_rounded,
                        size: 18,
                        color: Color(0xFF6B4C91),
                      ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      ApiPresenceLabel(
                        userId: widget.otherUserId,
                        compact: true,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                onTap: candidate == null ? null : () => _openProfile(candidate),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: candidate == null
                          ? null
                          : () => _openProfile(candidate),
                      icon: const Icon(Icons.person_outline),
                      label: const LocalizedText('View Profile'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openingChat
                          ? null
                          : () => _openChat(candidate),
                      icon: _openingChat
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chat_bubble_outline),
                      label: const LocalizedText('Message'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _MatchesMessage extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _MatchesMessage({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_border, size: 52),
          const SizedBox(height: 12),
          LocalizedText(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const LocalizedText('Try again'),
            ),
        ],
      ),
    ),
  );
}
