import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/app_language_service.dart';

import 'services/api_safety_service.dart';
import 'api_moderator_requests_screen.dart';
import 'widgets/localized_text.dart';

class ApiAdminReportsScreen extends StatefulWidget {
  const ApiAdminReportsScreen({super.key});

  @override
  State<ApiAdminReportsScreen> createState() => _ApiAdminReportsScreenState();
}

class _ApiAdminReportsScreenState extends State<ApiAdminReportsScreen> {
  late Future<List<Map<String, dynamic>>> _queue =
      ApiSafetyService.getReportQueue();
  late Future<Map<String, dynamic>> _metrics =
      ApiSafetyService.getReportMetrics();
  String? _category;
  bool _busy = false;

  Future<void> _sanction(Map<String, dynamic> report, String type) async {
    final form = await showDialog<_SanctionFormResult>(
      context: context,
      builder: (_) =>
          _SanctionActionDialog(accountBan: type == 'temporary_account_ban'),
    );
    if (form == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiSafetyService.createModerationSanction(
        targetUserId: report['subject_user_id'].toString(),
        sanctionType: type,
        otherUserId: type == 'pair_interaction_restriction'
            ? report['reporter_user_id']?.toString()
            : null,
        reportId: report['id'].toString(),
        reasonCode: report['triage_category']?.toString() ?? 'other',
        reason: form.reason,
        userNotice: form.notice,
        durationDays: form.durationDays,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText('Temporary moderation action saved.'),
          ),
        );
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _liftSanction(Map<String, dynamic> report, String type) async {
    final accountBan = type == 'temporary_account_ban';
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: LocalizedText(
          accountBan ? 'Unlift ban?' : 'Unlift restriction?',
        ),
        content: const LocalizedText(
          'This will immediately end the active temporary restriction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const LocalizedText('Unlift ban'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) {
      return;
    }
    final key = accountBan
        ? 'active_temporary_ban_id'
        : 'active_messaging_restriction_id';
    final sanctionId = report[key]?.toString();
    if (sanctionId == null || sanctionId.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiSafetyService.revokeModerationSanction(sanctionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText('Temporary restriction lifted.'),
          ),
        );
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _proposePermanentBan(Map<String, dynamic> report) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApiModeratorRequestsScreen(
          initialTargetUserId: report['subject_user_id']?.toString(),
          initialReportId: report['id']?.toString(),
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    final queue = ApiSafetyService.getReportQueue(triageCategory: _category);
    final metrics = ApiSafetyService.getReportMetrics();
    setState(() {
      _queue = queue;
      _metrics = metrics;
    });
    await Future.wait([queue, metrics]);
  }

  String _categoryLabel(String raw) => switch (raw) {
    'profile_content' => 'Profile content',
    'identity_or_fraud' => 'Identity or fraud',
    'harassment' => 'Harassment',
    'scam' => 'Scam',
    'marital_status' => 'Marital status',
    'spam' => 'Spam',
    _ => 'Other',
  };

  Future<Map<String, dynamic>?> _decisionDialog({
    required String title,
    required bool requiresOutcome,
    int currentPriority = 2,
  }) => showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _ReportDecisionDialog(
      title: title,
      requiresOutcome: requiresOutcome,
      currentPriority: currentPriority,
    ),
  );

  Future<Map<String, dynamic>?> _appealNotesDialog(String title) =>
      showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _AppealNotesDialog(title: title),
      );

  Future<void> _moderate(Map<String, dynamic> report, String decision) async {
    final result = await _decisionDialog(
      title: switch (decision) {
        'reviewing' => 'Mark as reviewing',
        'resolved' => 'Resolve report',
        _ => 'Dismiss report',
      },
      requiresOutcome: decision != 'reviewing',
      currentPriority: (report['priority'] as num?)?.toInt() ?? 2,
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiSafetyService.moderateReport(
        report['id'].toString(),
        decision: decision,
        outcomeCode: decision == 'reviewing'
            ? null
            : result['outcome'] as String,
        priority: result['priority'] as int,
        notes: result['notes'] as String,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Report decision saved')),
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _decideAppeal(
    Map<String, dynamic> report,
    String decision,
  ) async {
    final result = await _appealNotesDialog(
      decision == 'reopen' ? 'Reopen report after appeal' : 'Uphold closure',
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiSafetyService.decideReportAppeal(
        report['id'].toString(),
        decision: decision,
        notes: result['notes'] as String,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Appeal decision saved')),
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _metricsCard() => FutureBuilder<Map<String, dynamic>>(
    future: _metrics,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox.shrink();
      }
      final m = snapshot.data!;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _metric('Open', m['open_count']),
              _metric('Over 24 hours', m['older_24h']),
              _metric('Over 72 hours', m['older_72h']),
              _metric('Pending appeals', m['pending_appeals']),
              _metric('Avg. resolution hours', m['avg_resolution_hours']),
            ],
          ),
        ),
      );
    },
  );

