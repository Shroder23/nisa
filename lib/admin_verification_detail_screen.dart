import 'presentation/nisa_premium/nisa_premium.dart';
import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/admin_verification_request.dart';
import 'secure_admin_video_screen.dart';
import 'services/admin_verification_api_service.dart';

class AdminVerificationDetailScreen extends StatefulWidget {
  final String adminKey;
  final String requestId;

  const AdminVerificationDetailScreen({
    super.key,
    required this.adminKey,
    required this.requestId,
  });

  @override
  State<AdminVerificationDetailScreen> createState() =>
      _AdminVerificationDetailScreenState();
}

class _AdminVerificationDetailScreenState
    extends LanguageAwareState<AdminVerificationDetailScreen> {
  late Future<AdminVerificationRequest> _future;
  late Future<Map<String, String>> _mediaHeaders;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _future = AdminVerificationApiService.requestDetails(
      adminKey: widget.adminKey,
      requestId: widget.requestId,
    );
    _mediaHeaders = AdminVerificationApiService.protectedMediaHeaders(
      adminKey: widget.adminKey,
    );
  }

  Future<void> _approve(AdminVerificationRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Approve verification?'),
        content: const LocalizedText(
          'Approve only after reviewing the parent/guardian ID and confirmation video.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      await AdminVerificationApiService.approve(
        adminKey: widget.adminKey,
        requestId: request.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop('approved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Future<void> _reject(AdminVerificationRequest request) async {
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _RejectVerificationDialog(),
    );

    if (!mounted || reason == null || reason.trim().isEmpty) return;

    setState(() => _working = true);

    try {
      await AdminVerificationApiService.reject(
        adminKey: widget.adminKey,
        requestId: request.id,
        reason: reason.trim(),
      );

      if (!mounted) return;

      // Return to the admin list and let the parent screen refresh itself.
      // Do not show a SnackBar and tear down this route in the same frame.
      Navigator.of(context).pop('rejected');
    } catch (e) {
      if (!mounted) return;

      setState(() => _working = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Verification Detail'),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: false,
        child: FutureBuilder<AdminVerificationRequest>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: LocalizedText('Something went wrong. Please try again.'),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final request = snapshot.data!;
            final idUrl = AdminVerificationApiService.resolveUrl(
              request.parentIdUrl,
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _InfoCard(
                  title: AppLanguageService.translate('Request'),
                  children: [
                    _InfoRow(
                      label: AppLanguageService.translate('Request ID'),
                      value: request.id,
                    ),
                    _InfoRow(
                      label: AppLanguageService.translate('User ID'),
                      value: request.userId,
                    ),
                    _InfoRow(
                      label: AppLanguageService.translate('Status'),
                      value: request.status,
                    ),
                    if (request.createdAt.isNotEmpty)
                      _InfoRow(
                        label: AppLanguageService.translate('Created'),
                        value: request.createdAt,
                      ),
                  ],
                ),
                _InfoCard(
                  title: AppLanguageService.translate('Parent / Guardian'),
                  children: [
                    _InfoRow(
                      label: AppLanguageService.translate('Name'),
                      value: request.guardianName.isEmpty
                          ? 'Not provided'
                          : request.guardianName,
                    ),
                    _InfoRow(
                      label: AppLanguageService.translate('Relation'),
                      value: request.guardianRelation.isEmpty
                          ? 'Not provided'
                          : request.guardianRelation,
                    ),
                  ],
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LocalizedText(
                          'Parent ID',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        if (idUrl.isEmpty)
                          const LocalizedText('No parent ID file found.')
                        else
                          FutureBuilder<Map<String, String>>(
                            future: _mediaHeaders,
                            builder: (context, headersSnapshot) {
                              if (headersSnapshot.hasError) {
                                return LocalizedText(
                                  'Could not authorize ID preview: '
                                  '${headersSnapshot.error}',
                                );
                              }
                              if (!headersSnapshot.hasData) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(20),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(
                                  idUrl,
                                  headers: headersSnapshot.data!,
                                  height: 280,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: LocalizedText(
                                        'This ID may be a PDF or could not be '
                                        'previewed as an image.',
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.video_file_outlined),
                    title: const LocalizedText('Parent Confirmation Video'),
                    subtitle: const LocalizedText(
                      'Protected admin-only playback',
                    ),
                    trailing: const Icon(Icons.play_circle_outline),
                    onTap: request.parentVideoUrl.isEmpty
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SecureAdminVideoScreen(
                                  adminKey: widget.adminKey,
                                  protectedUrl: request.parentVideoUrl,
                                ),
                              ),
                            );
                          },
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _working || request.status != 'pending'
                      ? null
                      : () => _approve(request),
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined),
                  label: const LocalizedText('Approve Verification'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _working || request.status != 'pending'
                      ? null
                      : () => _reject(request),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const LocalizedText('Reject Verification'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocalizedText(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: LocalizedText(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _RejectVerificationDialog extends StatefulWidget {
  const _RejectVerificationDialog();

  @override
  State<_RejectVerificationDialog> createState() =>
      _RejectVerificationDialogState();
}

class _RejectVerificationDialogState
    extends LanguageAwareState<_RejectVerificationDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _canReject = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateState);
  }

  void _updateState() {
    final canReject = _controller.text.trim().length >= 3;

    if (canReject != _canReject && mounted) {
      setState(() => _canReject = canReject);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateState)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const LocalizedText('Reject verification'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 5,
        maxLength: 500,
        decoration: InputDecoration(
          labelText: AppLanguageService.translate('Reason'),
          hintText: AppLanguageService.translate(
            'Explain what must be corrected before resubmission.',
          ),
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const LocalizedText('Cancel'),
        ),
        FilledButton(
          onPressed: _canReject
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const LocalizedText('Reject'),
        ),
      ],
    );
  }
}
