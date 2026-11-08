import 'widgets/localized_text.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'main.dart' show AuthGate;

import 'notification_screen.dart';
import 'family_invitations_screen.dart';
import 'candidate_details_screen.dart';
import 'chat_screen.dart';
import 'edit_profile_screen.dart';
import 'family_screen.dart';
import 'blocked_users_screen.dart';
import 'admin_verification_list_screen.dart';
import 'matrimonial_preferences_screen.dart';
import 'models/candidate_profile.dart';
import 'models/discovery_filters.dart';
import 'models/conversation.dart';
import 'models/match.dart';
import 'models/profile_recommendation.dart';
import 'models/user_profile.dart';
import 'services/app_state.dart';
import 'services/app_language_service.dart';
import 'services/candidate_service.dart';
import 'services/discovery_service.dart';
import 'services/conversation_service.dart';
import 'services/match_service.dart';
import 'services/recommendation_service.dart';
import 'verification_screen.dart';
import 'incoming_interests_screen.dart';
import 'services/notification_service.dart';
import 'services/message_service.dart';
import 'services/photo_service.dart';
import 'services/location_service.dart';
import 'widgets/profile_photo.dart';

class HomeScreen extends StatefulWidget {
  final UserProfile profile;

  const HomeScreen({super.key, required this.profile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends LanguageAwareState<HomeScreen> {
  int _selectedIndex = 0;
  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomePage(profile: _profile),
      _SearchPage(profile: _profile),
      const _MatchesPage(),
      const _MessagesPage(),
      _ProfilePage(profile: _profile),
    ];

    return Scaffold(
      appBar: AppBar(
        title: LocalizedText(_titleForIndex(_selectedIndex)),
        centerTitle: true,
        actions: const [
          _HomeLanguageButton(),
          _NotificationBell(),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) async {
          if (index == 4) {
            try {
              await AppState.loadUser();

              final refreshed = AppState.currentUser;

              if (refreshed != null) {
                _profile = refreshed;
              }
            } catch (e) {
              debugPrint('Profile refresh failed: $e');
            }
          }

          if (!mounted) return;

          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: AppLanguageService.translate('Home'),
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: AppLanguageService.translate('Search'),
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: AppLanguageService.translate('Matches'),
          ),
          NavigationDestination(
            icon: const _MessagesNavigationIcon(selected: false),
            selectedIcon: const _MessagesNavigationIcon(selected: true),
            label: AppLanguageService.translate('Messages'),
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: AppLanguageService.translate('Profile'),
          ),
        ],
      ),
    );
  }

  String _titleForIndex(int index) {
    switch (index) {
      case 0:
        return 'Nisa';
      case 1:
        return AppLanguageService.translate('Search');
      case 2:
        return AppLanguageService.translate('Matches');
      case 3:
        return AppLanguageService.translate('Messages');
      case 4:
        return AppLanguageService.translate('Profile');
      default:
        return 'Nisa';
    }
  }
}

class _MessagesNavigationIcon extends StatelessWidget {
  final bool selected;

  const _MessagesNavigationIcon({required this.selected});

  @override
  Widget build(BuildContext context) {
    final uid = AppState.currentUser?.uid ?? AppState.firebaseUser?.uid;
    final icon = Icon(selected ? Icons.chat_bubble : Icons.chat_bubble_outline);

    if (uid == null || uid.isEmpty) return icon;

    return StreamBuilder<int>(
      stream: ConversationService.unreadCount(uid),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        if (unread <= 0) return icon;

        return Badge(
          label: Text(unread > 99 ? '99+' : unread.toString()),
          child: icon,
        );
      },
    );
  }
}

class _HomeLanguageButton extends StatelessWidget {
  const _HomeLanguageButton();

