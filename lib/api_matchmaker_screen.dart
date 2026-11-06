import 'package:flutter/material.dart';

import 'models/matchmaker_profile.dart';
import 'services/api_matchmaker_service.dart';
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _message(_error!, retry: true)
          : _account == null
          ? _application()
          : _account!['status'] != 'approved'
          ? _pending()
          : _dashboard(),
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
            FilledButton(onPressed: _load, child: const Text('Try again')),
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
        Text(
          'Join the Nisa Matchmaker Network',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Manage your own clients, import existing biodata safely, request consent, and collaborate through Nisa without exposing your private client database.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Business / matchmaker name',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Business phone'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'About your matchmaking work',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Apply as matchmaker'),
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
    'Your matchmaker application is ${_account!['status'] ?? 'pending'}. Nisa will enable client-management tools after review.',
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
            _account!['business_name']?.toString() ?? 'Matchmaker Dashboard',
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
            label: const Text('Import client profiles'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _profiles.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Export my represented profiles'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Represented clients',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 8),
          if (_profiles.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
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
    avatar: CircleAvatar(child: Text('$value')),
    label: Text(label),
  );

  Widget _profileTile(MatchmakerProfile p) => Card(
    child: ListTile(
      title: Text(p.fullName),
      subtitle: Text(
        [
          p.age?.toString(),
          p.profession,
          p.city,
          'Consent: ${p.consentStatus}',
        ].where((e) => e != null && e.toString().isNotEmpty).join(' • '),
      ),
      trailing: p.id != null && p.consentStatus != 'approved'
          ? TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ApiMatchmakerService.requestConsent(p.id!);
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Consent request sent.')),
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
              child: const Text('Consent'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export feature will be enabled in release build.'),
      ),
    );
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
      final result = await ApiMatchmakerService.importProfiles(_profiles);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result['created'] ?? _profiles.length} private draft profile(s).',
          ),
        ),
      );
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
    appBar: AppBar(title: const Text('Import client profiles')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Imports are created as private drafts. They are not published until consent and required verification are complete.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(
            labelText: 'Paste WhatsApp / biodata text',
            hintText: 'Name: Ayesha\nGender: Female\nAge: 26\nCity: Karachi\nEducation: MBBS\nProfession: Doctor\nLooking for: ...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: _parseText,
          child: const Text('Parse pasted biodata'),
        ),
        if (_warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._warnings.map(
            (w) => Text(
              '• $w',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        if (_profiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${_profiles.length} valid profile(s) ready for review',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          ..._profiles.map(
            (p) => Card(
              child: ListTile(
                title: Text(p.fullName),
                subtitle: Text(
                  '${p.gender}${p.age == null ? '' : ' • ${p.age}'}${p.city.isEmpty ? '' : ' • ${p.city}'}\n${p.profession}',
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
  );
}
