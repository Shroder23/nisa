import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets/localized_text.dart';

import 'widgets/language_selector_button.dart';
import 'widgets/api_profile_photo.dart';

import 'api_conversations_screen.dart';
import 'api_blocked_users_screen.dart';
import 'api_discovery_screen.dart';
import 'api_family_invitations_screen.dart';
import 'api_family_screen.dart';
import 'api_notifications_screen.dart';
import 'api_privacy_settings_screen.dart';
import 'api_session_management_screen.dart';
import 'edit_profile_screen.dart';
import 'matrimonial_preferences_screen.dart';
import 'models/notification_item.dart';
import 'models/user_profile.dart';
import 'services/api_app_state.dart';
import 'services/api_family_service.dart';
import 'services/api_social_service.dart';
import 'services/api_safety_service.dart';
import 'services/api_presence_service.dart';
import 'services/app_language_service.dart';
import 'services/api_verification_service.dart';
import 'api_admin_reports_screen.dart';
import 'api_my_reports_screen.dart';
import 'api_matches_screen.dart';
import 'verification_screen.dart';
import 'api_admin_verification_screen.dart';
import 'api_moderator_logs_screen.dart';
import 'api_moderator_requests_screen.dart';
import 'api_moderator_recommendations_screen.dart';
import 'api_admin_direct_ban_screen.dart';
import 'api_admin_user_management_screen.dart';

/// PostgreSQL-backed account home. Firebase-only features are not linked here.
class ApiHomeScreen extends StatefulWidget {
  final UserProfile profile;

  const ApiHomeScreen({super.key, required this.profile});

  @override
  State<ApiHomeScreen> createState() => _ApiHomeScreenState();
}