  Widget _metric(String label, dynamic value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      LocalizedText(label, style: Theme.of(context).textTheme.labelMedium),
      Text(
        value?.toString() ?? '—',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  );

  Widget _queueCard(Map<String, dynamic> report) {
    final appealPending = report['appeal_status'] == 'pending';
    final reporter =
        (report['reporter_name']?.toString().trim().isNotEmpty ?? false)
        ? report['reporter_name']
        : 'Nisa member';
    final subject =
        (report['reported_name']?.toString().trim().isNotEmpty ?? false)
        ? report['reported_name']
        : 'Unavailable account';
    final ageHours = int.tryParse(report['age_hours']?.toString() ?? '');
    final priority = report['priority']?.toString() ?? '2';
    final details = appealPending
        ? report['appeal_details']?.toString() ?? ''
        : report['details']?.toString() ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    report['reason']?.toString() ?? 'Report',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: LocalizedText(
                    _categoryLabel(
                      report['triage_category']?.toString() ?? 'other',
                    ),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                LocalizedRichText(
                  spanBuilder: () => TextSpan(
                    children: [
                      TextSpan(text: AppLanguageService.translate('Priority')),
                      const TextSpan(text: ' '),
                      TextSpan(text: AppLanguageService.translate(priority)),
                    ],
                  ),
                ),
                LocalizedRichText(
                  spanBuilder: () => TextSpan(
                    children: [
                      TextSpan(text: AppLanguageService.translate('Age')),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: ageHours == null
                            ? '—'
                            : AppLanguageService.formatNumber(ageHours),
                      ),
                      const TextSpan(text: ' h ('),
                      TextSpan(
                        text: AppLanguageService.translate(
                          report['age_bucket']?.toString() ?? 'under_24h',
                        ),
                      ),
                      const TextSpan(text: ')'),
                    ],
                  ),
                ),
                LocalizedRichText(
                  spanBuilder: () => TextSpan(
                    children: [
                      TextSpan(text: AppLanguageService.translate('Status')),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: AppLanguageService.translate(
                          appealPending
                              ? 'Appeal pending'
                              : report['status']?.toString() ?? '',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            LocalizedText(
              'Reported member: {name}',
              substitutions: {'name': subject},
            ),
            LocalizedText(
              'Reporter: {name}',
              substitutions: {'name': reporter},
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                appealPending ? 'Appeal details' : 'Report details',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 3),
              SelectableText(details),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (appealPending) ...[
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _decideAppeal(report, 'uphold'),
                    child: const LocalizedText('Uphold closure'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _decideAppeal(report, 'reopen'),
                    child: const LocalizedText('Reopen for review'),
                  ),
                ] else ...[
                  if (report['status'] == 'pending')
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _moderate(report, 'reviewing'),
                      child: const LocalizedText('Mark reviewing'),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _moderate(report, 'dismissed'),
                    child: const LocalizedText('Dismiss'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _moderate(report, 'resolved'),
                    child: const LocalizedText('Resolve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : report['active_temporary_ban_id'] == null
                        ? () => _sanction(report, 'temporary_account_ban')
                        : () => _liftSanction(report, 'temporary_account_ban'),
                    icon: Icon(
                      report['active_temporary_ban_id'] == null
                          ? Icons.timer_off_outlined
                          : Icons.lock_open_outlined,
                    ),
                    label: LocalizedText(
                      report['active_temporary_ban_id'] == null
                          ? 'Temporary account ban'
                          : 'Unlift ban',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : report['active_messaging_restriction_id'] == null
                        ? () =>
                              _sanction(report, 'pair_interaction_restriction')
                        : () => _liftSanction(
                            report,
                            'pair_interaction_restriction',
                          ),
                    icon: Icon(
                      report['active_messaging_restriction_id'] == null
                          ? Icons.message_outlined
                          : Icons.lock_open_outlined,
                    ),
                    label: LocalizedText(
                      report['active_messaging_restriction_id'] == null
                          ? 'Restrict messaging'
                          : 'Unlift restriction',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _proposePermanentBan(report),
                    icon: const Icon(Icons.gavel_outlined),
                    label: const LocalizedText('Recommend permanent ban'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Report moderation'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: NisaPageBody(
      form: false,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _queue,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: LocalizedText('Something went wrong. Please try again.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final reports = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                _metricsCard(),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  itemHeight: null,
                  isDense: false,
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.translate(
                      'Filter by triage category',
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: LocalizedText('All categories'),
                    ),
                    for (final category in [
                      'profile_content',
                      'identity_or_fraud',
                      'harassment',
                      'scam',
                      'marital_status',
                      'spam',
                      'other',
                    ])
                      DropdownMenuItem<String?>(
                        value: category,
                        child: LocalizedText(_categoryLabel(category)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() => _category = value);
                          _refresh();
                        },
                ),
                const SizedBox(height: 8),
                if (reports.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: LocalizedText(
                        'No open reports or appeals are waiting for review.',
                      ),
                    ),
                  )
                else
                  ...reports.map(_queueCard),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _SanctionFormResult {
  const _SanctionFormResult({
    required this.reason,
    required this.notice,
    required this.durationDays,
  });

  final String reason;
  final String notice;
  final int durationDays;
}

class _SanctionActionDialog extends StatefulWidget {
  const _SanctionActionDialog({required this.accountBan});

  final bool accountBan;

  @override
  State<_SanctionActionDialog> createState() => _SanctionActionDialogState();
}

class _SanctionActionDialogState extends State<_SanctionActionDialog> {
  final _reason = TextEditingController();
  final _notice = TextEditingController();
  int _durationDays = 7;
  String? _validationError;

  @override
  void dispose() {
    _reason.dispose();
    _notice.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    final notice = _notice.text.trim();
    if (reason.length < 10 || notice.length < 10) {
      setState(
        () => _validationError = 'Provide a clear reason and member notice.',
      );
      return;
    }
    Navigator.of(context).pop(
      _SanctionFormResult(
        reason: reason,
        notice: notice,
        durationDays: _durationDays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: LocalizedText(
      widget.accountBan ? 'Temporary account ban' : 'Restrict messaging',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            onChanged: (_) => setState(() => _validationError = null),
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Reason'),
            ),
          ),
          TextField(
            controller: _notice,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            onChanged: (_) => setState(() => _validationError = null),
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Notice shown to member'),
            ),
          ),
          DropdownButtonFormField<int>(
            isExpanded: true,
            itemHeight: null,
            isDense: false,
            initialValue: _durationDays,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Duration'),
            ),
            items: const [1, 3, 7, 14, 30]
                .map(
                  (days) => DropdownMenuItem(
                    value: days,
                    child: Text(days.toString()),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _durationDays = value ?? _durationDays),
          ),
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                AppLanguageService.translate(_validationError!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const LocalizedText('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const LocalizedText('Apply')),
    ],
  );
}

class _ReportDecisionDialog extends StatefulWidget {
  const _ReportDecisionDialog({
    required this.title,
    required this.requiresOutcome,
    required this.currentPriority,
  });

  final String title;
  final bool requiresOutcome;
  final int currentPriority;

  @override
  State<_ReportDecisionDialog> createState() => _ReportDecisionDialogState();
}

class _ReportDecisionDialogState extends State<_ReportDecisionDialog> {
  final _notes = TextEditingController();
  String _outcome = 'insufficient_information';
  late int _priority = widget.currentPriority.clamp(1, 3).toInt();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: LocalizedText(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.requiresOutcome) ...[
            const LocalizedText('Outcome'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              isExpanded: true,
              itemHeight: null,
              isDense: false,
              initialValue: _outcome,
              items: const [
                DropdownMenuItem(
                  value: 'action_taken',
                  child: LocalizedText('Action taken'),
                ),
                DropdownMenuItem(
                  value: 'no_violation_found',
                  child: LocalizedText('No violation found'),
                ),
                DropdownMenuItem(
                  value: 'insufficient_information',
                  child: LocalizedText('Insufficient information'),
                ),
                DropdownMenuItem(
                  value: 'duplicate',
                  child: LocalizedText('Duplicate report'),
                ),
                DropdownMenuItem(
                  value: 'other',
                  child: LocalizedText('Other outcome'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _outcome = value ?? _outcome),
            ),
            const SizedBox(height: 12),
          ],
          const LocalizedText('Queue priority'),
          Slider(
            value: _priority.toDouble(),
            min: 1,
            max: 3,
            divisions: 2,
            label: '$_priority',
            onChanged: (value) => setState(() => _priority = value.round()),
          ),
          TextField(
            controller: _notes,
            maxLength: 2000,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate(
                'Private moderator note (optional)',
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const LocalizedText('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop({
          'outcome': _outcome,
          'priority': _priority,
          'notes': _notes.text.trim(),
        }),
        child: const LocalizedText('Save decision'),
      ),
    ],
  );
}

class _AppealNotesDialog extends StatefulWidget {
  const _AppealNotesDialog({required this.title});

  final String title;

  @override
  State<_AppealNotesDialog> createState() => _AppealNotesDialogState();
}

class _AppealNotesDialogState extends State<_AppealNotesDialog> {
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: LocalizedText(widget.title),
    content: TextField(
      controller: _notes,
      maxLength: 2000,
      minLines: 2,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: AppLanguageService.translate(
          'Private moderator note (optional)',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const LocalizedText('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.of(context).pop({'notes': _notes.text.trim()}),
        child: const LocalizedText('Continue'),
      ),
    ],
  );
}
