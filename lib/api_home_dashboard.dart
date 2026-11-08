import 'package:flutter/material.dart';

import 'presentation/nisa_premium/nisa_premium.dart';

import 'api_candidate_details_screen.dart';
import 'models/candidate_profile.dart';
import 'models/discovery_filters.dart';
import 'models/interest.dart';
import 'models/user_profile.dart';
import 'report_user_screen.dart';
import 'services/api_discovery_service.dart';
import 'services/api_location_service.dart';
import 'services/api_safety_service.dart';
import 'services/api_social_service.dart';
import 'services/app_language_service.dart';
import 'widgets/api_candidate_cards.dart';
import 'widgets/api_profile_photo.dart';
import 'widgets/localized_text.dart';
import 'widgets/home_member_card.dart';

typedef HomeNearbyLoader = Future<ApiDiscoveryPage> Function(
  DiscoveryFilters filters,
  int limit,
);
typedef HomeRecommendationLoader = Future<ApiDiscoveryPage> Function(int limit);

class ApiHomeDashboard extends StatefulWidget {
  final UserProfile profile;
  final int profileCompletion;
  final VoidCallback onEditProfile;
  final VoidCallback onSeeAll;
  final HomeNearbyLoader? nearbyLoader;
  final HomeRecommendationLoader? recommendationLoader;
  final Future<bool> Function()? locationSharingLoader;
  final Future<int> Function()? radiusLoader;
  final Future<void> Function()? enableLocation;
  final Future<void> Function()? disableLocation;
  final Future<void> Function(int miles)? radiusSaver;
  final Future<List<Interest>> Function()? interestsLoader;
  final Future<Interest> Function(String profileId)? interestSender;
  final Future<void> Function(String profileId)? blockUser;
  final Future<void> Function(CandidateProfile profile)? openCandidate;
  final Future<void> Function(CandidateProfile profile)? reportCandidate;

  const ApiHomeDashboard({
    super.key,
    required this.profile,
    required this.profileCompletion,
    required this.onEditProfile,
    required this.onSeeAll,
    this.nearbyLoader,
    this.recommendationLoader,
    this.locationSharingLoader,
    this.radiusLoader,
    this.enableLocation,
    this.disableLocation,
    this.radiusSaver,
    this.interestsLoader,
    this.interestSender,
    this.blockUser,
    this.openCandidate,
    this.reportCandidate,
  });

  @override
  State<ApiHomeDashboard> createState() => _ApiHomeDashboardState();
}

class _ApiHomeDashboardState extends State<ApiHomeDashboard> {
  static const int _nearbyLimit = 8;
  static const int _recommendationLimit = 20;