class _ApiHomeScreenState extends LanguageAwareState<ApiHomeScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _selectedTab = 0;
  late UserProfile _profile = widget.profile;
  int _unreadNotifications = 0;
  int _incomingFamilyInvitations = 0;
  late Future<Map<String, dynamic>> _verificationStatus;
  bool _canReviewVerification = false;
  bool _canReviewReports = false;
  bool _canReviewModeratorLogs = false;
  bool _loadingCounts = false;
  Timer? _presenceTimer;
  bool _presenceActive = true;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    ApiPresenceService.setOnline(false).catchError((_) {});
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _verificationStatus = ApiVerificationService.getStatus();
    WidgetsBinding.instance.addObserver(this);
    _updatePresence(true);
    _presenceTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_presenceActive) {
        _updatePresence(true);
      }
    });
    _refreshCounts();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _presenceActive = active;
    _updatePresence(active);
  }

  void _updatePresence(bool online) {
    ApiPresenceService.setOnline(online).catchError((_) {});
  }

  Future<void> _refreshCounts() async {
    if (_loadingCounts) {
      return;
    }
    _loadingCounts = true;
    List<NotificationItem>? notifications;
    List<Map<String, dynamic>>? familyInvitations;
    bool? canReview;
    bool? canReviewReports;
    bool? canReviewModeratorLogs;
    try {
      await Future.wait([
        () async {
          try {
            notifications = await ApiSocialService.getNotifications();
          } catch (_) {}
        }(),
        () async {
          try {
            canReviewModeratorLogs =
                await ApiSafetyService.canReviewModeratorLogs();
          } catch (_) {}
        }(),
        () async {
          try {
            familyInvitations = await ApiFamilyService.getIncomingInvitations();
          } catch (_) {}
        }(),
        () async {
          try {
            canReview = await ApiVerificationService.isAdmin();
          } catch (_) {}
        }(),
        () async {
          try {
            canReviewReports = await ApiSafetyService.canReviewReports();
          } catch (_) {}
        }(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        if (notifications != null) {
          _unreadNotifications = notifications!
              .where((item) => !item.isRead)
              .length;
        }
        if (familyInvitations != null) {
          _incomingFamilyInvitations = familyInvitations!.length;
        }
        if (canReview != null) {
          _canReviewVerification = canReview!;
        }
        if (canReviewReports != null) {
          _canReviewReports = canReviewReports!;
        }
        if (canReviewModeratorLogs != null) {
          _canReviewModeratorLogs = canReviewModeratorLogs!;
        }
      });
    } finally {
      _loadingCounts = false;
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) {
      setState(() {
        _verificationStatus = ApiVerificationService.getStatus();
      });
      await _refreshCounts();
      await _refreshProfile();
    }
  }

  Future<void> _editProfile() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile)),
    );
    if (saved == true && mounted) {
      await _refreshProfile();
    }
  }

  Future<void> _editPreferences() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            MatrimonialPreferencesScreen(profile: _profile, isEditing: true),
      ),
    );
    if (saved == true && mounted) {
      await _refreshProfile();
    }
  }

  Future<void> _refreshProfile() async {
    try {
      final profile = await ApiAppState.loadCurrentProfile();
      if (mounted && profile != null) {
        setState(() => _profile = profile);
      }
    } catch (_) {
      // Retain the cached profile if the API is temporarily unavailable.
    }
  }

  Widget _countBadge(int count, {required Widget child}) {
    if (count <= 0) {
      return child;
    }
    return Badge(label: Text(count > 99 ? '99+' : '$count'), child: child);
  }

  Future<void> _selectTab(int index) async {
    if (index == _selectedTab) {
      return;
    }
    setState(() => _selectedTab = index);
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    if (index == 0 && mounted) {
      await _refreshCounts();
      await _refreshProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final useNavigationRail = media.size.width >= 840;
    final compactNavigation =
        !useNavigationRail &&
        (media.size.width <= 520 || media.textScaler.scale(1) > 1);
    final labels = [
      'Home',
      'Search',
      'Matches',
      'Messages',
      'Profile',
    ].map(AppLanguageService.translate).toList();
    final icons = [
      Icons.home_outlined,
      Icons.search_outlined,
      Icons.favorite_border_rounded,
      Icons.chat_bubble_outline_rounded,
      Icons.person_outline_rounded,
    ];
    final selectedIcons = [
      Icons.home_rounded,
      Icons.search_rounded,
      Icons.favorite_rounded,
      Icons.chat_bubble_rounded,
      Icons.person_rounded,
    ];
    final pages = <Widget>[
      _dashboardPage(),
      ApiDiscoveryScreen(
        currentUser: _profile,
        showAppBar: false,
        showSearchTools: true,
      ),
      ApiMatchesScreen(showAppBar: false, currentUser: _profile),
      const ApiConversationsScreen(onlyWithMessages: true, showAppBar: false),
      _profilePage(),
    ];
    final pageView = PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: pages,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLanguageService.translate(_titleForIndex(_selectedTab))),
        actions: [
          const LanguageSelectorButton(),
          IconButton(
            tooltip: AppLanguageService.translate('Notifications'),
            onPressed: () => _open(const ApiNotificationsScreen()),
            icon: _countBadge(
              _unreadNotifications,
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: useNavigationRail
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _selectedTab,
                    onDestinationSelected: _selectTab,
                    labelType: NavigationRailLabelType.all,
                    minWidth: 88,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    indicatorColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHigh,
                    destinations: List.generate(
                      labels.length,
                      (index) => NavigationRailDestination(
                        icon: Icon(icons[index]),
                        selectedIcon: Icon(selectedIcons[index]),
                        label: Text(labels[index]),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: pageView),
                ],
              )
            : pageView,
      ),
      bottomNavigationBar: useNavigationRail
          ? null
          : NavigationBar(
              labelBehavior: compactNavigation
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _selectedTab,
              onDestinationSelected: _selectTab,
              destinations: List.generate(
                labels.length,
                (index) => NavigationDestination(
                  icon: Icon(icons[index]),
                  selectedIcon: Icon(selectedIcons[index]),
                  label: labels[index],
                ),
              ),
            ),
    );
  }

  String _titleForIndex(int index) => switch (index) {
    0 => 'Nisa',
    1 => 'Search',
    2 => 'Matches',
    3 => 'Messages',
    4 => 'Profile',
    _ => 'Nisa',
  };

  int get _profileCompletion {
    var completed = 0;
    const total = 11;
    if (_profile.name.trim().isNotEmpty) {
      completed++;
    }
    if (_profile.city.trim().isNotEmpty) {
      completed++;
    }
    if (_profile.country?.trim().isNotEmpty == true) {
      completed++;
    }
    if (_profile.height?.trim().isNotEmpty == true) {
      completed++;
    }
    if (_profile.education?.trim().isNotEmpty == true) {
      completed++;
    }
    if (_profile.profession?.trim().isNotEmpty == true) {
      completed++;
    }
    if (_profile.language?.trim().isNotEmpty == true) {
      completed++;
    }
    if (_profile.aboutMe?.trim().isNotEmpty == true) {
      completed++;
    }
    if (_profile.profilePhoto?.trim().isNotEmpty == true) {
      completed++;
    }
    if (_profile.preferences.country != null ||
        _profile.preferences.city != null) {
      completed++;
    }
    if (_profile.isVerified || _profile.verificationPending) {
      completed++;
    }
    return ((completed / total) * 100).round();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Log Out?'),
        content: const LocalizedText('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ApiAppState.signOut();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Widget _profilePage() {
    final account = ApiAppState.currentAccount;
    final email = account?['email']?.toString() ?? _profile.email ?? '';
    final status = account?['account_status']?.toString() ?? 'unknown';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: ApiSafetyService.getAccountRestrictions(),
          builder: (context, snapshot) {
            final restrictions =
                snapshot.data ?? const <Map<String, dynamic>>[];
            if (restrictions.isEmpty) {
              return const SizedBox.shrink();
            }
            return Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Column(
                children: restrictions
                    .map(
                      (item) => ListTile(
                        leading: const Icon(Icons.warning_amber_rounded),
                        title: const LocalizedText(
                          'Account restriction active',
                        ),
                        subtitle: Text(
                          [
                            item['user_notice'],
                            item['expires_at'],
                          ].whereType<Object>().join('\n'),
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
        Center(
          child: ApiProfilePhoto(
            imageUrl: _profile.profilePhoto,
            radius: 52,
            fallbackText: _profile.name,
            showBorder: true,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _editProfile,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(
              _profile.profilePhoto == null || _profile.profilePhoto!.isEmpty
                  ? 'Add profile photo'
                  : 'Change profile photo',
            ),
          ),
        ),
        Center(
          child: Text(
            _profile.name.trim().isEmpty
                ? 'Complete your profile'
                : _profile.name,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            [
              if (_profile.city.trim().isNotEmpty) _profile.city,
              if (_profile.country?.trim().isNotEmpty == true)
                _profile.country!,
            ].join(', '),
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(email, style: TextStyle(color: Colors.grey.shade600)),
          ),
        ],
        const SizedBox(height: 12),
        Center(
          child: Chip(
            avatar: Icon(
              _profile.isVerified
                  ? Icons.verified
                  : _profile.verificationPending
                  ? Icons.hourglass_top_rounded
                  : Icons.info_outline,
            ),
            label: LocalizedText(
              _profile.isVerified
                  ? 'Parent verified'
                  : _profile.verificationPending
                  ? 'Parent verification pending'
                  : 'Parent verification not completed',
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: LocalizedRichText(
            spanBuilder: () => TextSpan(
              children: [
                TextSpan(text: AppLanguageService.translate('Account status')),
                const TextSpan(text: ': '),
                TextSpan(text: AppLanguageService.translate(status)),
              ],
            ),
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const LocalizedText(
                      'Profile Completion',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    LocalizedText(
                      '{percent}%',
                      substitutions: {
                        'percent': AppLanguageService.formatNumber(
                          _profileCompletion,
                        ),
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _profileCompletion / 100),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _profileSection(
          title: 'Personal Details',
          icon: Icons.person_outline_rounded,
          actions: [
            _HomeAction(
              icon: Icons.person_outline,
              title: 'Edit Profile',
              subtitle: 'Update your details and profile photo',
              onTap: _editProfile,
            ),
            _HomeAction(
              icon: Icons.tune,
              title: 'Matrimonial Preferences',
              subtitle: 'Choose the qualities you are looking for',
              onTap: _editPreferences,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _profileSection(
          title: 'Family / Guardian',
          icon: Icons.family_restroom_rounded,
          actions: [
            _HomeAction(
              icon: Icons.family_restroom,
              title: 'Family / Guardian',
              subtitle: 'Invite and manage trusted family members',
              onTap: () => _open(const ApiFamilyScreen()),
            ),
            _HomeAction(
              icon: Icons.mark_email_unread_outlined,
              title: 'Family Invitations',
              subtitle: 'Review invitations addressed to your account email',
              badge: _incomingFamilyInvitations,
              onTap: () => _open(const ApiFamilyInvitationsScreen()),
            ),
            _verificationAction(),
          ],
        ),
        const SizedBox(height: 8),
        _profileSection(
          title: 'Privacy settings',
          icon: Icons.shield_outlined,
          actions: [
            _HomeAction(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy settings',
              subtitle: 'Privacy settings apply only to members you have matched with.',
              onTap: () => _open(const ApiPrivacySettingsScreen()),
            ),
            _HomeAction(
              icon: Icons.devices_outlined,
              title: 'Signed-in devices',
              subtitle: 'Manage your active sessions.',
              onTap: () => _open(const ApiSessionManagementScreen()),
            ),
            _HomeAction(
              icon: Icons.flag_outlined,
              title: 'My reports',
              subtitle: 'Check the status of reports you submitted',
              onTap: () => _open(const ApiMyReportsScreen()),
            ),
            _HomeAction(
              icon: Icons.block_outlined,
              title: 'Blocked users',
              subtitle: 'Review or unblock accounts',
              onTap: () => _open(const ApiBlockedUsersScreen()),
            ),
          ],
        ),
        if (_canReviewReports || _canReviewVerification) ...[
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: LocalizedText('Moderator Functions'),
                ),
                if (_canReviewReports)
                  _HomeAction(
                    icon: Icons.flag_outlined,
                    title: 'Report moderation queue',
                    subtitle: 'Review and resolve member reports',
                    onTap: () => _open(const ApiAdminReportsScreen()),
                  ),
                if (_canReviewVerification)
                  _HomeAction(
                    icon: Icons.verified_user_outlined,
                    title: 'Verification review queue',
                    subtitle:
                        'Open private evidence and review pending requests',
                    onTap: () => _open(const ApiAdminVerificationScreen()),
                  ),
                if (_canReviewReports)
                  _HomeAction(
                    icon: Icons.gavel_outlined,
                    title: 'Moderator Request',
                    subtitle: 'Recommend permanent account action',
                    onTap: () => _open(const ApiModeratorRequestsScreen()),
                  ),
                _HomeAction(
                  icon: Icons.lightbulb_outline,
                  title: 'Moderator recommendation',
                  subtitle: 'Suggest app improvements',
                  onTap: () => _open(const ApiModeratorRecommendationsScreen()),
                ),
              ],
            ),
          ),
        ],
        if (_canReviewModeratorLogs) ...[
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  leading: Icon(Icons.admin_panel_settings_outlined),
                  title: LocalizedText('Admin Functions'),
                ),
                _HomeAction(
                  icon: Icons.lightbulb_outline,
                  title: 'Moderator recommendation',
                  subtitle: 'Review moderator recommendations',
                  onTap: () => _open(
                    const ApiModeratorRecommendationsScreen(
                      administrator: true,
                    ),
                  ),
                ),
                _HomeAction(
                  icon: Icons.inbox_outlined,
                  title: 'Moderator Request',
                  subtitle: 'Review permanent ban requests',
                  onTap: () => _open(
                    const ApiModeratorRequestsScreen(administrator: true),
                  ),
                ),
                _HomeAction(
                  icon: Icons.history,
                  title: 'Moderator Logs',
                  subtitle: 'Moderator activity',
                  onTap: () => _open(const ApiModeratorLogsScreen()),
                ),
                _HomeAction(
                  icon: Icons.manage_accounts_outlined,
                  title: 'User management',
                  subtitle:
                      'Search accounts, manage moderators, and review activity',
                  onTap: () => _open(const ApiAdminUserManagementScreen()),
                ),
                _HomeAction(
                  icon: Icons.gavel_outlined,
                  title: 'Permanent ban',
                  subtitle: 'Permanent ban',
                  onTap: () => _open(const ApiAdminDirectBanScreen()),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const LocalizedText('Log Out'),
            onTap: _confirmSignOut,
          ),
        ),
      ],
    );
  }

  Widget _profileSection({
    required String title,
    required IconData icon,
    required List<Widget> actions,
  }) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: LocalizedText(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          dense: true,
        ),
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          actions[index],
        ],
      ],
    ),
  );

  Widget _verificationAction() => FutureBuilder<Map<String, dynamic>>(
    future: _verificationStatus,
    builder: (context, snapshot) {
      final status = snapshot.data?['status']?.toString();
      final subtitle = switch (status) {
        'approved' => 'Parent verification approved',
        'pending' => 'Parent verification is under review',
        'resubmission_required' => 'Verification resubmission requested',
        'rejected' => 'Verification rejected',
        _ =>
          _profile.isVerified
              ? 'Parent verification approved'
              : _profile.verificationPending
              ? 'Parent verification is under review'
              : 'Parent verification not completed',
      };
      final icon = switch (status) {
        'approved' => Icons.verified,
        'pending' => Icons.hourglass_top_rounded,
        'resubmission_required' || 'rejected' => Icons.edit_note,
        _ =>
          _profile.isVerified
              ? Icons.verified
              : _profile.verificationPending
              ? Icons.hourglass_top_rounded
              : Icons.verified_user_outlined,
      };
      return _HomeAction(
        icon: icon,
        title: 'Verification',
        subtitle: subtitle,
        onTap: () => _open(VerificationScreen(profile: _profile)),
      );
    },
  );

  Widget _dashboardPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ApiProfilePhoto(
                      imageUrl: _profile.profilePhoto,
                      radius: 25,
                      fallbackText: _profile.name,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _profile.name.trim().isEmpty
                              ? const LocalizedText(
                                  'Nisa',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : Text(
                                  _profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                          const SizedBox(height: 2),
                          const LocalizedText('Find a meaningful connection.'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _profile.isVerified
                            ? Icons.verified_rounded
                            : _profile.verificationPending
                            ? Icons.hourglass_top_rounded
                            : Icons.verified_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LocalizedText(
                          _profile.isVerified
                              ? 'Parent verified'
                              : _profile.verificationPending
                              ? 'Parent verification pending'
                              : 'Parent verification not completed',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 38,
                        height: 38,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: _profileCompletion / 100,
                              strokeWidth: 3,
                              semanticsLabel: AppLanguageService.translate(
                                'Profile Completion',
                              ),
                              semanticsValue: AppLanguageService.formatNumber(
                                _profileCompletion,
                              ),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                            ),
                            LocalizedText(
                              '{percent}%',
                              substitutions: {
                                'percent': AppLanguageService.formatNumber(
                                  _profileCompletion,
                                ),
                              },
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: LocalizedText(
                        'Recommended for you',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: _editProfile,
                      child: const LocalizedText('Edit Profile'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      Expanded(
        child: ApiDiscoveryScreen(
          key: const ValueKey('home_recommendations'),
          currentUser: _profile,
          showAppBar: false,
          showSearchTools: false,
        ),
      ),
    ],
  );
}

class _HomeAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int badge;
  final VoidCallback onTap;

  const _HomeAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Badge(
      isLabelVisible: badge > 0,
      label: Text(badge > 99 ? '99+' : '$badge'),
      child: Icon(icon),
    ),
    title: LocalizedText(title),
    subtitle: LocalizedText(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
