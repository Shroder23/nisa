import 'presentation/nisa_premium/nisa_premium.dart';
import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'admin_verification_detail_screen.dart';
import 'models/admin_verification_request.dart';
import 'services/admin_verification_api_service.dart';

class AdminVerificationListScreen extends StatefulWidget {
  const AdminVerificationListScreen({super.key});

  @override
  State<AdminVerificationListScreen> createState() =>
      _AdminVerificationListScreenState();
}

class _AdminVerificationListScreenState
    extends LanguageAwareState<AdminVerificationListScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool _loading = false;
  String? _error;
  List<AdminVerificationRequest> _items = const [];

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter the admin key first.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await AdminVerificationApiService.pendingRequests(
        adminKey: key,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _open(AdminVerificationRequest request) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminVerificationDetailScreen(
          adminKey: _keyController.text.trim(),
          requestId: request.id,
        ),
      ),
    );

    if (!mounted) return;

    await _load();

    if (!mounted) return;

    if (result == 'rejected') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText(
            'Verification rejected. The user can submit corrected documents.',
          ),
        ),
      );
    } else if (result == 'approved') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Verification approved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Admin Verification'),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      'Admin Access',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keyController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: AppLanguageService.translate('Admin key'),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _load,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: LocalizedText(
                          _loading ? 'Loading...' : 'Load Pending Requests',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const LocalizedText('Error'),
                  subtitle: LocalizedText(_error!),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (!_loading && _items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 56),
                      SizedBox(height: 12),
                      LocalizedText('No pending requests loaded.'),
                    ],
                  ),
                ),
              ),
            ..._items.map(
              (request) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.verified_user_outlined),
                  ),
                  title: LocalizedText(
                    request.guardianName.isEmpty
                        ? 'Verification Request'
                        : request.guardianName,
                  ),
                  subtitle: LocalizedText(
                    [
                      'User: ${request.userId}',
                      if (request.guardianRelation.isNotEmpty)
                        'Relation: ${request.guardianRelation}',
                      if (request.createdAt.isNotEmpty)
                        'Submitted: ${request.createdAt}',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(request),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