  Future<void> _openPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: LocalizedText(
                      AppLanguageService.translate('Choose language'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: AppLanguageService.languages.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final language = AppLanguageService.languages[index];
                      final selected =
                          language.code ==
                          AppLanguageService.selectedCode.value;
                      return ListTile(
                        leading: const Icon(Icons.language_rounded),
                        title: LocalizedText(language.name),
                        subtitle: LocalizedText(language.nativeName),
                        trailing: selected
                            ? const Icon(Icons.check_circle_rounded)
                            : null,
                        onTap: () {
                          unawaited(AppLanguageService.setLanguage(language));
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.selectedCode,
      builder: (context, _, _) => IconButton(
        tooltip: AppLanguageService.translate('Choose language'),
        icon: const Icon(Icons.language_rounded),
        onPressed: () => _openPicker(context),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    final uid = AppState.currentUser?.uid ?? AppState.firebaseUser?.uid;

    if (uid == null || uid.isEmpty) {
      return IconButton(
        tooltip: AppLanguageService.translate('Notifications'),
        icon: const Icon(Icons.notifications_outlined),
        onPressed: null,
      );
    }

    return StreamBuilder<int>(
      stream: NotificationService.unreadCount(uid),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;

        final icon = unread > 0
            ? Badge(
                label: LocalizedText(unread > 99 ? '99+' : unread.toString()),
                child: const Icon(Icons.notifications_outlined),
              )
            : const Icon(Icons.notifications_outlined);

        return IconButton(
          tooltip: AppLanguageService.translate('Notifications'),
          icon: icon,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            );
          },
        );
      },
    );
  }
}

// ------------------------------------------------------------
// HOME PAGE ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â REAL RECOMMENDATIONS
// ------------------------------------------------------------

class _HomePage extends StatefulWidget {
  final UserProfile profile;
  const _HomePage({required this.profile});

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends LanguageAwareState<_HomePage> {
  List<ProfileRecommendation> _items = const [];
  bool _loading = true;
  String? _error;
  StreamSubscription<List<MatrimonialMatch>>? _matchSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    final uid = widget.profile.uid;
    if (uid != null && uid.isNotEmpty) {
      _matchSubscription = MatchService.watchMatchesForUser(uid).listen((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _matchSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await RecommendationService.getRecommendations(
        currentUser: widget.profile,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _open(CandidateProfile candidate) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CandidateDetailsScreen(
          candidate: candidate,
          currentUser: widget.profile,
        ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7B2CBF);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          LocalizedText(
            'Welcome, {name}',
            substitutions: {'name': widget.profile.name},
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          LocalizedText(
            AppLanguageService.translate('Find a meaningful connection.'),
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  widget.profile.isVerified
                      ? Icons.verified
                      : widget.profile.verificationPending
                      ? Icons.hourglass_top
                      : Icons.verified_outlined,
                  color: purple,
                ),
                const SizedBox(width: 12),
                LocalizedText(
                  widget.profile.isVerified
                      ? AppLanguageService.translate('Parent verified')
                      : widget.profile.verificationPending
                      ? AppLanguageService.translate(
                          'Parent verification pending',
                        )
                      : AppLanguageService.translate(
                          'Parent verification not completed',
                        ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          LocalizedText(
            AppLanguageService.translate('Recommended for you'),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          LocalizedText(
            AppLanguageService.translate(
              'Real profiles ranked using your matrimonial preferences.',
            ),
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 70),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_loading && _error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, size: 44),
                    const SizedBox(height: 10),
                    LocalizedText('Unable to load recommendations.'),
                    const SizedBox(height: 8),
                    LocalizedText(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: LocalizedText('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          if (!_loading && _error == null && _items.isEmpty)
            Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.people_outline, size: 52),
                    SizedBox(height: 12),
                    LocalizedText(
                      AppLanguageService.translate('No recommendations yet.'),
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    LocalizedText(
                      AppLanguageService.translate(
                        'As more eligible profiles join Nisa, compatible profiles will appear here.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          if (!_loading && _error == null)
            ..._items.map(
              (r) => _RecommendationCard(
                recommendation: r,
                onTap: () => _open(r.candidate),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final ProfileRecommendation recommendation;
  final VoidCallback onTap;

  const _RecommendationCard({
    required this.recommendation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = recommendation.candidate;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProfilePhoto(
                    imageUrl: c.profilePhoto,
                    radius: 29,
                    fallbackText: c.name,
                  ),
                  const SizedBox(width: 13),
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
                                    TextSpan(text: c.name),
                                    const TextSpan(text: ', '),
                                    TextSpan(
                                      text: AppLanguageService.formatAgeNumber(
                                        c.age,
                                      ),
                                    ),
                                  ],
                                ),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (c.verified) ...[
                              const SizedBox(width: 5),
                              const Icon(Icons.verified, size: 18),
                            ],
                          ],
                        ),
                        const SizedBox(height: 5),
                        LocalizedText(
                          [
                            if (c.city.isNotEmpty) c.city,
                            if (c.country.isNotEmpty) c.country,
                          ].join(', '),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              if (c.education?.isNotEmpty == true ||
                  c.profession?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                LocalizedText(
                  [
                    if (c.education?.isNotEmpty == true) c.education!,
                    if (c.profession?.isNotEmpty == true) c.profession!,
                  ].join(', '),
                ),
              ],
              if (recommendation.reasons.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: recommendation.reasons
                      .map(
                        (x) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: LocalizedText(
                            x,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (recommendation.hasExistingInterest) ...[
                const SizedBox(height: 8),
                LocalizedText(
                  AppLanguageService.translate('Interest already exists'),
                  style: TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.person_outline),
                  label: LocalizedText('View Profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// SEARCH
// ------------------------------------------------------------

class _SearchPage extends StatefulWidget {
  final UserProfile profile;

  const _SearchPage({required this.profile});

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends LanguageAwareState<_SearchPage> {
  List<DiscoveryResult> _results = const [];
  late DiscoveryFilters _filters;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    // Discovery filters are temporary for this Search page. Always start
    // from the latest matrimonial preferences instead of restoring a stale
    // in-memory filter snapshot from an earlier preference set.
    _filters = _defaultDiscoveryFilters();

    _loadCandidates();
  }

  @override
  void didUpdateWidget(covariant _SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _filters = _defaultDiscoveryFilters();
      _loadCandidates();
    }
  }

  DiscoveryFilters _defaultDiscoveryFilters() {
    final p = _currentProfile.preferences;
    return DiscoveryFilters(
      minimumAge: p.minimumAge.clamp(18, 100),
      maximumAge: p.maximumAge.clamp(18, 100),
      country: p.country,
      city: p.city,
      maritalStatus: p.maritalStatus,
      education: p.education,
      minimumHeight: p.minimumHeight,
      maximumHeight: p.maximumHeight,
    );
  }

  UserProfile get _currentProfile {
    return AppState.currentUser ?? widget.profile;
  }

  Future<void> _loadCandidates() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await DiscoveryService.discover(
        currentUser: _currentProfile,
        filters: _filters,
      );

      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openFilters() async {
    final updated = await showModalBottomSheet<DiscoveryFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _DiscoveryFilterSheet(initial: _filters, profile: _currentProfile),
    );

    if (updated == null || !mounted) return;

    setState(() {
      _filters = updated;
    });

    await _loadCandidates();
  }

  Future<void> _resetFilters() async {
    final defaults = _defaultDiscoveryFilters();

    setState(() {
      _filters = defaults;
    });

    await _loadCandidates();
  }

  @override
  Widget build(BuildContext context) {
    final filterChips = <Widget>[
      Chip(
        label: LocalizedRichText(
          spanBuilder: () => TextSpan(
            children: [
              TextSpan(text: AppLanguageService.translate('Age')),
              const TextSpan(text: ': '),
              TextSpan(
                text: AppLanguageService.formatNumber(_filters.minimumAge),
              ),
              const TextSpan(text: ' - '),
              TextSpan(
                text: AppLanguageService.formatNumber(_filters.maximumAge),
              ),
            ],
          ),
        ),
      ),
      if (_filters.country != null)
        Chip(label: LocalizedText(_filters.country!)),
      if (_filters.city != null) Chip(label: LocalizedText(_filters.city!)),
      if (_filters.maritalStatus != null)
        Chip(label: LocalizedText(_filters.maritalStatus!)),
      if (_filters.education != null)
        Chip(label: LocalizedText(_filters.education!)),
      if (_filters.verifiedOnly)
        Chip(
          avatar: const Icon(Icons.verified_outlined, size: 18),
          label: const LocalizedText('Verified only'),
        ),
      ActionChip(
        avatar: const Icon(Icons.restart_alt, size: 18),
        label: const LocalizedText('Clear filters'),
        onPressed: _resetFilters,
      ),
    ];

    return RefreshIndicator(
      onRefresh: _loadCandidates,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LocalizedText(
                  AppLanguageService.translate('Discover'),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Badge(
                label: Text(
                  AppLanguageService.formatNumber(_filters.activeFilterCount),
                ),
                child: IconButton.filledTonal(
                  tooltip: AppLanguageService.translate('Discovery filters'),
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LocalizedText(
            AppLanguageService.translate(
              'Your saved matrimonial preferences rank compatible profiles. Discovery filters only narrow the list when you choose them.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filterChips.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) => filterChips[index],
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_isLoading && _error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    LocalizedText(
                      AppLanguageService.translate('Unable to load profiles.'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    LocalizedText(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loadCandidates,
                      icon: const Icon(Icons.refresh),
                      label: LocalizedText('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          if (!_isLoading && _error == null && _results.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.manage_search, size: 52),
                    const SizedBox(height: 12),
                    LocalizedText(
                      AppLanguageService.translate(
                        'No profiles match these filters.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    LocalizedText(
                      AppLanguageService.translate(
                        'Broaden the discovery filters without changing your saved matrimonial preferences.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _openFilters,
                      icon: const Icon(Icons.tune),
                      label: LocalizedText('Adjust filters'),
                    ),
                  ],
                ),
              ),
            ),
          if (!_isLoading && _error == null)
            ..._results.map((result) {
              final candidate = result.candidate;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CandidateDetailsScreen(
                          candidate: candidate,
                          currentUser: widget.profile,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ProfilePhoto(
                          imageUrl: candidate.profilePhoto,
                          radius: 30,
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
                                    child: LocalizedText(
                                      candidate.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  if (candidate.verified) ...[
                                    const SizedBox(width: 5),
                                    Icon(
                                      Icons.verified,
                                      size: 18,
                                      semanticLabel:
                                          AppLanguageService.translate(
                                            'Parent verified',
                                          ),
                                    ),
                                  ],
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: LocalizedRichText(
                                      spanBuilder: () => TextSpan(
                                        children: [
                                          TextSpan(
                                            text:
                                                AppLanguageService.formatNumber(
                                                  result
                                                      .compatibility
                                                      .percentage,
                                                ),
                                          ),
                                          const TextSpan(text: '% '),
                                          TextSpan(
                                            text: AppLanguageService.translate(
                                              'match',
                                            ),
                                          ),
                                        ],
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondaryContainer,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              LocalizedText(
                                [
                                  if (candidate.age > 0)
                                    AppLanguageService.translateAge(
                                      '{age} years',
                                      age: candidate.age,
                                    ),
                                  if (candidate.city.isNotEmpty) candidate.city,
                                  if (candidate.country.isNotEmpty)
                                    candidate.country,
                                ].join(', '),
                              ),
                              if (candidate.education?.trim().isNotEmpty ==
                                  true) ...[
                                const SizedBox(height: 4),
                                LocalizedText(candidate.education!),
                              ],
                              const SizedBox(height: 7),
                              LocalizedText(
                                result.compatibility.label,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (result.reasons.isNotEmpty) ...[
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: result.reasons
                                      .take(3)
                                      .map(
                                        (reason) => Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: LocalizedText(reason),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _DiscoveryFilterSheet extends StatefulWidget {
  final DiscoveryFilters initial;
  final UserProfile profile;

  const _DiscoveryFilterSheet({required this.initial, required this.profile});

  @override
  State<_DiscoveryFilterSheet> createState() => _DiscoveryFilterSheetState();
}

class _DiscoveryFilterSheetState
    extends LanguageAwareState<_DiscoveryFilterSheet> {
  late RangeValues _age;
  String _country = '';
  String _city = '';
  String _maritalStatus = '';
  String _education = '';
  String _minimumHeight = '';
  String _maximumHeight = '';
  late bool _verifiedOnly;
  final _countryController = TextEditingController();
  final _cityController = TextEditingController();

  bool _loadingOptions = true;
  String? _optionsError;
  DiscoveryFilterOptions? _options;
  // Keep the current preference city and the Any city option usable while the
  // complete worldwide catalogue is fetched in the background.
  List<String> _cities = <String>[LocationService.anyCity];
  bool _allCitiesLoading = false;
  bool _allCitiesLoaded = false;

  @override
  void initState() {
    super.initState();
    _age = RangeValues(
      widget.initial.minimumAge.toDouble(),
      widget.initial.maximumAge.toDouble(),
    );
    _country = _normaliseAny(
      widget.initial.country,
      LocationService.anyCountry,
    );
    _city = _normaliseAny(widget.initial.city, LocationService.anyCity);
    final savedCity = widget.profile.preferences.city?.trim() ?? '';
    if (_city.isEmpty &&
        savedCity.isNotEmpty &&
        savedCity.toLowerCase() != LocationService.anyCity.toLowerCase()) {
      _city = savedCity;
    }
    _countryController.text = _country.isEmpty
        ? LocationService.anyCountry
        : _country;
    _cityController.text = _city.isEmpty ? LocationService.anyCity : _city;
    _maritalStatus = widget.initial.maritalStatus?.trim() ?? '';
    _education = _normalizeEducation(widget.initial.education);
    _minimumHeight = widget.initial.minimumHeight?.trim() ?? '';
    _maximumHeight = widget.initial.maximumHeight?.trim() ?? '';
    _verifiedOnly = widget.initial.verifiedOnly;
    if (_country.isNotEmpty) _loadCities(_country);
    _loadOptions();
  }

  Future<void> _loadCities(String country) async {
    final values = await LocationService.cities(country);
    if (!mounted) return;
    setState(() {
      _cities = {..._cities, ...values, LocationService.anyCity}.toList();
    });
  }

  Future<void> _loadAllCitiesInBackground() async {
    if (_allCitiesLoading || _allCitiesLoaded) return;
    setState(() => _allCitiesLoading = true);
    final values = await LocationService.allCities();
    if (!mounted) return;
    setState(() {
      _cities = {..._cities, ...values, LocationService.anyCity}.toList();
      _allCitiesLoading = false;
      _allCitiesLoaded = true;
    });
  }

  String _normaliseAny(String? value, String anyValue) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == anyValue.toLowerCase()) {
      return '';
    }
    return text;
  }

  Future<String?> _countryChoice() async {
    final search = TextEditingController();
    var choices = <String>[
      'Pakistan',
      LocationService.anyCountry,
      'India',
      'Bangladesh',
      'United Arab Emirates',
      'Saudi Arabia',
      'Qatar',
      'United Kingdom',
      'United States',
      'Canada',
      'Australia',
      'Malaysia',
      'Turkey',
    ];
    var loading = true;
    var requested = false;

    List<String> ordered(List<String> values) {
      final unique = values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
      unique.sort((a, b) {
        int priority(String value) {
          final normalized = value.toLowerCase();
          if (normalized == 'pakistan') return 0;
          if (normalized == LocationService.anyCountry.toLowerCase()) return 1;
          return 2;
        }

        final priorityResult = priority(a).compareTo(priority(b));
        return priorityResult != 0
            ? priorityResult
            : a.toLowerCase().compareTo(b.toLowerCase());
      });
      return unique;
    }

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          if (!requested) {
            requested = true;
            LocationService.countries().then((loaded) {
              if (dialogContext.mounted) {
                refresh(() {
                  choices = ordered(loaded);
                  loading = false;
                });
              }
            });
          }
          final query = search.text.trim().toLowerCase();
          final shown = choices
              .where((value) => value.toLowerCase().contains(query))
              .toList();
          return AlertDialog(
            title: const LocalizedText('Preferred Country'),
            content: SizedBox(
              height: 420,
              width: 420,
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: AppLanguageService.translate(
                        'Search countries',
                      ),
                    ),
                    onChanged: (_) => refresh(() {}),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: LinearProgressIndicator(),
                    ),
                  Expanded(
                    child: ListView(
                      children: shown
                          .map(
                            (value) => ListTile(
                              title: LocalizedText(value),
                              selected:
                                  (_country.isEmpty
                                      ? LocationService.anyCountry
                                      : _country) ==
                                  value,
                              onTap: () => Navigator.pop(dialogContext, value),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickCountry() async {
    final selected = await _countryChoice();
    if (selected == null || !mounted) return;
    final normalized = _normaliseAny(selected, LocationService.anyCountry);
    setState(() {
      _country = normalized;
      _city = '';
      _countryController.text = normalized.isEmpty
          ? LocationService.anyCountry
          : normalized;
      _cityController.text = LocationService.anyCity;
    });
    if (normalized.isEmpty) {
      unawaited(_loadAllCitiesInBackground());
    } else {
      unawaited(_loadCities(normalized));
    }
  }

  Future<String?> _pickLocation(
    String title,
    List<String> values,
    String current, {
    List<String> Function()? valuesBuilder,
    Future<void>? onValuesLoaded,
  }) async {
    final search = TextEditingController();
    var refreshRequested = false;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          if (!refreshRequested && onValuesLoaded != null) {
            refreshRequested = true;
            onValuesLoaded.then((_) {
              if (dialogContext.mounted) refresh(() {});
            });
          }
          final query = search.text.trim().toLowerCase();
          final available = valuesBuilder?.call() ?? values;
          final shown = available
              .where((value) => value.toLowerCase().contains(query))
              .toList();
          return AlertDialog(
            title: LocalizedText(title),
            content: SizedBox(
              height: 420,
              width: 420,
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: AppLanguageService.translate('Search'),
                    ),
                    onChanged: (_) => refresh(() {}),
                  ),
                  Expanded(
                    child: ListView(
                      children: shown
                          .map(
                            (value) => ListTile(
                              title: LocalizedText(value),
                              selected:
                                  (current.isEmpty
                                      ? LocationService.anyCity
                                      : current) ==
                                  value,
                              onTap: () => Navigator.pop(dialogContext, value),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickCity() async {
    // The offline options open immediately; the complete catalogue is fetched
    // concurrently and merged into the same searchable list.
    final allCitiesLoading = _loadAllCitiesInBackground();
    final selected = await _pickLocation(
      'Preferred City',
      _cityOptions,
      _city,
      valuesBuilder: () => _cityOptions,
      onValuesLoaded: allCitiesLoading,
    );
    if (selected == null || !mounted) return;
    final normalized = _normaliseAny(selected, LocationService.anyCity);
    setState(() {
      _city = normalized;
      _cityController.text = normalized.isEmpty
          ? LocationService.anyCity
          : normalized;
    });
  }

  Future<void> _loadOptions() async {
    try {
      final options = await DiscoveryService.loadFilterOptions(
        currentUser: widget.profile,
      );
      if (!mounted) return;
      setState(() {
        _options = options;
        _loadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _optionsError = e.toString();
      });
    }
  }

  List<String> _withCurrent(List<String> values, String current) {
    final result = <String>{...values};
    if (current.trim().isNotEmpty) result.add(current.trim());
    final list = result.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  String _normalizeEducation(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty ||
        normalized.toLowerCase() == 'any' ||
        normalized.toLowerCase() == 'any education') {
      return '';
    }
    return normalized;
  }

  List<String> get _cityOptions => _withCurrent(
    {
      ..._cities,
      ...?_options?.citiesFor(_country.isEmpty ? null : _country),
      if (widget.profile.preferences.city?.trim().isNotEmpty == true)
        widget.profile.preferences.city!.trim(),
    }.toList(),
    _city,
  );

  List<String> get _maritalOptions => _withCurrent(
    _options?.maritalStatuses ??
        const [
          'Single (Never Married)',
          'Married',
          'Separated',
          'Divorced',
          'Widowed',
        ],
    _maritalStatus,
  );

  // Keep the education menu in the same high-to-low order used by the
  // registration and preferences screens. `_withCurrent` sorts generic
  // filter values alphabetically, which would destroy the qualification
  // hierarchy users rely on when choosing a minimum.
  List<String> get _educationOptions {
    final values = <String>[...LocationService.educationOptions];
    final current = _education.trim();
    if (current.isNotEmpty && !values.contains(current)) values.add(current);
    return values;
  }

  void _apply() {
    Navigator.pop(
      context,
      DiscoveryFilters(
        minimumAge: _age.start.round(),
        maximumAge: _age.end.round(),
        country: _country.isEmpty ? null : _country,
        city: _city.isEmpty ? null : _city,
        maritalStatus: _maritalStatus.isEmpty ? null : _maritalStatus,
        education: _education.isEmpty ? null : _education,
        minimumHeight: _minimumHeight.isEmpty ? null : _minimumHeight,
        maximumHeight: _maximumHeight.isEmpty ? null : _maximumHeight,
        verifiedOnly: _verifiedOnly,
      ),
    );
  }

  void _useSavedPreferences() {
    final preferences = widget.profile.preferences;
    setState(() {
      _age = RangeValues(
        preferences.minimumAge.clamp(18, 100).toDouble(),
        preferences.maximumAge.clamp(18, 100).toDouble(),
      );
      _country = _normaliseAny(preferences.country, LocationService.anyCountry);
      _city = _normaliseAny(preferences.city, LocationService.anyCity);
      _countryController.text = _country.isEmpty
          ? LocationService.anyCountry
          : _country;
      _cityController.text = _city.isEmpty ? LocationService.anyCity : _city;
      _maritalStatus = preferences.maritalStatus?.trim() ?? '';
      _education = _normalizeEducation(preferences.education);
      _minimumHeight = preferences.minimumHeight?.trim() ?? '';
      _maximumHeight = preferences.maximumHeight?.trim() ?? '';
      _verifiedOnly = false;
    });
  }

  @override
  void dispose() {
    _countryController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required String value,
    required List<String> values,
    required String anyLabel,
    VoidCallback? onTap,
    required ValueChanged<String?> onChanged,
  }) {
    final selectedValue =
        value.trim().isEmpty ||
            value.trim().toLowerCase() ==
                LocationService.anyCountry.toLowerCase() ||
            value.trim().toLowerCase() == LocationService.anyCity.toLowerCase()
        ? ''
        : value;
    final seen = <String>{};
    final menuValues = values.where((item) {
      final text = item.trim();
      final key = text.toLowerCase();
      if (text.isEmpty ||
          key == LocationService.anyCountry.toLowerCase() ||
          key == LocationService.anyCity.toLowerCase() ||
          key == anyLabel.trim().toLowerCase() ||
          !seen.add(key)) {
        return false;
      }
      return true;
    }).toList();
    return DropdownButtonFormField<String>(
      itemHeight: null,
      isDense: false,
      // Do not include the asynchronously changing list length in the key.
      // Re-keying a DropdownButton while its route is open can leave duplicate
      // menu entries and trigger Flutter's _dependents.isEmpty assertion.
      key: ValueKey('$label:$selectedValue'),
      initialValue: selectedValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: AppLanguageService.translate(label),
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<String>(value: '', child: LocalizedText(anyLabel)),
        ...menuValues.map(
          (item) => DropdownMenuItem<String>(
            value: item,
            child: item.contains("'")
                ? LocalizedHeightText(item, overflow: TextOverflow.ellipsis)
                : LocalizedText(item, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onTap: onTap,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + keyboardBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LocalizedText(
                  AppLanguageService.translate('Discovery filters'),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: AppLanguageService.translate('Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LocalizedRichText(
            spanBuilder: () => TextSpan(
              children: [
                TextSpan(text: AppLanguageService.translate('Age')),
                const TextSpan(text: ': '),
                TextSpan(
                  text: AppLanguageService.formatNumber(_age.start.round()),
                ),
                const TextSpan(text: ' - '),
                TextSpan(
                  text: AppLanguageService.formatNumber(_age.end.round()),
                ),
              ],
            ),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          RangeSlider(
            min: 18,
            max: 100,
            divisions: 82,
            labels: RangeLabels('${_age.start.round()}', '${_age.end.round()}'),
            values: _age,
            onChanged: (value) => setState(() => _age = value),
          ),
          const SizedBox(height: 8),
          if (_loadingOptions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
          if (_optionsError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LocalizedText(
                AppLanguageService.translate(
                  'Could not refresh every dropdown option. Saved choices remain available.',
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextFormField(
            controller: _countryController,
            readOnly: true,
            onTap: _pickCountry,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Preferred Country'),
              prefixIcon: const Icon(Icons.public),
              suffixIcon: const Icon(Icons.arrow_drop_down),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cityController,
            readOnly: true,
            maxLines: 1,
            onTap: _pickCity,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Preferred City'),
              prefixIcon: const Icon(Icons.location_city_outlined),
              suffixIcon: _allCitiesLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.arrow_drop_down),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _dropdown(
            label: AppLanguageService.translate('Marital status'),
            icon: Icons.favorite_border,
            value: _maritalStatus,
            values: _maritalOptions,
            anyLabel: 'Any marital status',
            onChanged: (value) => setState(() => _maritalStatus = value ?? ''),
          ),
          const SizedBox(height: 12),
          _dropdown(
            label: AppLanguageService.translate('Minimum Education'),
            icon: Icons.school_outlined,
            value: _education,
            values: _educationOptions,
            anyLabel: 'Any education',
            onChanged: (value) => setState(() => _education = value ?? ''),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: LocalizedText('Parent-verified profiles only'),
            value: _verifiedOnly,
            onChanged: (value) => setState(() => _verifiedOnly = value),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _useSavedPreferences,
                  icon: const Icon(Icons.restart_alt),
                  label: LocalizedText('My preferences'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.search),
                  label: LocalizedText('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------

class _MatchesPage extends StatelessWidget {
  const _MatchesPage();

  @override
  Widget build(BuildContext context) {
    final uid = AppState.firebaseUser?.uid;

    if (uid == null || uid.isEmpty) {
      return Center(child: LocalizedText('You are not signed in.'));
    }

    return StreamBuilder<List<MatrimonialMatch>>(
      stream: MatchService.watchMatchesForUser(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 100),
              const Icon(Icons.error_outline, size: 50),
              const SizedBox(height: 16),
              LocalizedText(
                AppLanguageService.translate('Unable to load matches.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const LocalizedText(
                'Something went wrong. Please try again.',
                textAlign: TextAlign.center,
              ),
            ],
          );
        }

        if (!snapshot.hasData) {
          return ListView(
            children: const [
              SizedBox(height: 250),
              Center(child: CircularProgressIndicator()),
            ],
          );
        }

        final matches = snapshot.data!;

        if (matches.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 150),
              const Icon(Icons.favorite_border, size: 70),
              const SizedBox(height: 20),
              LocalizedText(
                AppLanguageService.translate('No matches yet.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              LocalizedText(
                AppLanguageService.translate(
                  'When an incoming interest is accepted, the match will appear here.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: matches.length,
          itemBuilder: (context, index) {
            final match = matches[index];
            final otherUserId = match.userA == uid ? match.userB : match.userA;

            return _MatchCard(match: match, otherUserId: otherUserId);
          },
        );
      },
    );
  }
}

class _MatchCard extends StatefulWidget {
  final MatrimonialMatch match;
  final String otherUserId;

  const _MatchCard({required this.match, required this.otherUserId});

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends LanguageAwareState<_MatchCard> {
  CandidateProfile? _candidate;
  bool _loading = true;
  String? _error;
  bool _openingChat = false;

  @override
  void initState() {
    super.initState();
    _loadCandidate();
  }

  Future<void> _loadCandidate() async {
    try {
      final candidate = await CandidateService.getCandidateById(
        widget.otherUserId,
      );

      if (!mounted) return;
      setState(() {
        _candidate = candidate;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openChat() async {
    if (_openingChat) return;

    final uid = AppState.firebaseUser?.uid;
    final candidate = _candidate;

    if (uid == null || uid.isEmpty || candidate == null) return;

    setState(() => _openingChat = true);

    try {
      final conversation = await ConversationService.getOrCreateForMatch(
        widget.match,
        uid,
      );

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversation.id,
            otherUserId: candidate.id,
            otherUserName: candidate.name,
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

  void _openProfile() {
    final candidate = _candidate;
    final currentUser = AppState.currentUser;

    if (candidate == null || currentUser == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CandidateDetailsScreen(
          candidate: candidate,
          currentUser: currentUser,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        margin: EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: LocalizedText('Unable to load match'),
          subtitle: LocalizedText(_error!),
        ),
      );
    }

    final candidate = _candidate;
    if (candidate == null) {
      return Card(
        margin: EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: CircleAvatar(child: Icon(Icons.person)),
          title: LocalizedText('Profile unavailable'),
          subtitle: LocalizedText('This profile is no longer available.'),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: ProfilePhoto(
                imageUrl: candidate.profilePhoto,
                radius: 30,
                fallbackText: candidate.name,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: LocalizedText(
                      candidate.age > 0
                          ? '${candidate.name}, ${AppLanguageService.formatAgeNumber(candidate.age)}'
                          : candidate.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (candidate.verified) const Icon(Icons.verified, size: 19),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: LocalizedText(
                  [
                    if (candidate.city.isNotEmpty) candidate.city,
                    if (candidate.country.isNotEmpty) candidate.country,
                    if (candidate.profession?.isNotEmpty == true)
                      candidate.profession!,
                  ].join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onTap: _openProfile,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openProfile,
                    icon: const Icon(Icons.person_outline),
                    label: LocalizedText('View Profile'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openingChat ? null : _openChat,
                    icon: _openingChat
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chat_bubble_outline),
                    label: LocalizedText('Message'),
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

// ------------------------------------------------------------
// MESSAGES
// ------------------------------------------------------------

class _MessagesPage extends StatelessWidget {
  const _MessagesPage();

  @override
  Widget build(BuildContext context) {
    final uid = AppState.firebaseUser?.uid;

    if (uid == null || uid.isEmpty) {
      return Center(child: LocalizedText('You are not signed in.'));
    }

    return StreamBuilder<List<Conversation>>(
      stream: ConversationService.watchForUser(uid),
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
          return const Center(child: CircularProgressIndicator());
        }

        final conversations = snapshot.data!;

        if (conversations.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64),
                  SizedBox(height: 16),
                  LocalizedText(
                    AppLanguageService.translate('No conversations yet.'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  LocalizedText(
                    AppLanguageService.translate(
                      'Open one of your matches and tap Message to start.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            return _ConversationCard(
              conversation: conversations[index],
              currentUserId: uid,
            );
          },
        );
      },
    );
  }
}

class _ConversationCard extends StatefulWidget {
  final Conversation conversation;
  final String currentUserId;

  const _ConversationCard({
    required this.conversation,
    required this.currentUserId,
  });

  @override
  State<_ConversationCard> createState() => _ConversationCardState();
}

class _ConversationCardState extends LanguageAwareState<_ConversationCard> {
  CandidateProfile? _candidate;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCandidate();
    MessageService.markLatestDelivered(
      conversationId: widget.conversation.id,
      recipientId: widget.currentUserId,
    ).catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant _ConversationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      _candidate = null;
      _loading = true;
      _loadCandidate();
      MessageService.markLatestDelivered(
        conversationId: widget.conversation.id,
        recipientId: widget.currentUserId,
      ).catchError((_) {});
    }
  }

  Future<void> _loadCandidate() async {
    final otherId = widget.conversation.otherParticipant(widget.currentUserId);

    if (otherId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final candidate = await CandidateService.getCandidateById(otherId);
      if (!mounted) return;
      setState(() {
        _candidate = candidate;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openChat() async {
    final candidate = _candidate;
    final otherId = widget.conversation.otherParticipant(widget.currentUserId);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: widget.conversation.id,
          otherUserId: otherId,
          otherUserName: candidate?.name ?? 'Nisa Member',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: ListTile(
          leading: CircleAvatar(child: CircularProgressIndicator()),
          title: LocalizedText('Loading...'),
        ),
      );
    }

    final candidate = _candidate;
    final hasUnread = widget.conversation.unreadFor.contains(
      widget.currentUserId,
    );

    final preview = widget.conversation.lastMessage.isEmpty
        ? 'Matched ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â start a conversation'
        : widget.conversation.lastMessage;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: ProfilePhoto(
          imageUrl: candidate?.profilePhoto,
          radius: 26,
          fallbackText: candidate?.name ?? 'Nisa Member',
        ),
        title: Row(
          children: [
            Expanded(
              child: LocalizedText(
                candidate?.name ??
                    widget.conversation.participantNames[widget.conversation
                        .otherParticipant(widget.currentUserId)] ??
                    'Nisa Member',
                style: TextStyle(
                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ),
            if (hasUnread)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: LocalizedText(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openChat,
      ),
    );
  }
}

// ------------------------------------------------------------
// PROFILE
// ------------------------------------------------------------

class _ProfilePage extends StatefulWidget {
  final UserProfile profile;

  const _ProfilePage({required this.profile});

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends LanguageAwareState<_ProfilePage> {
  late UserProfile _profile;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  @override
  void didUpdateWidget(covariant _ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _profile = widget.profile;
    }
  }

  int get profileCompletion {
    int completed = 0;
    const total = 11;

    if (_profile.name.isNotEmpty) completed++;
    if (_profile.city.isNotEmpty) completed++;
    if (_profile.country != null && _profile.country!.isNotEmpty) completed++;
    if (_profile.height != null && _profile.height!.isNotEmpty) completed++;
    if (_profile.education != null && _profile.education!.isNotEmpty) {
      completed++;
    }
    if (_profile.profession != null && _profile.profession!.isNotEmpty) {
      completed++;
    }
    if (_profile.language != null && _profile.language!.isNotEmpty) completed++;
    if (_profile.aboutMe != null && _profile.aboutMe!.isNotEmpty) completed++;
    if (_profile.profilePhoto != null && _profile.profilePhoto!.isNotEmpty) {
      completed++;
    }
    if (_profile.preferences.country != null ||
        _profile.preferences.city != null) {
      completed++;
    }
    if (_profile.isVerified || _profile.verificationPending) completed++;

    return ((completed / total) * 100).round();
  }

  Future<void> _chooseProfilePhoto() async {
    if (_uploadingPhoto) return;

    final source = await showModalBottomSheet<_PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LocalizedText(
                  'Update Profile Photo',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const LocalizedText('Take a photo'),
                  subtitle: const LocalizedText('Use your camera'),
                  onTap: () => Navigator.pop(context, _PhotoSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const LocalizedText('Choose from gallery'),
                  subtitle: const LocalizedText('Select an existing photo'),
                  onTap: () => Navigator.pop(context, _PhotoSource.gallery),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const LocalizedText('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    await _uploadProfilePhoto(source);
  }

  Future<void> _uploadProfilePhoto(_PhotoSource source) async {
    setState(() => _uploadingPhoto = true);

    try {
      final file = source == _PhotoSource.camera
          ? await PhotoService.pickFromCamera()
          : await PhotoService.pickFromGallery();

      if (file == null) {
        if (mounted) {
          setState(() => _uploadingPhoto = false);
        }
        return;
      }

      await PhotoService.uploadPhoto(file: file, order: 0);

      await AppState.loadUser();

      final refreshed = AppState.currentUser;
      if (refreshed != null) {
        _profile = refreshed;
      }

      if (!mounted) return;

      setState(() => _uploadingPhoto = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Profile photo updated.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _uploadingPhoto = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: GestureDetector(
            onTap: _chooseProfilePhoto,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                ProfilePhoto(
                  imageUrl: profile.profilePhoto,
                  radius: 52,
                  fallbackText: profile.name,
                  showBorder: true,
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: _uploadingPhoto
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        Center(
          child: TextButton.icon(
            onPressed: _uploadingPhoto ? null : _chooseProfilePhoto,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: LocalizedText(
              profile.profilePhoto == null || profile.profilePhoto!.isEmpty
                  ? AppLanguageService.translate('Add profile photo')
                  : AppLanguageService.translate('Change profile photo'),
            ),
          ),
        ),

        const SizedBox(height: 6),

        Center(
          child: LocalizedText(
            profile.name,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(height: 4),

        Center(
          child: LocalizedRichText(
            spanBuilder: () => TextSpan(
              children: [
                TextSpan(text: profile.city),
                const TextSpan(text: ', '),
                TextSpan(
                  text: AppLanguageService.translate(
                    profile.country ?? 'Country not specified',
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Center(
          child: profile.isVerified
              ? Chip(
                  avatar: Icon(Icons.verified, size: 18),
                  label: LocalizedText('Parent verified'),
                )
              : profile.verificationPending
              ? Chip(
                  avatar: Icon(Icons.hourglass_top, size: 18),
                  label: LocalizedText('Parent verification pending'),
                )
              : Chip(
                  avatar: Icon(Icons.info_outline, size: 18),
                  label: LocalizedText('Parent verification not completed'),
                ),
        ),

        const SizedBox(height: 24),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    LocalizedText(
                      AppLanguageService.translate('Profile Completion'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    LocalizedText(
                      '{percent}%',
                      substitutions: {
                        'percent': AppLanguageService.formatNumber(
                          profileCompletion,
                        ),
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: profileCompletion / 100),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),

        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: LocalizedText('Edit Profile'),
                subtitle: LocalizedText('Update your personal information'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditProfileScreen(profile: profile),
                    ),
                  );

                  await AppState.loadUser();
                  final refreshed = AppState.currentUser;

                  if (mounted && refreshed != null) {
                    setState(() => _profile = refreshed);
                  }
                },
              ),

              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: LocalizedText('Matrimonial Preferences'),
                subtitle: LocalizedText('Change your preferred match criteria'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MatrimonialPreferencesScreen(
                        profile: profile,
                        isEditing: true,
                      ),
                    ),
                  );

                  await AppState.loadUser();
                  final refreshed = AppState.currentUser;

                  if (mounted && refreshed != null) {
                    setState(() => _profile = refreshed);
                  }
                },
              ),

              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: LocalizedText('Incoming Interests'),
                subtitle: LocalizedText('Review people who expressed interest'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          IncomingInterestsScreen(profile: profile),
                    ),
                  );
                },
              ),

              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.family_restroom),
                title: LocalizedText('Family / Guardian'),
                subtitle: LocalizedText('Invite a trusted family member'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FamilyScreen()),
                  );
                },
              ),

              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.mark_email_unread_outlined),
                title: LocalizedText('Family Invitations'),
                subtitle: LocalizedText(
                  'Review invitations sent to your email',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FamilyInvitationsScreen(),
                    ),
                  );
                },
              ),

              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: LocalizedText('Blocked Users'),
                subtitle: LocalizedText('Review and unblock people'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BlockedUsersScreen(),
                    ),
                  );
                },
              ),

              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: LocalizedText('Admin Verification'),
                subtitle: LocalizedText('Review pending verification requests'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminVerificationListScreen(),
                    ),
                  );
                },
              ),

              const Divider(height: 1),

              ListTile(
                leading: Icon(
                  profile.isVerified
                      ? Icons.verified
                      : profile.verificationPending
                      ? Icons.hourglass_top
                      : Icons.verified_user_outlined,
                ),
                title: LocalizedText('Verification'),
                subtitle: LocalizedText(
                  profile.isVerified
                      ? AppLanguageService.translate(
                          'Verified - no further action needed',
                        )
                      : profile.verificationPending
                      ? AppLanguageService.translate(
                          'Verification is under review',
                        )
                      : AppLanguageService.translate('Verify your profile'),
                ),
                trailing: Icon(
                  profile.isVerified
                      ? Icons.check_circle_outline
                      : Icons.chevron_right,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          VerificationScreen(profile: profile),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        Card(
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: LocalizedText('Log Out'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: LocalizedText('Log Out?'),
                    content: LocalizedText('Are you sure you want to log out?'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context, false);
                        },
                        child: LocalizedText('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(context, true);
                        },
                        child: LocalizedText('Log Out'),
                      ),
                    ],
                  );
                },
              );

              if (confirmed != true) {
                return;
              }

              try {
                await AppState.clearUser();
                if (!context.mounted) return;
                // Also recover sessions opened through a legacy Home route.
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (route) => false,
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: LocalizedText(
                      'Something went wrong. Please try again.',
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

enum _PhotoSource { camera, gallery }
