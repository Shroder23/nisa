import 'presentation/nisa_premium/nisa_premium.dart';

import 'package:flutter/material.dart';

import 'services/api_privacy_service.dart';
import 'services/app_language_service.dart';
import 'widgets/language_selector_button.dart';
import 'widgets/localized_text.dart';

class ApiPrivacySettingsScreen extends StatefulWidget {
  const ApiPrivacySettingsScreen({super.key});

  @override
  State<ApiPrivacySettingsScreen> createState() =>
      _ApiPrivacySettingsScreenState();
}

class _ApiPrivacySettingsScreenState
    extends LanguageAwareState<ApiPrivacySettingsScreen> {
  ApiPrivacySettings _settings = const ApiPrivacySettings();
  bool _loading = true;
  bool _saving = false;
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
      final settings = await ApiPrivacyService.getSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load privacy settings.';
      });
    }
  }

  Future<void> _save(ApiPrivacySettings next) async {
    if (_saving) return;
    final previous = _settings;
    setState(() {
      _settings = next;
      _saving = true;
    });
    try {
      final saved = await ApiPrivacyService.updateSettings(next);
      if (!mounted) return;
      setState(() => _settings = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _settings = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Could not save privacy settings.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Privacy settings'),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: true,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LocalizedText(_error!),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const LocalizedText('Try again'),
                    ),
                  ],
                ),
              )
            : ListView(
                children: [
                  SwitchListTile.adaptive(
                    value: _settings.showOnlineStatus,
                    onChanged: _saving
                        ? null
                        : (value) => _save(
                            ApiPrivacySettings(
                              showOnlineStatus: value,
                              shareReadReceipts: _settings.shareReadReceipts,
                            ),
                          ),
                    title: const LocalizedText('Online and last seen'),
                    subtitle: const LocalizedText(
                      'Matched members can see your online status and last-seen time.',
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    value: _settings.shareReadReceipts,
                    onChanged: _saving
                        ? null
                        : (value) => _save(
                            ApiPrivacySettings(
                              showOnlineStatus: _settings.showOnlineStatus,
                              shareReadReceipts: value,
                            ),
                          ),
                    title: const LocalizedText('Read receipts'),
                    subtitle: const LocalizedText(
                      'Matched members can see when you have read their messages.',
                    ),
                  ),
                  if (_saving) const LinearProgressIndicator(minHeight: 2),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: LocalizedText(
                      'Privacy settings apply only to members you have matched with.',
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
