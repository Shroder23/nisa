import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/api_location_service.dart';

import 'api_candidate_details_screen.dart';
import 'models/candidate_profile.dart';
import 'models/discovery_filters.dart';
import 'models/interest.dart';
import 'models/user_profile.dart';
import 'services/api_discovery_service.dart';
import 'services/api_safety_service.dart';
import 'services/api_social_service.dart';
import 'services/location_service.dart';
import 'services/app_language_service.dart';
import 'report_user_screen.dart';
import 'widgets/api_candidate_cards.dart';
import 'widgets/localized_text.dart';

/// PostgreSQL-backed discovery surface for API-authenticated users.
class ApiDiscoveryScreen extends StatefulWidget {
  final UserProfile currentUser;
  final bool showAppBar;
  final bool showSearchTools;

  const ApiDiscoveryScreen({
    super.key,
    required this.currentUser,
    this.showAppBar = true,
    this.showSearchTools = true,
  });

  @override
  State<ApiDiscoveryScreen> createState() => _ApiDiscoveryScreenState();
}

class _ApiDiscoveryScreenState extends LanguageAwareState<ApiDiscoveryScreen> {
  static const int _pageSize = 50;
  final ScrollController _scrollController = ScrollController();
  List<CandidateProfile> _profiles = const [];
  final Map<String, InterestStatus> _interestStatuses = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _locationSharingEnabled = false;
  bool _nearestMode = false;
  bool _locationBusy = false;
  int _radiusMiles = 25;
  int _nextOffset = 0;
  String? _error;
  String? _sendingTo;
  late DiscoveryFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = _defaultFilters();
    _scrollController.addListener(_onScroll);
    _initializeLocationAndLoad();
  }

  Future<void> _initializeLocationAndLoad() async {
    try {
      _locationSharingEnabled = await ApiLocationService.isSharingEnabled();
    } catch (_) {
      _locationSharingEnabled = false;
    }
    try {
      _radiusMiles = await ApiLocationService.selectedRadiusMiles();
    } catch (_) {
      _radiusMiles = ApiLocationService.defaultRadiusMiles;
    }
    if (!mounted) return;
    _setNearbyFilterFlag();
    await _load();
  }

  void _setNearbyFilterFlag() {
    _filters = DiscoveryFilters(
      minimumAge: _filters.minimumAge,
      maximumAge: _filters.maximumAge,
      minimumHeight: _filters.minimumHeight,
      maximumHeight: _filters.maximumHeight,
      country: _filters.country,
      city: _filters.city,
      maritalStatus: _filters.maritalStatus,
      education: _filters.education,
      verifiedOnly: _filters.verifiedOnly,
      prioritizeNearby: _nearestMode,
      maxDistanceMiles: _nearestMode ? _radiusMiles : null,
      locationScopeExplicit: _filters.locationScopeExplicit,
    );
  }

  @override
  void didUpdateWidget(covariant ApiDiscoveryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser != widget.currentUser) {
      _nearestMode = false;
      _radiusMiles = 25;
      _filters = _defaultFilters();
      _initializeLocationAndLoad();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  DiscoveryFilters _defaultFilters() {
    return ApiDiscoveryService.defaultFiltersFor(
      widget.currentUser,
      prioritizeNearby: _nearestMode,
      maxDistanceMiles: _nearestMode ? _radiusMiles : null,
    );
  }

  String? _normalizedMaritalValue(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized == 'single' ||
        normalized == 'never married' ||
        normalized == 'single (never married)') {
      return 'never married';
    }
    return normalized.isEmpty ? null : normalized;
  }

  bool _matchesFilters(CandidateProfile profile) {
    final f = _filters;
    if (profile.age < f.minimumAge || profile.age > f.maximumAge) return false;
    bool isAny(String? value) {
      final v = value?.trim().toLowerCase() ?? '';
      return v.isEmpty ||
          v == 'any' ||
          v == 'any country' ||
          v == 'any city' ||
          v == 'any marital status' ||
          v == 'any education';
    }

    if ((!f.prioritizeNearby || f.locationScopeExplicit) &&
        !isAny(f.country) &&
        profile.country.toLowerCase() != f.country!.toLowerCase()) {
      return false;
    }
    if ((!f.prioritizeNearby || f.locationScopeExplicit) &&
        !isAny(f.city) &&
        profile.city.toLowerCase() != f.city!.toLowerCase()) {
      return false;
    }
    if (!isAny(f.maritalStatus) &&
        _normalizedMaritalValue(profile.maritalStatus) !=
            _normalizedMaritalValue(f.maritalStatus)) {
      return false;
    }
    if (!isAny(f.education) &&
        !LocationService.educationMeetsMinimum(
          f.education,
          profile.education,
        )) {
      return false;
    }
    if (f.verifiedOnly && !profile.verified) return false;
    final minHeight = _heightInches(f.minimumHeight);
    final maxHeight = _heightInches(f.maximumHeight);
    final candidateHeight = _heightInches(profile.height);
    if (candidateHeight != null &&
        minHeight != null &&
        candidateHeight < minHeight) {
      return false;
    }
    if (candidateHeight != null &&
        maxHeight != null &&
        candidateHeight > maxHeight) {
      return false;
    }
    return true;
  }

  int? _heightInches(String? value) {
    final match = RegExp(r"(\d+)\s*'\s*(\d+)").firstMatch(value?.trim() ?? '');
    if (match == null) return null;
    return int.parse(match.group(1)!) * 12 + int.parse(match.group(2)!);
  }

  Future<void> _changeLocationSharing({required bool enable}) async {
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
    try {
      if (enable) {
        // This is the only path that asks for device permission.
        await ApiLocationService.updateApproximateLocation();
      } else {
        await ApiLocationService.stopSharing();
      }
      if (!mounted) return;
      setState(() {
        _locationSharingEnabled = enable;
        _nearestMode = enable;
        if (enable && _radiusMiles < 5) _radiusMiles = 25;
        _setNearbyFilterFlag();
        _profiles = const [];
        _hasMore = false;
        _nextOffset = 0;
      });
      await _load();
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

  Future<void> _applyRadius() async {
    if (!_nearestMode) return;
    await ApiLocationService.saveSelectedRadiusMiles(_radiusMiles);
    setState(() {
      _setNearbyFilterFlag();
      _profiles = const [];
      _hasMore = false;
      _nextOffset = 0;
    });
    await _load();
  }

  Widget _locationBanner() => Card(
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText(
            _nearestMode ? 'Nearby recommendations are on' : 'Share an approximate location to rank nearby profiles first. It is never shown to other members.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _locationBusy
                    ? null
                    : () => _changeLocationSharing(enable: true),
                icon: _locationBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.near_me_outlined),
                label: const LocalizedText('Show nearest profiles'),
              ),
              if (_locationSharingEnabled)
                TextButton(
                  onPressed: _locationBusy
                      ? null
                      : () => _changeLocationSharing(enable: false),
                  child: const LocalizedText('Stop sharing location'),
                ),
            ],
          ),
          if (_nearestMode) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: LocalizedText('Search radius (miles)')),
                LocalizedText(
                  '{miles} miles',
                  substitutions: {
                    'miles': AppLanguageService.formatNumber(_radiusMiles),
                  },
                ),
              ],
            ),
            Slider(
              min: 5,
              max: 500,
              divisions: 99,
              value: _radiusMiles.toDouble(),
              label: '$_radiusMiles mi',
              onChanged: _locationBusy
                  ? null
                  : (value) => setState(() => _radiusMiles = value.round()),
              onChangeEnd: _locationBusy ? null : (_) => _applyRadius(),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _resetFilters() async {
    setState(() {
      _filters = _defaultFilters();
      _profiles = const [];
      _hasMore = false;
      _nextOffset = 0;
    });
    await _load();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<DiscoveryFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ApiDiscoveryFilterSheet(
        initial: _filters,
        profile: widget.currentUser,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filters = result;
      _profiles = const [];
      _hasMore = false;
      _nextOffset = 0;
    });
    await _load();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        !_hasMore ||
        _loadingMore ||
        _loading) {
      return;
    }
    if (_scrollController.position.extentAfter < 400) _loadMore();
  }

  void _fillShortViewport() {
    if (!mounted || _loading || _loadingMore || !_hasMore) return;
    if (!_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent <= 0) {
      _loadMore();
    }
  }

  DiscoveryFilters? get _requestFilters {
    if (widget.showSearchTools) return _filters;
    return DiscoveryFilters(
      minimumAge: 18,
      maximumAge: 100,
      prioritizeNearby: _nearestMode,
      maxDistanceMiles: _nearestMode ? _radiusMiles : null,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ApiDiscoveryService.getRecommendations(
        currentGender: widget.currentUser.gender,
        filters: _requestFilters,
        offset: 0,
        limit: _pageSize,
      );
      // Interest status is useful for button labels, but it must not make the
      // recommendation feed disappear if the separate interests endpoint fails.
      List<Interest> interests = const [];
      try {
        interests = await ApiSocialService.getSentInterests();
      } catch (_) {
        interests = const [];
      }
      if (!mounted) return;
      setState(() {
        _profiles = page.profiles;
        _hasMore = page.hasMore;
        _nextOffset = _pageSize;
        _interestStatuses
          ..clear()
          ..addEntries(
            interests
                .where((interest) => interest.receiverId.isNotEmpty)
                .map(
                  (interest) => MapEntry(interest.receiverId, interest.status),
                ),
          );
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fillShortViewport());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      // Keep scanning empty pages so filtered candidates beyond them appear.
      var offset = _nextOffset;
      var hasMore = true;
      final additions = <CandidateProfile>[];
      while (hasMore && additions.isEmpty) {
        final page = await ApiDiscoveryService.getRecommendations(
          currentGender: widget.currentUser.gender,
          filters: _requestFilters,
          offset: offset,
          limit: _pageSize,
        );
        additions.addAll(page.profiles);
        hasMore = page.hasMore;
        offset += _pageSize;
      }
      if (!mounted) return;
      setState(() {
        _profiles = [..._profiles, ...additions];
        _hasMore = hasMore;
        _nextOffset = offset;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _fillShortViewport(),
        );
      }
    }
  }

  Future<void> _sendInterest(CandidateProfile candidate) async {
    final existing = _interestStatuses[candidate.id];
    if (_sendingTo != null ||
        existing == InterestStatus.pending ||
        existing == InterestStatus.accepted) {
      return;
    }
    setState(() => _sendingTo = candidate.id);
    try {
      final interest = await ApiSocialService.sendInterest(candidate.id);
      if (!mounted) return;
      setState(() => _interestStatuses[candidate.id] = interest.status);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('Interest sent.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingTo = null);
    }
  }

  Future<void> _openProfile(CandidateProfile candidate) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiCandidateDetailsScreen(
          candidate: candidate,
          currentUser: widget.currentUser,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _block(CandidateProfile candidate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: LocalizedText(
          'Block {name}?',
          substitutions: {'name': candidate.name},
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
      await ApiSafetyService.blockUser(candidate.id);
      if (!mounted) return;
      setState(() => _profiles.removeWhere((item) => item.id == candidate.id));
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

  Future<void> _report(CandidateProfile candidate) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportUserScreen(
          reportedUserId: candidate.id,
          reportedUserName: candidate.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const LocalizedText('Discover'),
              actions: [
                IconButton(
                  tooltip: AppLanguageService.translate(
                    'Refresh recommendations',
                  ),
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      body: NisaPageBody(form: false, child: _resultsView()),
    );
  }

  List<CandidateProfile> get _visibleProfiles => widget.showSearchTools
      ? _profiles.where(_matchesFilters).toList()
      : _profiles;

  Widget _resultsView() => LayoutBuilder(
    builder: (context, box) {
      final columns =
          box.maxWidth >= 360 &&
              MediaQuery.textScalerOf(context).scale(16) <= 22
          ? 2
          : 1;
      final profiles = _visibleProfiles;
      final rowCount = (profiles.length / columns).ceil();
      return RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _locationBanner()),
            if (widget.showSearchTools)
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverToBoxAdapter(child: _searchHeader()),
              ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: _MessageState(
                  message: 'Something went wrong. Please try again.',
                  onRetry: _load,
                ),
              )
            else if (profiles.isEmpty)
              SliverToBoxAdapter(
                child: _MessageState(
                  message: widget.showSearchTools
                      ? 'No profiles match these filters. Try broadening your search.'
                      : 'No matching profiles are available yet. Try again later.',
                  onRetry: _hasMore ? _loadMore : _load,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: rowCount,
                  itemBuilder: (context, row) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0) const SizedBox(width: 12),
                          Expanded(
                            child: row * columns + column < profiles.length
                                ? _profileCard(profiles[row * columns + column])
                                : const SizedBox(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      );
    },
  );

  Widget _searchHeader() => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: LocalizedText(
                'Discover',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
        Text(
          AppLanguageService.translate(
            'Your saved matrimonial preferences rank compatible profiles. Discovery filters only narrow the list when you choose them.',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Chip(
              label: LocalizedRichText(
                spanBuilder: () => TextSpan(
                  children: [
                    TextSpan(text: AppLanguageService.translate('Age')),
                    const TextSpan(text: ': '),
                    TextSpan(
                      text: AppLanguageService.formatNumber(
                        _filters.minimumAge,
                      ),
                    ),
                    const TextSpan(text: ' - '),
                    TextSpan(
                      text: AppLanguageService.formatNumber(
                        _filters.maximumAge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_filters.country?.trim().isNotEmpty == true)
              Chip(label: LocalizedText(_filters.country!)),
            if (_filters.city?.trim().isNotEmpty == true)
              Chip(label: LocalizedText(_filters.city!)),
            if (_filters.maritalStatus?.trim().isNotEmpty == true)
              Chip(label: LocalizedText(_filters.maritalStatus!)),
            if (_filters.education?.trim().isNotEmpty == true)
              Chip(label: LocalizedText(_filters.education!)),
            if (_filters.verifiedOnly)
              const Chip(label: LocalizedText('Parent-verified profiles only')),
            ActionChip(
              avatar: const Icon(Icons.restart_alt, size: 18),
              label: const LocalizedText('Reset filters'),
              onPressed: _resetFilters,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _profileCard(CandidateProfile profile) {
    final status = _interestStatuses[profile.id];
    final existingRecommendationInterest =
        !widget.showSearchTools && profile.hasExistingInterest;
    return ApiCandidateProfileCard(
      profile: profile,
      interestStatus: status,
      existingInterest: existingRecommendationInterest,
      sendingInterest: _sendingTo == profile.id,
      showRecommendationReasons: !widget.showSearchTools,
      onOpen: () => _openProfile(profile),
      onInterest: () => _sendInterest(profile),
      onBlock: () => _block(profile),
      onReport: () => _report(profile),
    );
  }
}

class _MessageState extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _MessageState({required this.message, this.onRetry});

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

class _ApiDiscoveryFilterSheet extends StatefulWidget {
  final DiscoveryFilters initial;
  final UserProfile profile;

  const _ApiDiscoveryFilterSheet({
    required this.initial,
    required this.profile,
  });

  @override
  State<_ApiDiscoveryFilterSheet> createState() =>
      _ApiDiscoveryFilterSheetState();
}

class _ApiDiscoveryFilterSheetState
    extends LanguageAwareState<_ApiDiscoveryFilterSheet> {
  late RangeValues _age;
  late String _country;
  late String _city;
  late String _maritalStatus;
  late String _education;
  late String _minimumHeight;
  late String _maximumHeight;
  late bool _verifiedOnly;
  late bool _locationScopeExplicit;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _age = RangeValues(f.minimumAge.toDouble(), f.maximumAge.toDouble());
    _country = f.country ?? LocationService.anyCountry;
    _city = f.city ?? LocationService.anyCity;
    final savedMarital = f.maritalStatus?.trim().toLowerCase() ?? '';
    _maritalStatus = switch (savedMarital) {
      'single' ||
      'never married' ||
      'single (never married)' => 'Single (Never Married)',
      'married' => 'Married',
      'separated' => 'Separated',
      'divorced' => 'Divorced',
      'widowed' => 'Widowed',
      _ => 'Any marital status',
    };
    _education = f.education ?? 'Any education';
    _minimumHeight = f.minimumHeight ?? '';
    _maximumHeight = f.maximumHeight ?? '';
    _verifiedOnly = f.verifiedOnly;
    _locationScopeExplicit = f.locationScopeExplicit;
  }

  Future<String?> _searchableChoice({
    required String title,
    required String searchHint,
    required String current,
    required List<String> initialValues,
    required Future<List<String>> Function() loadValues,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _SearchableChoiceDialog(
      title: title,
      searchHint: searchHint,
      current: current,
      initialValues: initialValues,
      loadValues: loadValues,
    ),
  );

  Future<void> _pickCountry() async {
    final selected = await _searchableChoice(
      title: 'Country',
      searchHint: 'Search countries',
      current: _country,
      initialValues: [
        LocationService.anyCountry,
        'Pakistan',
        ...LocationService.offlineCountries,
      ],
      loadValues: LocationService.countries,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _country = selected;
      _city = LocationService.anyCity;
      _locationScopeExplicit = true;
    });
  }

  Future<void> _pickCity() async {
    final countryIsPakistan = _country.trim().toLowerCase() == 'pakistan';
    final countryIsAny =
        _country.trim().toLowerCase() ==
        LocationService.anyCountry.toLowerCase();
    final initial = <String>{
      LocationService.anyCity,
      if (countryIsPakistan || countryIsAny) ...LocationService.pakistanCities,
      if (_city.isNotEmpty) _city,
    }.toList();
    final selected = await _searchableChoice(
      title: 'City',
      searchHint: 'Search cities',
      current: _city,
      initialValues: initial,
      loadValues: () =>
          _country.toLowerCase() == LocationService.anyCountry.toLowerCase()
          ? LocationService.allCities()
          : LocationService.cities(_country),
    );
    if (selected != null && mounted) {
      setState(() {
        _city = selected;
        _locationScopeExplicit = true;
      });
    }
  }

  bool _isAny(String value) => value.trim().toLowerCase().startsWith('any');

  void _apply() => Navigator.pop(
    context,
    DiscoveryFilters(
      minimumAge: _age.start.round(),
      maximumAge: _age.end.round(),
      country: _isAny(_country) ? null : _country,
      city: _isAny(_city) ? null : _city,
      maritalStatus: _isAny(_maritalStatus) ? null : _maritalStatus,
      education: _isAny(_education) ? null : _education,
      minimumHeight: _minimumHeight.isEmpty ? null : _minimumHeight,
      maximumHeight: _maximumHeight.isEmpty ? null : _maximumHeight,
      verifiedOnly: _verifiedOnly,
      prioritizeNearby: widget.initial.prioritizeNearby,
      maxDistanceMiles: widget.initial.maxDistanceMiles,
      locationScopeExplicit: _locationScopeExplicit,
    ),
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          'Discovery filters',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        LocalizedRichText(
          spanBuilder: () => TextSpan(
            children: [
              TextSpan(text: AppLanguageService.translate('Age')),
              const TextSpan(text: ': '),
              TextSpan(
                text: AppLanguageService.formatNumber(_age.start.round()),
              ),
              const TextSpan(text: ' - '),
              TextSpan(text: AppLanguageService.formatNumber(_age.end.round())),
            ],
          ),
        ),
        RangeSlider(
          values: _age,
          min: 18,
          max: 100,
          divisions: 82,
          labels: RangeLabels('${_age.start.round()}', '${_age.end.round()}'),
          onChanged: (value) => setState(() => _age = value),
        ),
        _locationField('Country', _country, _pickCountry),
        const SizedBox(height: 12),
        _locationField('City', _city, _pickCity),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          itemHeight: null,
          isDense: false,
          initialValue: _maritalStatus,
          decoration: InputDecoration(
            labelText: AppLanguageService.translate('Marital Status'),
          ),
          items:
              const [
                    'Any marital status',
                    'Single (Never Married)',
                    'Married',
                    'Separated',
                    'Divorced',
                    'Widowed',
                  ]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: LocalizedText(value),
                    ),
                  )
                  .toList(),
          onChanged: (value) =>
              setState(() => _maritalStatus = value ?? 'Any marital status'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          itemHeight: null,
          isDense: false,
          initialValue: _education,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: AppLanguageService.translate('Minimum Education'),
          ),
          items: ['Any education', ...LocationService.educationOptions]
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: LocalizedText(value)),
              )
              .toList(),
          onChanged: (value) =>
              setState(() => _education = value ?? 'Any education'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          itemHeight: null,
          isDense: false,
          initialValue: LocationService.heightOptions.contains(_minimumHeight)
              ? _minimumHeight
              : '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: AppLanguageService.translate('Minimum height'),
          ),
          items: [
            DropdownMenuItem(value: '', child: LocalizedText('Any')),
            ...LocationService.heightOptions.map(
              (v) => DropdownMenuItem(value: v, child: Text(v)),
            ),
          ],
          onChanged: (value) => setState(() => _minimumHeight = value ?? ''),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          itemHeight: null,
          isDense: false,
          initialValue: LocationService.heightOptions.contains(_maximumHeight)
              ? _maximumHeight
              : '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: AppLanguageService.translate('Maximum height'),
          ),
          items: [
            DropdownMenuItem(value: '', child: LocalizedText('Any')),
            ...LocationService.heightOptions.map(
              (v) => DropdownMenuItem(value: v, child: Text(v)),
            ),
          ],
          onChanged: (value) => setState(() => _maximumHeight = value ?? ''),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const LocalizedText('Parent-verified profiles only'),
          value: _verifiedOnly,
          onChanged: (value) => setState(() => _verifiedOnly = value),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _apply,
            child: const LocalizedText('Apply filters'),
          ),
        ),
      ],
    ),
  );

  Widget _locationField(String label, String value, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: AppLanguageService.translate(label),
            suffixIcon: const Icon(Icons.search),
          ),
          child: LocalizedText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}

class _SearchableChoiceDialog extends StatefulWidget {
  final String title;
  final String searchHint;
  final String current;
  final List<String> initialValues;
  final Future<List<String>> Function() loadValues;

  const _SearchableChoiceDialog({
    required this.title,
    required this.searchHint,
    required this.current,
    required this.initialValues,
    required this.loadValues,
  });

  @override
  State<_SearchableChoiceDialog> createState() =>
      _SearchableChoiceDialogState();
}

class _SearchableChoiceDialogState
    extends LanguageAwareState<_SearchableChoiceDialog> {
  final TextEditingController _controller = TextEditingController();
  late List<String> _choices;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _choices = <String>{...widget.initialValues, widget.current}.toList();
    _loadChoices();
  }

  Future<void> _loadChoices() async {
    try {
      final loaded = await widget.loadValues();
      if (!mounted) return;
      setState(() {
        _choices = <String>{
          ...widget.initialValues,
          ...loaded,
          widget.current,
        }.toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final shown =
        _choices.where((value) => value.toLowerCase().contains(query)).toList()
          ..sort((a, b) {
            int priority(String value) =>
                value.toLowerCase().startsWith('any') ? -1 : 0;
            final p = priority(a).compareTo(priority(b));
            return p != 0 ? p : a.toLowerCase().compareTo(b.toLowerCase());
          });

    return AlertDialog(
      title: LocalizedText(widget.title),
      content: SizedBox(
        height: 420,
        width: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: AppLanguageService.translate(widget.searchHint),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_loading)
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
                        selected: value == widget.current,
                        onTap: () => Navigator.of(context).pop(value),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
