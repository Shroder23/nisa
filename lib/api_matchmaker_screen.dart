import 'presentation/nisa_premium/nisa_premium.dart';

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models/matchmaker_profile.dart';
import 'services/api_matchmaker_service.dart';
import 'services/app_language_service.dart';
import 'services/matchmaker_import_service.dart';
import 'widgets/localized_text.dart';

class ApiMatchmakerScreen extends StatefulWidget {
  const ApiMatchmakerScreen({super.key});
  @override
  State<ApiMatchmakerScreen> createState() => _ApiMatchmakerScreenState();
}

class _ApiMatchmakerScreenState extends State<ApiMatchmakerScreen> {
  bool _loading = true;
  Map<String, dynamic>? _account;
  List<MatchmakerProfile> _profiles = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final a = await ApiMatchmakerService.getMyPartnerAccount();
      var p = <MatchmakerProfile>[];
      if (a != null && a['status'] == 'approved') {
        p = await ApiMatchmakerService.listProfiles();
      }
      if (mounted) {
        setState(() {
          _account = a;
          _profiles = p;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Matchmaker Network')),
      body: NisaPageBody(
        form: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _message(_error!, retry: true)
            : _account == null
            ? _application()
            : _account!['status'] != 'approved'
            ? _pending()
            : _dashboard(),
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              child: const LocalizedText('Try Again'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _application() {
    final name = TextEditingController();
    final phone = TextEditingController();
    final notes = TextEditingController();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.handshake_outlined, size: 64),
        const SizedBox(height: 12),
        LocalizedText(
          'Join the Nisa Matchmaker Network',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const LocalizedText(
          'Manage your own clients, import existing biodata safely, request consent, and collaborate through Nisa without exposing your private client database.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            label: LocalizedText('Business / matchmaker name'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            label: LocalizedText('Business phone'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(
            label: LocalizedText('About your matchmaking work'),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.verified_user_outlined),
          label: const LocalizedText('Apply as matchmaker'),
          onPressed: () async {
            if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
            final messenger = ScaffoldMessenger.of(context);
            try {
              await ApiMatchmakerService.apply(
                businessName: name.text.trim(),
                phone: phone.text.trim(),
                notes: notes.text.trim(),
              );
              await _load();
            } catch (e) {
              if (mounted) {
                messenger.showSnackBar(SnackBar(content: Text(e.toString())));
              }
            }
          },
        ),
      ],
    );
  }

  Widget _pending() => _message(
    AppLanguageService.translateTemplate(
      'Your matchmaker application is {status}. Nisa will enable client-management tools after review.',
      {'status': _account!['status'] ?? 'pending'},
    ),
  );

  Widget _dashboard() {
    final pending = _profiles
        .where((p) => p.consentStatus != 'approved')
        .length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _account!['business_name']?.toString() ??
                AppLanguageService.translate('Matchmaker Network'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('Clients', _profiles.length),
              _stat('Consent pending', pending),
              _stat(
                'Active',
                _profiles.where((p) => p.visibility == 'active').length,
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _openImport,
            icon: const Icon(Icons.person_add_alt_1),
            label: const LocalizedText('Import client profiles'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _profiles.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.download_outlined),
            label: const LocalizedText('Export my represented profiles'),
          ),
          const SizedBox(height: 20),
          const LocalizedText(
            'Represented clients',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 8),
          if (_profiles.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: LocalizedText(
                  'No client profiles yet. Import WhatsApp biodata, CSV, or JSON to create private drafts.',
                ),
              ),
            ),
          ..._profiles.map(_profileTile),
        ],
      ),
    );
  }

  Widget _stat(String label, int value) => Chip(
    avatar: CircleAvatar(child: Text(value.toString())),
    label: LocalizedText(label),
  );

  Widget _profileTile(MatchmakerProfile p) => Card(
    child: ListTile(
      title: Text(p.fullName),
      subtitle: LocalizedRichText(
        spanBuilder: () => TextSpan(
          children: [
            TextSpan(text: AppLanguageService.translate(p.gender)),
            if (p.age != null)
              TextSpan(text: ' • ${AppLanguageService.formatNumber(p.age!)}'),
            if (p.city.isNotEmpty) TextSpan(text: ' • ${p.city}'),
            if (p.profession.isNotEmpty) TextSpan(text: '\n${p.profession}'),
            TextSpan(
              text:
                  '\n${AppLanguageService.translateTemplate('Consent: {status}', {'status': p.consentStatus})}',
            ),
          ],
        ),
      ),
      trailing: p.id != null && p.consentStatus != 'approved'
          ? TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ApiMatchmakerService.requestConsent(p.id!);
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: LocalizedText('Consent request sent.'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const LocalizedText('Consent'),
            )
          : null,
    ),
  );

  Future<void> _openImport() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const MatchmakerImportScreen()),
    );
    if (changed == true) {
      await _load();
    }
  }

  Future<void> _exportCsv() async {
    final uri = await FilePicker.saveFile(
      fileName: 'nisa-represented-profiles.csv',
      bytes: utf8.encode(MatchmakerImportService.toCsv(_profiles)),
      mimeType: 'text/csv',
      dialogTitle: AppLanguageService.translate(
        'Export my represented profiles',
      ),
    );
    if (!mounted || uri == null) return;
  }
}

class MatchmakerImportScreen extends StatefulWidget {
  const MatchmakerImportScreen({super.key});
  @override
  State<MatchmakerImportScreen> createState() => _MatchmakerImportScreenState();
}

class _MatchmakerImportScreenState extends State<MatchmakerImportScreen> {
  final _text = TextEditingController();
  List<MatchmakerProfile> _profiles = const [];
  List<String> _warnings = const [];
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parseText() {
    final r = MatchmakerImportService.parseText(_text.text);
    setState(() {
      _profiles = r.profiles;
      _warnings = r.warnings;
    });
  }

  Future<void> _createDrafts() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ApiMatchmakerService.importProfiles(_profiles);
      if (!mounted) return;
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('Import client profiles')),
    body: NisaPageBody(
      form: false,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const LocalizedText(
            'Imports are created as private drafts. They are not published until consent and required verification are complete.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              label: LocalizedText('Paste WhatsApp / biodata text'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _parseText,
            child: const LocalizedText('Parse pasted biodata'),
          ),
          if (_warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._warnings.map(
              (w) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      w,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_profiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            LocalizedRichText(
              spanBuilder: () => TextSpan(
                text: AppLanguageService.translateTemplate(
                  'Profiles ready for review: {count}',
                  {'count': AppLanguageService.formatNumber(_profiles.length)},
                ),
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            ..._profiles.map(
              (p) => Card(
                child: ListTile(
                  title: Text(p.fullName),
                  subtitle: LocalizedRichText(
                    spanBuilder: () => TextSpan(
                      children: [
                        TextSpan(text: AppLanguageService.translate(p.gender)),
                        if (p.age != null)
                          TextSpan(
                            text:
                                ' • ${AppLanguageService.formatNumber(p.age!)}',
                          ),
                        if (p.city.isNotEmpty) TextSpan(text: ' • ${p.city}'),
                        if (p.profession.isNotEmpty)
                          TextSpan(text: '\n${p.profession}'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _createDrafts,
              icon: const Icon(Icons.lock_outline),
              label: Text(_saving ? 'Saving…' : 'Create private drafts'),
            ),
          ],
        ],
      ),
    ),
  );
}
