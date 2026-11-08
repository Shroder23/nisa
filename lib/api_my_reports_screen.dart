import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/app_language_service.dart';

import 'services/api_safety_service.dart';
import 'widgets/localized_text.dart';

class ApiMyReportsScreen extends StatefulWidget {
  const ApiMyReportsScreen({super.key});

  @override
  State<ApiMyReportsScreen> createState() => _ApiMyReportsScreenState();
}

class _ApiMyReportsScreenState extends State<ApiMyReportsScreen> {
  late Future<List<Map<String, dynamic>>> _reports =
      ApiSafetyService.getMyReports();
  final Set<String> _submittingAppeals = {};

  Future<void> _refresh() async {
    final next = ApiSafetyService.getMyReports();
    setState(() {
      _reports = next;
    });
    await next;
  }

  String _status(Map<String, dynamic> report) {
    final appeal = report['appeal_status']?.toString() ?? 'none';
    if (appeal == 'pending') return 'Appeal pending';
    if (appeal == 'rejected') return 'Appeal declined';
    if (appeal == 'accepted' && report['status'] == 'reviewing') {
      return 'Appeal accepted';
    }
    return switch (report['status']?.toString()) {
      'pending' => 'Waiting for review',
      'reviewing' => 'Under review',
      'resolved' => 'Reviewed',
      'dismissed' => 'Closed',
      _ => 'Status unavailable',
    };
  }

  String _nextStep(Map<String, dynamic> report) {
    final appeal = report['appeal_status']?.toString() ?? 'none';
    if (appeal == 'pending') return 'Appeal pending';
    if (appeal == 'rejected') return 'Case closed';
    if (appeal == 'accepted' && report['status'] == 'reviewing') {
      return 'Under review';
    }
    return switch (report['status']?.toString()) {
      'pending' => 'No action needed now',
      'reviewing' => 'Under review',
      'resolved' => 'Reviewed',
      'dismissed' => 'Case closed',
      _ => 'Status unavailable',
    };
  }

  Future<String?> _appealDialog() async {
    var appealDetails = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Request a review'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => appealDetails = value,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          decoration: InputDecoration(
            hintText: AppLanguageService.translate(
              'Explain why this report should be reviewed again (10–1000 characters).',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = appealDetails.trim();
              if (value.length < 10) return;
              Navigator.pop(dialogContext, value);
            },
            child: const LocalizedText('Send appeal'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _submitAppeal(String reportId) async {
    final details = await _appealDialog();
    if (details == null || !mounted) return;
    setState(() => _submittingAppeals.add(reportId));
    try {
      await ApiSafetyService.submitReportAppeal(reportId, details);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Appeal submitted for review')),
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
      if (mounted) setState(() => _submittingAppeals.remove(reportId));
    }
  }

  Widget _message(Widget message) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Center(
            child: Padding(padding: const EdgeInsets.all(20), child: message),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('My reports'),
      actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: NisaPageBody(
      form: false,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _reports,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message(
              LocalizedText('Something went wrong. Please try again.'),
            );
          }
          if (!snapshot.hasData) {
            return _message(const CircularProgressIndicator());
          }
          final reports = snapshot.data!;
          if (reports.isEmpty) {
            return _message(
              const LocalizedText('You have not submitted any reports.'),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final report = reports[index];
                final reportId = report['id']?.toString() ?? '';
                final created = DateTime.tryParse(
                  report['created_at']?.toString() ?? '',
                )?.toLocal();
                final appealAllowed = report['appeal_allowed'] == true;
                final busy = _submittingAppeals.contains(reportId);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report['reason']?.toString() ?? 'Report',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const LocalizedText('Status'),
                            const LocalizedText(': '),
                            LocalizedText(_status(report)),
                          ],
                        ),
                        if (created != null)
                          LocalizedText(
                            'Submitted: {date}',
                            substitutions: {
                              'date': created.toString().split('.').first,
                            },
                          ),
                        const SizedBox(height: 8),
                        LocalizedText(_nextStep(report)),
                        if (appealAllowed) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => _submitAppeal(reportId),
                              icon: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.rate_review_outlined),
                              label: const LocalizedText('Request a review'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );
}
