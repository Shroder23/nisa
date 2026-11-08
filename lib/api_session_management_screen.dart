import 'presentation/nisa_premium/nisa_premium.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'services/api_app_state.dart';
import 'services/api_auth_service.dart';
import 'services/app_language_service.dart';
import 'widgets/language_selector_button.dart';
import 'widgets/localized_text.dart';

class ApiSessionManagementScreen extends StatefulWidget {
  const ApiSessionManagementScreen({super.key});

  @override
  State<ApiSessionManagementScreen> createState() =>
      _ApiSessionManagementScreenState();
}

class _ApiSessionManagementScreenState
    extends LanguageAwareState<ApiSessionManagementScreen> {
  List<Map<String, dynamic>> _sessions = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiAuthService.get('/api/auth/sessions');
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(_detail(decoded));
      }
      if (decoded is! Map<String, dynamic> || decoded['sessions'] is! List) {
        throw StateError('Could not load sessions.');
      }
      final sessions = (decoded['sessions'] as List)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load sessions.';
      });
    }
  }

  static String _detail(dynamic decoded) {
    if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
      return decoded['detail'].toString();
    }
    return 'Could not load sessions.';
  }

  Future<void> _revoke(Map<String, dynamic> session) async {
    if (_busy || session['is_current'] == true) return;
    final sessionId = session['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Revoke this session?'),
        content: const LocalizedText('That device will be signed out.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final response = await ApiAuthService.delete(
        '/api/auth/sessions/${Uri.encodeComponent(sessionId)}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Could not revoke session.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Session revoked.')),
      );
      await _loadSessions();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Could not revoke session.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOutEverywhere() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Sign out of all devices?'),
        content: const LocalizedText(
          'This will sign out every device using your account, including this one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('Sign out everywhere'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ApiAuthService.revokeAllSessions();
      await ApiAppState.clearLocalSession();
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Could not sign out everywhere.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _lastActive(dynamic value) {
    if (value == null) return '';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return '';
    final label = AppLanguageService.translate('Last active');
    return '$label: ${parsed.toLocal()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Signed-in devices'),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LocalizedText('Could not load sessions.'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _loadSessions,
                      child: const LocalizedText('Try again'),
                    ),
                  ],
                ),
              )
            : ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: LocalizedText('Manage your active sessions.'),
                  ),
                  if (_sessions.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.devices_other_outlined),
                      title: LocalizedText('No active sessions found.'),
                    ),
                  for (final session in _sessions)
                    ListTile(
                      leading: Icon(
                        session['is_current'] == true
                            ? Icons.phone_android
                            : Icons.devices_other_outlined,
                      ),
                      title: Text(
                        session['device_label']?.toString().trim().isNotEmpty ==
                                true
                            ? session['device_label'].toString()
                            : AppLanguageService.translate('Unknown device'),
                      ),
                      subtitle: Text(
                        [
                          if (_lastActive(session['last_used_at']).isNotEmpty)
                            _lastActive(session['last_used_at']),
                        ].join(' · '),
                      ),
                      trailing: session['is_current'] == true
                          ? const Chip(label: LocalizedText('This device'))
                          : TextButton(
                              onPressed: _busy ? null : () => _revoke(session),
                              child: const LocalizedText('Revoke'),
                            ),
                    ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _signOutEverywhere,
                      icon: const Icon(Icons.logout),
                      label: const LocalizedText('Sign out of all devices'),
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
      ),
    );
  }
}
