import 'presentation/nisa_premium/nisa_premium.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';
import 'services/app_language_service.dart';

import 'package:flutter/material.dart';

import 'candidate_details_screen.dart';
import 'models/candidate_profile.dart';
import 'models/interest.dart';
import 'models/user_profile.dart';
import 'widgets/profile_photo.dart';
import 'services/app_state.dart';
import 'services/candidate_service.dart';
import 'services/interest_service.dart';
import 'services/match_service.dart';

class IncomingInterestsScreen extends StatefulWidget {
  final UserProfile profile;

  const IncomingInterestsScreen({super.key, required this.profile});

  @override
  State<IncomingInterestsScreen> createState() =>
      _IncomingInterestsScreenState();
}

class _IncomingInterestsScreenState
    extends LanguageAwareState<IncomingInterestsScreen> {
  final List<Interest> _interests = [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    _loadInterests();
  }

  Future<void> _loadInterests() async {
    final uid = AppState.firebaseUser?.uid;

    if (uid == null || uid.isEmpty) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Please sign in again.';
      });

      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      debugPrint(
        'IncomingInterests: '
        'loading interests for $uid',
      );

      final allInterests = await InterestService.interestsForReceiver(uid);

      debugPrint(
        'IncomingInterests: '
        '${allInterests.length} '
        'incoming interest(s) found.',
      );

      final pending = allInterests
          .where((interest) => interest.status == InterestStatus.pending)
          .toList();

      if (!mounted) return;

      setState(() {
        _interests
          ..clear()
          ..addAll(pending);

        _loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('IncomingInterests LOAD ERROR: $e');

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _accept(Interest interest) async {
    final myUid = AppState.firebaseUser?.uid;

    if (myUid == null || myUid.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Please sign in again.')),
      );

      return;
    }

    debugPrint(
      'IncomingInterests: '
      'accepting ${interest.id}',
    );

    try {
      await InterestService.acceptInterest(interest.id);

      if (!mounted) return;

      setState(() {
        _interests.removeWhere((item) => item.id == interest.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Interest accepted. '
            'You are now matched.',
          ),
        ),
      );

      // Match creation is required, but it must not block this screen or
      // trigger another full Firestore read. It is initiated once here.
      () async {
        try {
          final match = await MatchService.createFromAcceptedInterest(
            senderId: interest.senderId,
            receiverId: myUid,
          );
          debugPrint('IncomingInterests: match created ${match.id}');
        } catch (error) {
          debugPrint('IncomingInterests: match creation deferred: $error');
        }
      }();
    } catch (e, stackTrace) {
      debugPrint(
        'IncomingInterests '
        'ACCEPT ERROR: $e',
      );

      debugPrintStack(stackTrace: stackTrace);

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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Interest declined.')),
      );

      await _loadInterests();
    } catch (e, stackTrace) {
      debugPrint(
        'IncomingInterests '
        'DECLINE ERROR: $e',
      );

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            'Could not decline '
            'interest: $e',
          ),
        ),
      );
    }
  }

  Future<void> _openSender(Interest interest) async {
    try {
      final candidate = await CandidateService.getCandidateById(
        interest.senderId,
      );

      if (!mounted) return;

      if (candidate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText(
              'This profile is '
              'not currently available.',
            ),
          ),
        );

        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CandidateDetailsScreen(
            candidate: candidate,
            currentUser: widget.profile,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            'Could not open '
            'profile: $e',
          ),
        ),
      );
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 250),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadInterests,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 150),
            const Icon(Icons.error_outline_rounded, size: 64),
            const SizedBox(height: 16),
            const LocalizedText(
              'Unable to load '
              'incoming interests',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            LocalizedText(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            Center(
              child: FilledButton.icon(
                onPressed: _loadInterests,
                icon: const Icon(Icons.refresh),
                label: const LocalizedText('Try Again'),
              ),
            ),
          ],
        ),
      );
    }

    if (_interests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadInterests,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Icon(
              Icons.favorite_border_rounded,
              size: 64,
              color: Colors.black38,
            ),
            SizedBox(height: 18),
            Center(
              child: LocalizedText(
                'No pending '
                'interests.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 36),
              child: LocalizedText(
                'New interests sent '
                'to you will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInterests,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _interests.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final interest = _interests[index];

          return _IncomingInterestCard(
            interest: interest,
            onAccept: () {
              _accept(interest);
            },
            onDecline: () {
              _decline(interest);
            },
            onOpenProfile: () {
              _openSender(interest);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Incoming Interests'),
        centerTitle: true,
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(form: false, child: _buildBody()),
    );
  }
}

class _IncomingInterestCard extends StatefulWidget {
  final Interest interest;

  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onOpenProfile;

  const _IncomingInterestCard({
    required this.interest,
    required this.onAccept,
    required this.onDecline,
    required this.onOpenProfile,
  });

  @override
  State<_IncomingInterestCard> createState() => _IncomingInterestCardState();
}

class _IncomingInterestCardState
    extends LanguageAwareState<_IncomingInterestCard> {
  CandidateProfile? _candidate;

  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _loadCandidate();
  }

  Future<void> _loadCandidate() async {
    try {
      final candidate = await CandidateService.getCandidateById(
        widget.interest.senderId,
      );

      if (!mounted) return;

      setState(() {
        _candidate = candidate;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final candidate = _candidate;

    if (candidate == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LocalizedText(
                'Nisa Member',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const LocalizedText(
                'Profile information '
                'is not currently available.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onDecline,
                      child: const LocalizedText('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.onAccept,
                      child: const LocalizedText('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenProfile,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProfilePhoto(
                    imageUrl: candidate.profilePhoto,
                    radius: 28,
                    fallbackText: candidate.name,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: LocalizedRichText(
                                spanBuilder: () => TextSpan(
                                  children: [
                                    TextSpan(text: candidate.name),
                                    const TextSpan(text: ', '),
                                    TextSpan(
                                      text: AppLanguageService.formatAgeNumber(
                                        candidate.age,
                                      ),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (candidate.verified) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.verified_rounded,
                                size: 18,
                                color: Color(0xFF7B2CBF),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        LocalizedText(
                          [candidate.city, candidate.country]
                              .where((value) => value.trim().isNotEmpty)
                              .join(', '),
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (candidate.education != null &&
                  candidate.education!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.school_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: LocalizedText(candidate.education!)),
                  ],
                ),
              ],

              if (candidate.profession != null &&
                  candidate.profession!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.work_outline_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: LocalizedText(candidate.profession!)),
                  ],
                ),
              ],

              const SizedBox(height: 18),

              const Divider(),

              const SizedBox(height: 10),

              const LocalizedText(
                'This person is interested '
                'in your matrimonial profile.',
                style: TextStyle(color: Colors.black54),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onDecline,
                      icon: const Icon(Icons.close),
                      label: const LocalizedText('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onAccept,
                      icon: const Icon(Icons.favorite_rounded),
                      label: const LocalizedText('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
