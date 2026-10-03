import 'package:flutter/material.dart';

import 'services/api_safety_service.dart';
import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';

class ApiModeratorLogsScreen extends StatefulWidget {
  const ApiModeratorLogsScreen({super.key});
  @override
  State<ApiModeratorLogsScreen> createState() => _ApiModeratorLogsScreenState();
}

class _ApiModeratorLogsScreenState extends State<ApiModeratorLogsScreen> {
  late Future<Map<String, dynamic>> _logs =
      ApiSafetyService.getModeratorLogsPage();
  bool _busy = false;
  bool _loadingOlder = false;
  List<Map<String, dynamic>> _loadedLogs = [];
  int? _nextBeforeId;

  void _refresh() => setState(() {
    _loadedLogs = [];
    _nextBeforeId = null;
    _logs = ApiSafetyService.getModeratorLogsPage();
  });

  Future<void> _loadOlder() async {
    if (_loadingOlder || _nextBeforeId == null) {
      return;
    }
    setState(() => _loadingOlder = true);
    try {
      final page = await ApiSafetyService.getModeratorLogsPage(
        beforeId: _nextBeforeId,
      );
      final rows = (page['logs'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _loadedLogs.addAll(rows);
        _nextBeforeId = page['next_before_id'] as int?;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingOlder = false);
      }
    }
  }

  String _eventLabel(String raw) => switch (raw) {
    'temporary_account_ban' => 'Temporary ban',
    'temporary_account_ban_revoked' => 'Temporary ban lifted',
    'pair_interaction_restriction' => 'Messaging restriction',
    'pair_interaction_restriction_revoked' => 'Messaging restriction lifted',
    'permanent_ban_vote' => 'Permanent ban request',
    'report_resolved' => 'Report resolved',
    'report_dismissed' => 'Report dismissed',
    'verification_approve' => 'Verification approved',
    'verification_reject' => 'Verification rejected',
    'verification_request_resubmission' =>
      'Verification resubmission requested',
    'admin_direct_permanent_ban' => 'Administrator permanent ban',
    'admin_overrode_moderator_sanction' => 'Administrator override',
    'recommendation_submitted' => 'Moderator recommendation',
    'recommendation_decided' => 'Recommendation decision',
    _ => raw.replaceAll('_', ' '),
  };

  Future<void> _override(
    Map<String, dynamic> log, {
    required bool decisionOverride,
  }) async {
    var reasonText = '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Override'),
        content: TextField(
          onChanged: (value) => reasonText = value,
          minLines: 3,
          maxLines: 5,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: AppLanguageService.translate('Reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonText.trim().length >= 10) {
                Navigator.pop(context, reasonText.trim());
              }
            },
            child: const LocalizedText('Override'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (decisionOverride) {
        await ApiSafetyService.overrideModeratorDecision(
          logId: (log['id'] as num).toInt(),
          reason: value,
        );
      } else {
        await ApiSafetyService.overrideModeratorSanction(
          sanctionId: log['sanction_id'].toString(),
          reason: value,
        );
      }
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: LocalizedText('Action taken')));
      }
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('Moderator Logs'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _logs,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(snapshot.error.toString()),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final page = snapshot.data!;
          if (_loadedLogs.isEmpty) {
            _loadedLogs = (page['logs'] as List).cast<Map<String, dynamic>>();
            _nextBeforeId = page['next_before_id'] as int?;
          }
          if (_loadedLogs.isEmpty) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: LocalizedText(
                    'No moderator actions have been recorded.',
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ..._loadedLogs.map((log) {
                final actor =
                    log['actor_name'] ?? log['actor_user_id'] ?? 'Moderator';
                final target =
                    log['target_name'] ?? log['target_user_id'] ?? '';
                final active = log['sanction_active'] == true;
                final eventType = log['event_type']?.toString() ?? '';
                final decisionOverride =
                    eventType == 'report_resolved' ||
                    eventType == 'report_dismissed' ||
                    eventType == 'verification_approve';
                final canOverrideSanction =
                    active && log['sanction_id'] != null;
                final canOverrideDecision =
                    decisionOverride && log['override_id'] == null;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.history),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LocalizedText(
                                _eventLabel(
                                  log['event_type']?.toString() ?? '',
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(child: Text(actor.toString())),
                            if (target.toString().isNotEmpty) ...[
                              const Icon(Icons.arrow_forward, size: 16),
                              Expanded(child: Text(target.toString())),
                            ],
                          ],
                        ),
                        if ((log['reason']?.toString() ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(log['reason'].toString()),
                        ],
                        if (log['occurred_at'] != null)
                          Text(
                            log['occurred_at'].toString(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (canOverrideSanction || canOverrideDecision)
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _override(
                                      log,
                                      decisionOverride: canOverrideDecision,
                                    ),
                              icon: Icon(Icons.undo),
                              label: LocalizedText(
                                !canOverrideDecision
                                    ? 'Override'
                                    : eventType.startsWith('report_')
                                    ? 'Reopen report'
                                    : 'Revoke verified badge',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              if (_nextBeforeId != null)
                Center(
                  child: TextButton.icon(
                    onPressed: _loadingOlder ? null : _loadOlder,
                    icon: _loadingOlder
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more),
                    label: LocalizedText('Load older activity'),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
