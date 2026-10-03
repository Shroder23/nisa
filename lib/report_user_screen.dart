import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'services/app_state.dart';
import 'services/api_app_state.dart';
import 'services/api_auth_service.dart';
import 'services/api_safety_service.dart';
import 'services/report_service.dart';

class ReportUserScreen extends StatefulWidget {
  final String reportedUserId;
  final String reportedUserName;

  const ReportUserScreen({
    super.key,
    required this.reportedUserId,
    required this.reportedUserName,
  });

  @override
  State<ReportUserScreen> createState() => _ReportUserScreenState();
}

class _ReportUserScreenState extends LanguageAwareState<ReportUserScreen> {
  final TextEditingController _detailsController = TextEditingController();

  String _reason = 'Inappropriate profile';
  bool _submitting = false;

  final List<String> _reasons = const [
    'Spam',
    'Inappropriate profile',
    'Fake or misleading information',
    'Harassment or disrespectful behavior',
    'Scam or suspicious activity',
    'Already married / dishonest status',
    'Other',
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final apiSession = ApiAppState.isSignedIn;
    final String? reporterId;
    if (apiSession) {
      final account = ApiAuthService.currentAccount.value;
      reporterId = account == null ? null : account['id']?.toString();
    } else {
      reporterId = AppState.firebaseUser?.uid;
    }

    if (reporterId == null || reporterId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Please sign in again.')),
      );
      return;
    }

    final details = _detailsController.text.trim();

    if (_reason == 'Other' && details.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Please explain the issue in at least 10 characters.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      if (apiSession) {
        await ApiSafetyService.submitReport(
          userId: widget.reportedUserId,
          reason: _reason,
          details: details,
        );
      } else {
        await ReportService.submitReport(
          reporterId: reporterId,
          reportedUserId: widget.reportedUserId,
          reason: _reason,
          details: details,
        );
      }

      if (!mounted) return;

      setState(() => _submitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Report submitted for review.')),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() => _submitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.reportedUserName.trim().isEmpty
        ? 'this user'
        : widget.reportedUserName.trim();

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Report Profile'),
        actions: const [LanguageSelectorButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            Icons.flag_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          LocalizedText(
            'Report {name}',
            substitutions: {'name': name},
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const LocalizedText(
            'Use this only for genuine safety, privacy, honesty, or misuse concerns.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Reason'),
              border: OutlineInputBorder(),
            ),
            items: _reasons
                .map(
                  (reason) => DropdownMenuItem(
                    value: reason,
                    child: LocalizedText(reason),
                  ),
                )
                .toList(),
            onChanged: _submitting
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _reason = value);
                  },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _detailsController,
            enabled: !_submitting,
            minLines: 4,
            maxLines: 7,
            decoration: InputDecoration(
              labelText: AppLanguageService.translate('Details'),
              hintText: AppLanguageService.translate(
                'Explain what happened. Do not include private documents unless necessary.',
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: LocalizedText(
              _submitting ? 'Submitting...' : 'Submit Report',
            ),
          ),
        ],
      ),
    );
  }
}
