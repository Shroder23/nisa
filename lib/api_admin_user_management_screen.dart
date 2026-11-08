import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/api_safety_service.dart';
import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

class ApiAdminUserManagementScreen extends StatefulWidget {
  const ApiAdminUserManagementScreen({super.key});

  @override
  State<ApiAdminUserManagementScreen> createState() =>
      _ApiAdminUserManagementScreenState();
}

class _ApiAdminUserManagementScreenState
    extends State<ApiAdminUserManagementScreen> {
  final _query = TextEditingController();
  Future<Map<String, dynamic>>? _results;
  int? _nextOffset;
  bool _loadingMore = false;
  bool _searching = false;
  int _loadGeneration = 0;

  String _accountStatusLabel(String? raw) => switch (raw) {
    'active' => 'Active',
    'disabled' => 'Disabled',
    'deleted' => 'Deleted',
    'draft' => 'Draft',
    _ => 'Unknown',
  };

  @override
  void initState() {
    super.initState();
    _loadUsers(reset: true);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool reset = false}) async {
    if (reset) {
      _nextOffset = null;
    }
    final generation = ++_loadGeneration;
    final request = ApiSafetyService.searchAdminUsers(
      query: _query.text.trim(),
      offset: reset ? 0 : (_nextOffset ?? 0),
    );
    setState(() {
      _searching = true;
      _results = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder presents the request error and retry action.
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextOffset == null) {
      return;
    }
    final generation = _loadGeneration;
    final query = _query.text.trim();
    setState(() => _loadingMore = true);
    try {
      final next = await ApiSafetyService.searchAdminUsers(
        query: query,
        offset: _nextOffset!,
      );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      final current = await _results!;
      final users = <Map<String, dynamic>>[
        ...((current['users'] as List).cast<Map<String, dynamic>>()),
        ...((next['users'] as List).cast<Map<String, dynamic>>()),
      ];
      setState(() {
        _nextOffset = next['next_offset'] as int?;
        _results = Future.value({'users': users, 'next_offset': _nextOffset});
      });
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: LocalizedText(
          'Could not complete this admin action: {error}',
          substitutions: {
            'error': error.toString().replaceFirst('Bad state: ', ''),
          },
        ),
      ),
    );
  }

  Future<void> _openUser(Map<String, dynamic> user) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiAdminUserDetailScreen(user: user),
      ),
    );
    if (mounted) {
      _loadUsers(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('User management'),
      actions: [
        IconButton(
          tooltip: AppLanguageService.translate('Refresh'),
          onPressed: _searching ? null : () => _loadUsers(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: NisaPageBody(
      form: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadUsers(reset: true),
              decoration: InputDecoration(
                labelText: AppLanguageService.translate(
                  'Search by name, registered email, or phone',
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: AppLanguageService.translate('Search'),
                  onPressed: _searching ? null : () => _loadUsers(reset: true),
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: LocalizedText(
                'Phone search only finds numbers saved on an account. Phone registration is not available yet.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _results,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(snapshot.error.toString()),
                          TextButton(
                            onPressed: () => _loadUsers(reset: true),
                            child: const LocalizedText('Try again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final users = (snapshot.data!['users'] as List)
                    .cast<Map<String, dynamic>>();
                _nextOffset = snapshot.data!['next_offset'] as int?;
                if (users.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => _loadUsers(reset: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 160),
                        Center(
                          child: LocalizedText('No matching accounts found.'),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => _loadUsers(reset: true),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: users.length + (_nextOffset == null ? 0 : 1),
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      if (index == users.length) {
                        return Center(
                          child: TextButton.icon(
                            onPressed: _loadingMore ? null : _loadMore,
                            icon: _loadingMore
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more),
                            label: const LocalizedText('Load more'),
                          ),
                        );
                      }
                      final row = users[index];
                      final name = row['full_name']?.toString().trim();
                      final email = row['email']?.toString() ?? '';
                      final phone = row['phone_number']?.toString() ?? '';
                      final activeModerator =
                          row['moderator_active'] == true &&
                          (row['can_review_reports'] == true ||
                              row['can_review_verification'] == true);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              row['platform_admin'] == true
                                  ? Icons.admin_panel_settings_outlined
                                  : activeModerator
                                  ? Icons.shield_outlined
                                  : Icons.person_outline,
                            ),
                          ),
                          title: Text(
                            (name == null || name.isEmpty)
                                ? (row['display_name']?.toString() ??
                                      row['id'].toString())
                                : name,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (email.isNotEmpty) Text(email),
                              if (phone.isNotEmpty) Text(phone),
                              Wrap(
                                spacing: 4,
                                children: [
                                  const LocalizedText('Account status'),
                                  LocalizedText(
                                    _accountStatusLabel(
                                      row['account_status']?.toString(),
                                    ),
                                  ),
                                ],
                              ),
                              if (activeModerator)
                                const LocalizedText('Moderator'),
                              if (row['platform_admin'] == true)
                                const LocalizedText('Platform administrator'),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openUser(row),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class ApiAdminUserDetailScreen extends StatefulWidget {
  const ApiAdminUserDetailScreen({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<ApiAdminUserDetailScreen> createState() =>
      _ApiAdminUserDetailScreenState();
}

class _ApiAdminUserDetailScreenState extends State<ApiAdminUserDetailScreen> {
  bool _busy = false;
  late Map<String, dynamic> _user = Map<String, dynamic>.from(widget.user);

  bool get _isModerator =>
      _user['moderator_active'] == true &&
      (_user['can_review_reports'] == true ||
          _user['can_review_verification'] == true);

  bool get _isPlatformAdmin => _user['platform_admin'] == true;

  String _accountStatusLabel(String? raw) => switch (raw) {
    'active' => 'Active',
    'disabled' => 'Disabled',
    'deleted' => 'Deleted',
    'draft' => 'Draft',
    _ => 'Unknown',
  };

  void _message(String value) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: LocalizedText(value)));
  }

  Future<String?> _reasonDialog({
    required String title,
    required String label,
    String confirm = 'Continue',
  }) async {
    var reasonText = '';
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: LocalizedText(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => reasonText = value,
                minLines: 3,
                maxLines: 5,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate(label),
                  errorText: error,
                ),
              ),
              const LocalizedText(
                'At least 10 characters are required. The reason is recorded in the admin audit log.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const LocalizedText('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = reasonText.trim();
                if (value.length < 10) {
                  setDialogState(
                    () => error = AppLanguageService.translate(
                      'Enter at least 10 characters.',
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: LocalizedText(confirm),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<Map<String, dynamic>?> _moderatorDialog() async {
    String? gender = _user['reviewer_gender']?.toString().isEmpty == true
        ? null
        : _user['reviewer_gender']?.toString();
    bool verification = _user['can_review_verification'] == true;
    bool reports = _user['can_review_reports'] == true;
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const LocalizedText('Set moderator permissions'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  itemHeight: null,
                  isDense: false,
                  initialValue: gender,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.translate('Reviewer gender'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'male',
                      child: LocalizedText('Male'),
                    ),
                    DropdownMenuItem(
                      value: 'female',
                      child: LocalizedText('Female'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() => gender = value),
                ),
                SwitchListTile(
                  value: verification,
                  title: const LocalizedText('Verification'),
                  onChanged: (value) =>
                      setDialogState(() => verification = value),
                ),
                SwitchListTile(
                  value: reports,
                  title: const LocalizedText('Reports'),
                  onChanged: (value) => setDialogState(() => reports = value),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const LocalizedText('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (gender == null || (!verification && !reports)) {
                  setDialogState(
                    () => error = AppLanguageService.translate(
                      'Choose a reviewer gender and at least one permission.',
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, {
                  'gender': gender,
                  'verification': verification,
                  'reports': reports,
                });
              },
              child: const LocalizedText('Save'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<Map<String, dynamic>?> _banDialog({required bool deletion}) async {
    var reasonText = '';
    var denyPhoneText = '';
    bool denyEmail = false;
    bool confirmed = false;
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: LocalizedText(deletion ? 'Delete account' : 'Permanent ban'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (value) => reasonText = value,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.translate('Reason'),
                    errorText: error,
                  ),
                ),
                CheckboxListTile(
                  value: denyEmail,
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText(
                    'Block this email from registering again',
                  ),
                  onChanged: (value) =>
                      setDialogState(() => denyEmail = value ?? false),
                ),
                TextField(
                  onChanged: (value) => denyPhoneText = value,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.translate(
                      'Phone number to block (optional)',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                LocalizedText(
                  deletion
                      ? 'Profile data, sign-in credentials, photos, and verification uploads are removed. Messages, interests, reports, matches, family records, notifications, and audit history may remain linked to the retained account ID.'
                      : 'This disables sign-in and revokes active sessions.',
                ),
                CheckboxListTile(
                  value: confirmed,
                  contentPadding: EdgeInsets.zero,
                  title: const LocalizedText('I confirm this action.'),
                  onChanged: (value) =>
                      setDialogState(() => confirmed = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const LocalizedText('Cancel'),
            ),
            FilledButton(
              style: deletion
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              onPressed: confirmed
                  ? () {
                      if (reasonText.trim().length < 10) {
                        setDialogState(
                          () => error = AppLanguageService.translate(
                            'Enter at least 10 characters.',
                          ),
                        );
                        return;
                      }
                      Navigator.pop(dialogContext, {
                        'reason': reasonText.trim(),
                        'deny_email': denyEmail,
                        'deny_phone': denyPhoneText.trim(),
                      });
                    }
                  : null,
              child: LocalizedText(
                deletion ? 'Delete account' : 'Permanent ban',
              ),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      _message('Admin action saved.');
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: LocalizedText(
          'Could not complete this admin action: {error}',
          substitutions: {
            'error': error.toString().replaceFirst('Bad state: ', ''),
          },
        ),
      ),
    );
  }

  Future<void> _setModerator() async {
    final form = await _moderatorDialog();
    if (form == null || !mounted) {
      return;
    }
    await _runAction(() async {
      await ApiSafetyService.setAdminUserModerator(
        userId: _user['id'].toString(),
        reviewerGender: form['gender'] as String,
        canReviewVerification: form['verification'] as bool,
        canReviewReports: form['reports'] as bool,
        reason: '',
      );
      _user = {
        ..._user,
        'reviewer_gender': form['gender'],
        'can_review_verification': form['verification'],
        'can_review_reports': form['reports'],
        'moderator_active': true,
      };
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _removeModerator() async {
    final reason = await _reasonDialog(
      title: 'Remove moderator access?',
      label: 'Reason',
      confirm: 'Remove moderator',
    );
    if (reason == null || !mounted) {
      return;
    }
    await _runAction(() async {
      await ApiSafetyService.removeAdminUserModerator(
        userId: _user['id'].toString(),
        reason: reason,
      );
      _user = {
        ..._user,
        'moderator_active': false,
        'can_review_verification': false,
        'can_review_reports': false,
      };
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _ban({required bool deletion}) async {
    final form = await _banDialog(deletion: deletion);
    if (form == null || !mounted) {
      return;
    }
    await _runAction(() async {
      final phone = (form['deny_phone'] as String).trim();
      if (deletion) {
        await ApiSafetyService.deleteAdminUser(
          userId: _user['id'].toString(),
          reason: form['reason'] as String,
          denyEmail: form['deny_email'] as bool,
          denyPhone: phone.isEmpty ? null : phone,
        );
      } else {
        await ApiSafetyService.permanentlyBanAdminUser(
          userId: _user['id'].toString(),
          reason: form['reason'] as String,
          denyEmail: form['deny_email'] as bool,
          denyPhone: phone.isEmpty ? null : phone,
        );
      }
      _user = {
        ..._user,
        'account_status': deletion ? 'deleted' : 'disabled',
        'email': deletion ? null : _user['email'],
        'phone_number': deletion ? null : _user['phone_number'],
        'moderator_active': false,
      };
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _showActivity() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiAdminUserActivityScreen(user: _user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _user['full_name']?.toString().trim();
    final displayName = name == null || name.isEmpty
        ? (_user['display_name']?.toString() ?? _user['id'].toString())
        : name;
    final status = _user['account_status']?.toString() ?? 'unknown';
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Account administration')),
      body: NisaPageBody(
        form: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    _isPlatformAdmin
                        ? Icons.admin_panel_settings_outlined
                        : _isModerator
                        ? Icons.shield_outlined
                        : Icons.person_outline,
                  ),
                ),
                title: Text(displayName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 4,
                      children: [
                        const LocalizedText('User ID'),
                        Text(_user['id'].toString()),
                      ],
                    ),
                    if ((_user['email']?.toString() ?? '').isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: [
                          const LocalizedText('Email'),
                          Text(_user['email'].toString()),
                        ],
                      ),
                    if ((_user['phone_number']?.toString() ?? '').isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: [
                          const LocalizedText('Phone'),
                          Text(_user['phone_number'].toString()),
                        ],
                      ),
                    Wrap(
                      spacing: 4,
                      children: [
                        const LocalizedText('Account status'),
                        LocalizedText(_accountStatusLabel(status)),
                      ],
                    ),
                    if (_isModerator)
                      Wrap(
                        spacing: 4,
                        children: [
                          const LocalizedText('Moderator'),
                          _user['reviewer_gender'] == 'male'
                              ? const LocalizedText('Male')
                              : const LocalizedText('Female'),
                          if (_user['can_review_verification'] == true)
                            const LocalizedText('Verification'),
                          if (_user['can_review_reports'] == true)
                            const LocalizedText('Reports'),
                        ],
                      ),
                    if (_isPlatformAdmin)
                      const LocalizedText('Platform administrator account'),
                  ],
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _showActivity,
              icon: const Icon(Icons.history),
              label: const LocalizedText('View account activity'),
            ),
            const SizedBox(height: 12),
            if (_user['account_status'] == 'active') ...[
              if (_isModerator) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _setModerator,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const LocalizedText('Edit moderator permissions'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _removeModerator,
                  icon: const Icon(Icons.person_remove_alt_1_outlined),
                  label: const LocalizedText('Remove moderator access'),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: _busy ? null : _setModerator,
                  icon: const Icon(Icons.shield_outlined),
                  label: const LocalizedText('Set as moderator'),
                ),
              if (!_isPlatformAdmin && _user['account_status'] == 'active') ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _ban(deletion: false),
                  icon: const Icon(Icons.gavel_outlined),
                  label: const LocalizedText('Permanently ban account'),
                ),
              ],
            ],
            if (!_isPlatformAdmin && _user['account_status'] != 'deleted')
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _ban(deletion: true),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const LocalizedText('Delete account'),
              ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class ApiAdminUserActivityScreen extends StatefulWidget {
  const ApiAdminUserActivityScreen({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<ApiAdminUserActivityScreen> createState() =>
      _ApiAdminUserActivityScreenState();
}

class _ApiAdminUserActivityScreenState
    extends State<ApiAdminUserActivityScreen> {
  late final Future<List<Map<String, dynamic>>> _activities =
      ApiSafetyService.getAdminUserActivity(widget.user['id'].toString());

  String _eventLabel(String? raw) => switch (raw) {
    'directory_search' => 'User directory searched',
    'account_activity_viewed' => 'Account activity viewed',
    'moderator_role_set' => 'Moderator permissions changed',
    'moderator_role_removed' => 'Moderator access removed',
    'account_permanently_banned' => 'Account permanently banned',
    'account_deleted' => 'Account deleted',
    'admin_moderator_role_set' => 'Moderator permissions changed',
    'admin_moderator_role_removed' => 'Moderator access removed',
    'admin_direct_permanent_ban' => 'Account permanently banned',
    'admin_account_deleted' => 'Account deleted',
    'report_submitted' => 'Report submitted',
    'report_received' => 'Report received',
    'temporary_account_ban' => 'Temporary account ban',
    'pair_interaction_restriction' => 'Pair interaction restriction',
    'permanent_ban_vote' => 'Permanent ban request',
    'report_resolved' => 'Report resolved',
    'report_dismissed' => 'Report dismissed',
    'verification_approve' => 'Verification approved',
    'verification_reject' => 'Verification rejected',
    'verification_request_resubmission' =>
      'Verification resubmission requested',
    'admin_overrode_moderator_sanction' => 'Administrator override',
    'admin_overrode_moderator_decision' => 'Administrator override',
    'admin_reinstate' => 'Account reinstated',
    'admin_permanent_ban' => 'Account permanently banned',
    'admin_delete_account' => 'Account deleted',
    'admin_dismiss' => 'Administrator dismissed case',
    'admin_case_decided' => 'Administrator decision recorded',
    'report_reviewing' => 'Report marked for review',
    'report_appeal_reopen' => 'Report appeal reopened',
    'report_appeal_uphold' => 'Report appeal upheld',
    'recommendation_submitted' => 'Moderator recommendation submitted',
    'recommendation_decided' => 'Moderator recommendation reviewed',
    'verification_view_id' => 'Verification ID viewed',
    'verification_view_authority' => 'Verification authority document viewed',
    'verification_view_video' => 'Verification video viewed',
    _ => 'Other account activity',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('Account activity')),
    body: NisaPageBody(
      form: false,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _activities,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final activities = snapshot.data!;
          if (activities.isEmpty) {
            return const Center(
              child: LocalizedText('No recorded account activity.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: activities.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = activities[index];
              final reason = event['reason']?.toString() ?? '';
              return ListTile(
                leading: const Icon(Icons.history),
                title: LocalizedText(
                  _eventLabel(event['event_type']?.toString()),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (reason.isNotEmpty) Text(reason),
                    Wrap(
                      spacing: 4,
                      children: [
                        const LocalizedText('Actor'),
                        Text(
                          event['actor_user_id']?.toString() ??
                              AppLanguageService.translate('System'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (event['target_user_id'] != null)
                      Wrap(
                        spacing: 4,
                        children: [
                          const LocalizedText('Target'),
                          Text(
                            event['target_user_id'].toString(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    if (event['occurred_at'] != null)
                      Text(
                        event['occurred_at'].toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    ),
  );
}
