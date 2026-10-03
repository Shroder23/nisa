import 'package:flutter/material.dart';

import 'services/api_safety_service.dart';
import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

class ApiModeratorRequestsScreen extends StatefulWidget {
  const ApiModeratorRequestsScreen({
    super.key,
    this.administrator = false,
    this.initialTargetUserId,
    this.initialReportId,
  });

  final bool administrator;
  final String? initialTargetUserId;
  final String? initialReportId;

  @override
  State<ApiModeratorRequestsScreen> createState() =>
      _ApiModeratorRequestsScreenState();
}

class _ApiModeratorRequestsScreenState
    extends State<ApiModeratorRequestsScreen> {
  final _target = TextEditingController();
  final _reason = TextEditingController();
  String? _reportId;
  String? _witnessId;
  String? _reviewerGender;
  bool _busy = false;
  late Future<List<Map<String, dynamic>>> _requests;
  late Future<List<Map<String, dynamic>>> _cases;
  late Future<List<Map<String, dynamic>>> _witnesses;

  @override
  void initState() {
    super.initState();
    _target.text = widget.initialTargetUserId ?? '';
    _reportId = widget.initialReportId;
    _requests = widget.administrator
        ? Future.value(const <Map<String, dynamic>>[])
        : ApiSafetyService.getMyPermanentBanRequests();
    _cases = widget.administrator
        ? ApiSafetyService.getAdminModerationCases()
        : Future.value(const <Map<String, dynamic>>[]);
    _witnesses = widget.administrator
        ? Future.value(const <Map<String, dynamic>>[])
        : ApiSafetyService.getModeratorWitnesses();
    if (!widget.administrator) {
      _loadRole();
    }
  }

  Future<void> _loadRole() async {
    try {
      final value = await ApiSafetyService.getModeratorUiCapability();
      if (mounted) {
        setState(() => _reviewerGender = value['reviewer_gender']?.toString());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _target.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _statusLabel(String raw) => switch (raw) {
    'collecting' => 'Collecting',
    'sent_to_admin' => 'Sent to administrator',
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'withdrawn' => 'Withdrawn',
    _ => raw,
  };

  void _refresh() => setState(() {
    _requests = widget.administrator
        ? Future.value(const <Map<String, dynamic>>[])
        : ApiSafetyService.getMyPermanentBanRequests();
    _cases = widget.administrator
        ? ApiSafetyService.getAdminModerationCases()
        : Future.value(const <Map<String, dynamic>>[]);
    _witnesses = widget.administrator
        ? Future.value(const <Map<String, dynamic>>[])
        : ApiSafetyService.getModeratorWitnesses();
  });

  Future<void> _submitRequest({String? proposalId}) async {
    if (_target.text.trim().isEmpty || _reason.text.trim().length < 20) {
      _message('Please complete all required fields.');
      return;
    }
    if (_reviewerGender == 'female' &&
        _witnessId == null &&
        proposalId == null) {
      _message('Choose Involve a witness and select an eligible moderator.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ApiSafetyService.proposePermanentBan(
        targetUserId: _target.text.trim(),
        reportId: _reportId,
        proposalId: proposalId,
        witnessUserId: proposalId == null ? _witnessId : null,
        reason: _reason.text.trim(),
      );
      if (!mounted) {
        return;
      }
      final sent = result['sent_to_admin'] == true;
      _message(
        sent ? 'Moderator request sent to the administrator for final review.' : 'Request saved. The invited witness must review and support it before administrator review.',
      );
      _reason.clear();
      _refresh();
    } catch (error) {
      _message(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _message(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  Future<Map<String, dynamic>?> _adminDecision(String decision) async {
    var notesText = '';
    var denyPhoneText = '';
    bool denyEmail = false;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: LocalizedText(
            decision == 'permanent_ban'
                ? 'Permanent ban'
                : decision == 'delete_account'
                ? 'Delete account'
                : decision == 'reinstate'
                ? 'Reinstate account'
                : 'Dismiss request',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (value) => notesText = value,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.translate('Reason'),
                  ),
                ),
                if (decision == 'permanent_ban' ||
                    decision == 'delete_account') ...[
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
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const LocalizedText('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (notesText.trim().length < 10) {
                  return;
                }
                Navigator.pop(dialogContext, {
                  'notes': notesText.trim(),
                  'deny_email': denyEmail,
                  'deny_phone': denyPhoneText.trim(),
                });
              },
              child: const LocalizedText('Save decision'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decideCase(Map<String, dynamic> item, String decision) async {
    final form = await _adminDecision(decision);
    if (form == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiSafetyService.decideAdminModerationCase(
        item['id'].toString(),
        decision: decision,
        notes: form['notes'] as String,
        denyEmail: form['deny_email'] as bool,
        denyPhone: (form['deny_phone'] as String).isEmpty
            ? null
            : form['deny_phone'] as String,
      );
      if (!mounted) {
        return;
      }
      _refresh();
    } catch (error) {
      _message(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _adminCase(Map<String, dynamic> item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['target_name']?.toString() ??
                      item['target_user_id'].toString(),
                ),
              ),
              const SizedBox(width: 8),
              LocalizedText(
                item['case_type'] == 'permanent_ban_proposal'
                    ? 'Permanent ban'
                    : 'Temporary ban',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(item['reason']?.toString() ?? ''),
          if (item['case_type'] == 'permanent_ban_proposal')
            Row(
              children: [
                const LocalizedText('Support'),
                const SizedBox(width: 6),
                const LocalizedText('Male'),
                Text(item['male_support']?.toString() ?? '0'),
                const SizedBox(width: 8),
                const LocalizedText('Female'),
                Text(item['female_support']?.toString() ?? '0'),
              ],
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : () => _decideCase(item, 'reinstate'),
                child: const LocalizedText('Reinstate'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _decideCase(item, 'dismiss'),
                child: const LocalizedText('Dismiss'),
              ),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _decideCase(item, 'permanent_ban'),
                child: const LocalizedText('Permanent ban'),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _decideCase(item, 'delete_account'),
                child: const LocalizedText('Delete account'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Moderator Request'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.administrator) ...[
            const LocalizedText(
              'Only administrators can permanently ban or delete accounts.',
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _cases,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.data!.isEmpty) {
                  return const LocalizedText('No requests yet.');
                }
                return Column(
                  children: snapshot.data!.map(_adminCase).toList(),
                );
              },
            ),
          ] else ...[
            const LocalizedText(
              'Only administrators can permanently ban or delete accounts.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _target,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('User ID'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Reason'),
              ),
            ),
            if (_reviewerGender == 'female') ...[
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final requestContext = context;
                        final rows = await _witnesses;
                        if (!requestContext.mounted) {
                          return;
                        }
                        if (rows.isEmpty) {
                          _message(
                            'No eligible witness moderator is configured.',
                          );
                          return;
                        }
                        final picked = await showModalBottomSheet<String>(
                          context: requestContext,
                          builder: (context) => SafeArea(
                            child: ListView(
                              children: [
                                ListTile(
                                  title: const LocalizedText(
                                    'Involve a witness',
                                  ),
                                  subtitle: const LocalizedText(
                                    'You require one witness to support this request.',
                                  ),
                                ),
                                ...rows.map(
                                  (row) => ListTile(
                                    title: Text(
                                      row['display_name']?.toString() ??
                                          row['user_id'].toString(),
                                    ),
                                    subtitle: LocalizedText(
                                      row['reviewer_gender'] == 'male'
                                          ? 'Male'
                                          : 'Female',
                                    ),
                                    onTap: () => Navigator.pop(
                                      context,
                                      row['user_id'].toString(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() => _witnessId = picked);
                        }
                      },
                icon: const Icon(Icons.people_outline),
                label: const LocalizedText('Involve a witness'),
              ),
              const LocalizedText(
                'You require one witness to support this request.',
              ),
              if (_witnessId != null) const LocalizedText('Witness selected'),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : () => _submitRequest(),
              icon: const Icon(Icons.send),
              label: const LocalizedText('Submit'),
            ),
            const SizedBox(height: 22),
            Text(
              AppLanguageService.translate('My requests'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _requests,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.data!.isEmpty) {
                  return const LocalizedText('No requests yet.');
                }
                return Column(
                  children: snapshot.data!
                      .map(
                        (item) => Card(
                          child: ListTile(
                            title: Text(
                              item['target_name']?.toString() ??
                                  item['target_user_id'].toString(),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LocalizedText(
                                  _statusLabel(
                                    item['status']?.toString() ?? 'collecting',
                                  ),
                                ),
                                Row(
                                  children: [
                                    const LocalizedText('Support'),
                                    const SizedBox(width: 6),
                                    const LocalizedText('Male'),
                                    Text(
                                      item['male_support']?.toString() ?? '0',
                                    ),
                                    const SizedBox(width: 8),
                                    const LocalizedText('Female'),
                                    Text(
                                      item['female_support']?.toString() ?? '0',
                                    ),
                                  ],
                                ),
                                Text(item['reason']?.toString() ?? ''),
                              ],
                            ),
                            isThreeLine: true,
                            trailing:
                                item['witness_user_id'] != null &&
                                    item['already_supported'] != true &&
                                    item['status'] == 'collecting'
                                ? TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            _target.text =
                                                item['target_user_id']
                                                    .toString();
                                            _reason.text = item['reason']
                                                .toString();
                                            _reportId = item['report_id']
                                                ?.toString();
                                            _submitRequest(
                                              proposalId: item['id'].toString(),
                                            );
                                          },
                                    child: const LocalizedText('Support'),
                                  )
                                : null,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ],
      ),
    ),
  );
}