  final Map<String, InterestStatus> _interestStatuses = {};
  List<CandidateProfile> _nearby = const [];
  List<CandidateProfile> _recommendations = const [];
  bool _checkingLocation = true;
  bool _locationEnabled = false;
  bool _locationBusy = false;
  bool _nearbyLoading = false;
  bool _recommendationsLoading = true;
  bool _locationStatusUnavailable = false;
  bool _interestStatusUnavailable = false;
  int _radiusMiles = ApiLocationService.defaultRadiusMiles;
  String? _nearbyError;
  String? _recommendationsError;
  String? _sendingTo;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant ApiHomeDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.preferences != widget.profile.preferences) {
      _loadAll();
    }
  }

  HomeNearbyLoader get _loadNearbyPage =>
      widget.nearbyLoader ??
      (filters, limit) => ApiDiscoveryService.getRecommendations(
        currentGender: widget.profile.gender,
        filters: filters,
        limit: limit,
      );

  HomeRecommendationLoader get _loadRecommendationPage =>
      widget.recommendationLoader ??
      (limit) => ApiDiscoveryService.getRecommendations(
        currentGender: widget.profile.gender,
        filters: const DiscoveryFilters(minimumAge: 18, maximumAge: 100),
        limit: limit,
      );

  Future<void> _loadAll() async {
    if (mounted) {
      setState(() {
        _checkingLocation = true;
        _recommendationsLoading = true;
        _nearbyError = null;
        _recommendationsError = null;
      });
    }

    bool sharing = false;
    var radius = ApiLocationService.defaultRadiusMiles;
    List<Interest> interests = const [];
    var locationStatusUnavailable = false;
    var interestStatusUnavailable = false;
    await Future.wait([
      () async {
        try {
          sharing =
              await (widget.locationSharingLoader ??
                  ApiLocationService.isSharingEnabled)();
        } catch (_) {
          sharing = false;
          locationStatusUnavailable = true;
        }
      }(),
      () async {
        try {
          radius =
              await (widget.radiusLoader ??
                  ApiLocationService.selectedRadiusMiles)();
        } catch (_) {
          radius = ApiLocationService.defaultRadiusMiles;
        }
      }(),
      () async {
        try {
          interests =
              await (widget.interestsLoader ??
                  ApiSocialService.getSentInterests)();
        } catch (_) {
          interests = const [];
          interestStatusUnavailable = true;
        }
      }(),
    ]);
    if (!mounted) return;
    setState(() {
      _locationEnabled = sharing;
      _locationStatusUnavailable = locationStatusUnavailable;
      _interestStatusUnavailable = interestStatusUnavailable;
      _checkingLocation = false;
      _radiusMiles = radius.clamp(5, 500);
      _interestStatuses
        ..clear()
        ..addEntries(
          interests
              .where((interest) => interest.receiverId.isNotEmpty)
              .map(
                (interest) => MapEntry(interest.receiverId, interest.status),
              ),
        );
      if (!sharing) _nearby = const [];
    });

    await Future.wait([
      _loadRecommendations(),
      if (sharing) _loadNearby() else Future<void>.value(),
    ]);
  }

  Future<void> _loadNearby() async {
    if (!_locationEnabled) {
      if (mounted) {
        setState(() {
          _nearby = const [];
          _nearbyError = null;
          _nearbyLoading = false;
        });
      }
      return;
    }
    setState(() {
      _nearbyLoading = true;
      _nearbyError = null;
    });
    try {
      final filters = ApiDiscoveryService.defaultFiltersFor(
        widget.profile,
        prioritizeNearby: true,
        maxDistanceMiles: _radiusMiles,
      );
      final page = await _loadNearbyPage(filters, _nearbyLimit);
      if (!mounted) return;
      setState(() {
        _nearby = _deduplicate(page.profiles);
        _nearbyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nearby = const [];
        _nearbyError = 'Something went wrong. Please try again.';
        _nearbyLoading = false;
      });
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _recommendationsLoading = true;
      _recommendationsError = null;
    });
    try {
      final page = await _loadRecommendationPage(_recommendationLimit);
      if (!mounted) return;
      setState(() {
        _recommendations = _deduplicate(page.profiles);
        _recommendationsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recommendations = const [];
        _recommendationsError = 'Something went wrong. Please try again.';
        _recommendationsLoading = false;
      });
    }
  }

  List<CandidateProfile> _deduplicate(List<CandidateProfile> profiles) {
    final result = <CandidateProfile>[];
    final seen = <String>{};
    for (final profile in profiles) {
      if (profile.id.isNotEmpty && seen.add(profile.id)) result.add(profile);
    }
    return result;
  }

  List<CandidateProfile> get _visibleRecommendations {
    final nearbyIds = _nearby.map((profile) => profile.id).toSet();
    return _recommendations
        .where((profile) => !nearbyIds.contains(profile.id))
        .toList(growable: false);
  }

  Future<void> _enableNearby() async {
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
    try {
      await (widget.enableLocation ??
          ApiLocationService.updateApproximateLocation)();
      if (!mounted) return;
      setState(() {
        _locationEnabled = true;
        _nearby = const [];
      });
      await _loadNearby();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLanguageService.translate(message))),
      );
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  Future<void> _disableNearby() async {
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
    try {
      await (widget.disableLocation ?? ApiLocationService.stopSharing)();
      if (!mounted) return;
      setState(() {
        _locationEnabled = false;
        _nearby = const [];
        _nearbyError = null;
        _nearbyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Location sharing could not be changed. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  Future<void> _saveRadius(int miles) async {
    setState(() => _radiusMiles = miles.clamp(5, 500));
    await (widget.radiusSaver ?? ApiLocationService.saveSelectedRadiusMiles)(
      _radiusMiles,
    );
    if (mounted) await _loadNearby();
  }

  Future<void> _sendInterest(CandidateProfile profile) async {
    final current = _interestStatuses[profile.id];
    if (_sendingTo != null ||
        profile.hasExistingInterest ||
        current == InterestStatus.pending ||
        current == InterestStatus.accepted) {
      return;
    }
    setState(() => _sendingTo = profile.id);
    try {
      final interest =
          await (widget.interestSender ?? ApiSocialService.sendInterest)(
            profile.id,
          );
      if (!mounted) return;
      setState(() => _interestStatuses[profile.id] = interest.status);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('Interest sent.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingTo = null);
    }
  }

  Future<void> _openProfile(CandidateProfile profile) async {
    if (widget.openCandidate != null) {
      await widget.openCandidate!(profile);
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ApiCandidateDetailsScreen(
            candidate: profile,
            currentUser: widget.profile,
          ),
        ),
      );
    }
    if (mounted) await _loadAll();
  }

  Future<void> _report(CandidateProfile profile) async {
    if (widget.reportCandidate != null) {
      await widget.reportCandidate!(profile);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReportUserScreen(
          reportedUserId: profile.id,
          reportedUserName: profile.name,
        ),
      ),
    );
  }

  Future<void> _block(CandidateProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: LocalizedText(
          'Block {name}?',
          substitutions: {'name': profile.name},
        ),
        content: const LocalizedText(
          'This profile will be hidden, and neither of you can send interests or messages. They will not be notified.',
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
      await (widget.blockUser ?? ApiSafetyService.blockUser)(profile.id);
      if (!mounted) return;
      setState(() {
        _nearby = _nearby.where((item) => item.id != profile.id).toList();
        _recommendations = _recommendations
            .where((item) => item.id != profile.id)
            .toList();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('User blocked.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Widget _welcomeCard() => NisaWelcomeCard(
    greeting: AppLanguageService.translate('Welcome back'),
    name: widget.profile.name,
    subtitle: AppLanguageService.translate('Find a meaningful connection.'),
    avatar: ApiProfilePhoto(
      imageUrl: widget.profile.profilePhoto,
      radius: 32,
      fallbackText: widget.profile.name,
      enablePreview: false,
    ),
  );

  Future<void> _locationSettings() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (_, updateSheet) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LocalizedText('Search radius (miles)'),
            LocalizedText(
              '{miles} miles',
              substitutions: {
                'miles': AppLanguageService.formatNumber(_radiusMiles),
              },
            ),
            Slider(
              min: 5,
              max: 500,
              divisions: 99,
              value: _radiusMiles.toDouble(),
              onChanged: (value) =>
                  updateSheet(() => _radiusMiles = value.round()),
              onChangeEnd: (value) => _saveRadius(value.round()),
            ),
            TextButton(
              onPressed: _locationBusy
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      _disableNearby();
                    },
              child: const LocalizedText('Stop sharing location'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _nearbyContent() {
    if (_checkingLocation) {
      return const SizedBox(
        key: ValueKey('nearby-loading'),
        height: 110,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_locationStatusUnavailable) {
      return ApiInlineState(
        key: const ValueKey('location-status-error'),
        icon: Icons.cloud_off_outlined,
        message: 'Something went wrong. Please try again.',
        actionLabel: 'Try again',
        onAction: _loadAll,
      );
    }
    if (!_locationEnabled) {
      return ApiInlineState(
        key: const ValueKey('location-disabled'),
        icon: Icons.location_off_outlined,
        message: 'Share an approximate location to rank nearby profiles first. It is never shown to other members.',
        actionLabel: 'Use my location',
        onAction: _enableNearby,
        busy: _locationBusy,
      );
    }
    if (_nearbyLoading) {
      return const SizedBox(
        key: ValueKey('nearby-loading'),
        height: 110,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_nearbyError != null) {
      return ApiInlineState(
        key: const ValueKey('nearby-error'),
        icon: Icons.cloud_off_outlined,
        message: _nearbyError!,
        actionLabel: 'Try again',
        onAction: _loadNearby,
      );
    }
    if (_nearby.isEmpty) {
      return const ApiInlineState(
        key: ValueKey('nearby-empty'),
        icon: Icons.location_searching_rounded,
        message: 'No matching profiles are available yet. Try again later.',
      );
    }
    return SizedBox(
      key: const ValueKey('nearby-rail'),
      height: _nearby
          .map(
            (profile) => ApiNearbyProfileCard.contentHeight(context, profile),
          )
          .reduce((a, b) => a > b ? a : b),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        primary: false,
        itemCount: _nearby.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final profile = _nearby[index];
          return ApiNearbyProfileCard(
            profile: profile,
            interestStatus: _interestStatuses[profile.id],
            existingInterest: profile.hasExistingInterest,
            sendingInterest: _sendingTo == profile.id,
            onOpen: () => _openProfile(profile),
            onInterest: () => _sendInterest(profile),
            onBlock: () => _block(profile),
            onReport: () => _report(profile),
          );
        },
      ),
    );
  }

  Widget _recommendationsContent() {
    if (_recommendationsLoading) {
      return const SizedBox(
        key: ValueKey('recommendations-loading'),
        height: 140,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_recommendationsError != null) {
      return ApiInlineState(
        key: const ValueKey('recommendations-error'),
        icon: Icons.cloud_off_outlined,
        message: _recommendationsError!,
        actionLabel: 'Try again',
        onAction: _loadRecommendations,
      );
    }
    if (_visibleRecommendations.isEmpty) {
      return const ApiInlineState(
        key: ValueKey('recommendations-empty'),
        icon: Icons.favorite_outline_rounded,
        message: 'No matching profiles are available yet. Try again later.',
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _visibleRecommendations;
    return NisaPremiumHomeBody(
      onRefresh: _loadAll,
      welcome: _welcomeCard(),
      nearbyHeading: NisaSectionHeading(
        key: const ValueKey('nearby-section'),
        title: AppLanguageService.translate('Nearby Profiles'),
        icon: Icons.location_on,
        actionKey: const ValueKey('see-all-Nearby Profiles'),
        actionLabel: AppLanguageService.translate('See all'),
        onAction: widget.onSeeAll,
      ),
      nearbyContent: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_locationEnabled)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _locationSettings,
                icon: const Icon(Icons.tune, size: 18),
                label: LocalizedText(
                  '{miles} miles',
                  substitutions: {
                    'miles': AppLanguageService.formatNumber(_radiusMiles),
                  },
                ),
              ),
            ),
          _nearbyContent(),
        ],
      ),
      recommendationHeading: NisaSectionHeading(
        key: const ValueKey('recommendations-list'),
        title: AppLanguageService.translate('Recommended for you'),
        icon: Icons.star_rounded,
      ),
      recommendationNotice: _interestStatusUnavailable
          ? ApiInlineState(
              icon: Icons.sync_problem_outlined,
              message: 'Something went wrong. Please try again.',
              actionLabel: 'Try again',
              onAction: _loadAll,
            )
          : null,
      recommendationStatus:
          _recommendationsLoading || _recommendationsError != null
          ? _recommendationsContent()
          : null,
      recommendationCount: profiles.length,
      recommendationEmpty: _recommendationsContent(),
      recommendationBuilder: (context, index) {
        final profile = profiles[index];
        return HomeMemberCard(
          profile: profile,
          interestStatus: _interestStatuses[profile.id],
          existingInterest: profile.hasExistingInterest,
          sendingInterest: _sendingTo == profile.id,
          onOpen: () => _openProfile(profile),
          onInterest: () => _sendInterest(profile),
          onBlock: () => _block(profile),
          onReport: () => _report(profile),
        );
      },
    );
  }
}
