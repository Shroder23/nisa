import 'dart:async';

import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/user_profile.dart';
import 'services/firestore_service.dart';
import 'services/location_service.dart';
import 'services/app_language_service.dart';
import 'services/app_state.dart';
import 'services/api_app_state.dart';
import 'matrimonial_preferences_screen.dart';

class ProfileDetailsScreen extends StatefulWidget {
  final UserProfile profile;

  const ProfileDetailsScreen({super.key, required this.profile});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState
    extends LanguageAwareState<ProfileDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _professionController = TextEditingController();

  String? _height;
  String _religion = 'Islam';
  String? _sect = 'Sunni';
  List<String> _sects = const ['Sunni'];
  bool _sectsLoading = false;
  String? _caste;
  List<String> _castes = const ['Any caste', 'Other / Not listed'];
  bool _castesLoading = false;
  String? _religiousPractice;
  String? _language;
  String? _relocation;
  List<String> _languages = List<String>.from(LocationService.offlineLanguages);

  @override
  void initState() {
    super.initState();
    _language = 'Urdu';
    _religion = widget.profile.religion?.trim().isNotEmpty == true
        ? widget.profile.religion!.trim()
        : 'Islam';
    _sect = widget.profile.sect?.trim().isNotEmpty == true
        ? widget.profile.sect!.trim()
        : (_religion == 'Islam' ? 'Sunni' : null);
    _caste = widget.profile.caste?.trim().isNotEmpty == true
        ? widget.profile.caste!.trim()
        : null;
    _sectsLoading = true;
    _castesLoading = true;
    unawaited(_loadSects(_religion));
    unawaited(_loadCastes(widget.profile.country ?? 'Pakistan'));
    LocationService.languages().then((values) {
      if (mounted) setState(() => _languages = values);
    });
  }

  Future<void> _loadSects(String religion) async {
    final values = await LocationService.sects(religion);
    if (!mounted || _religion != religion) return;
    setState(() {
      _sects = values;
      if (_sect != null && !values.contains(_sect)) _sect = null;
      _sectsLoading = false;
    });
  }

  Future<void> _loadCastes(String country) async {
    final values = await LocationService.castes(country);
    if (!mounted || (widget.profile.country ?? 'Pakistan') != country) return;
    setState(() {
      _castes = values;
      if (_caste != null && !values.contains(_caste)) _caste = null;
      _castesLoading = false;
    });
  }

  @override
  void dispose() {
    _professionController.dispose();
    super.dispose();
  }

  Future<void> _handleBack() async {
    // When this screen was pushed from Basic Profile, return to that step.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    // Google registration can display Profile Details as the root route.
    // In that case Back means cancel this unfinished registration and return
    // to Welcome instead of leaving the button with no visible effect.
    await AppState.clearUser();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_height == null ||
        _religiousPractice == null ||
        _language == null ||
        _relocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Please complete all required fields.'),
        ),
      );
      return;
    }

    widget.profile.height = _height;
    widget.profile.religion = _religion;
    widget.profile.sect = _sect;
    widget.profile.caste = _caste;
    widget.profile.profession = _professionController.text.trim();
    widget.profile.religiousPractice = _religiousPractice;
    widget.profile.language = _language;
    widget.profile.relocation = _relocation;

    try {
      // Save locally first. Cloud writes are retried by the normal sync path
      // and must not trap the user during a temporary outage.
      await AppState.setUser(widget.profile);
      if (!ApiAppState.isSignedIn) {
        try {
          await FirestoreService.createUserProfile(widget.profile);
          await FirestoreService.setRegistrationStep(
            uid: widget.profile.uid!,
            step: 'profile_details',
          );
        } catch (error) {
          debugPrint('Profile details sync deferred: $error');
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MatrimonialPreferencesScreen(profile: widget.profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: LocalizedText('Profile Details'),
        centerTitle: true,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: _handleBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: const [LanguageSelectorButton()],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  for (int i = 0; i < 4; i++) ...[
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    if (i < 3) const SizedBox(width: 6),
                  ],
                ],
              ),

              const SizedBox(height: 28),

              LocalizedText(
                'Tell us a little more',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              LocalizedText(
                'These details help families understand your background and preferences.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),

              const SizedBox(height: 28),

              DropdownButtonFormField<String>(
                initialValue: LocationService.heightOptions.contains(_height)
                    ? _height
                    : null,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Height'),
                  prefixIcon: Icon(Icons.height),
                  border: OutlineInputBorder(),
                ),
                items: LocationService.heightOptions
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: LocalizedHeightText(value),
                      ),
                    )
                    .toList(),
                /* items: const [
                  DropdownMenuItem(value: '4\'10"', child: LocalizedText('4\'10"')),
                  DropdownMenuItem(value: '4\'11"', child: LocalizedText('4\'11"')),
                  DropdownMenuItem(value: '5\'0"', child: LocalizedText('5\'0"')),
                  DropdownMenuItem(value: '5\'1"', child: LocalizedText('5\'1"')),
                  DropdownMenuItem(value: '5\'2"', child: LocalizedText('5\'2"')),
                  DropdownMenuItem(value: '5\'3"', child: LocalizedText('5\'3"')),
                  DropdownMenuItem(value: '5\'4"', child: LocalizedText('5\'4"')),
                  DropdownMenuItem(value: '5\'5"', child: LocalizedText('5\'5"')),
                  DropdownMenuItem(value: '5\'6"', child: LocalizedText('5\'6"')),
                  DropdownMenuItem(value: '5\'7"', child: LocalizedText('5\'7"')),
                  DropdownMenuItem(value: '5\'8"', child: LocalizedText('5\'8"')),
                  DropdownMenuItem(value: '5\'9"', child: LocalizedText('5\'9"')),
                  DropdownMenuItem(value: '5\'10"', child: LocalizedText('5\'10"')),
                  DropdownMenuItem(value: '5\'11"', child: LocalizedText('5\'11"')),
                  DropdownMenuItem(value: '6\'0"', child: LocalizedText('6\'0"')),
                  DropdownMenuItem(value: '6\'1"', child: LocalizedText('6\'1"')),
                  DropdownMenuItem(value: '6\'2"', child: LocalizedText('6\'2"')),
                  DropdownMenuItem(value: '6\'3"', child: LocalizedText('6\'3"')),
                  DropdownMenuItem(value: '6\'4"', child: LocalizedText('6\'4"')),
                ], */
                onChanged: (value) {
                  setState(() {
                    _height = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select your height';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              const SizedBox(height: 18),

              TextFormField(
                controller: _professionController,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Profession'),
                  prefixIcon: Icon(Icons.work_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your profession';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                initialValue: _sects.contains(_sect) ? _sect : null,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Sect'),
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                  border: const OutlineInputBorder(),
                ),
                items: _sects
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: LocalizedText(value),
                      ),
                    )
                    .toList(),
                onChanged: _sectsLoading
                    ? null
                    : (value) => setState(() => _sect = value),
                validator: (value) {
                  if (_sectsLoading) return null;
                  if (value == null) return 'Please select an option';
                  return null;
                },
              ),

              if (_sectsLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),

              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                initialValue: _castes.contains(_caste) ? _caste : null,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Caste'),
                  prefixIcon: const Icon(Icons.groups_outlined),
                  border: const OutlineInputBorder(),
                ),
                items: _castes
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: LocalizedText(value),
                      ),
                    )
                    .toList(),
                onChanged: _castesLoading
                    ? null
                    : (value) => setState(() => _caste = value),
              ),
              if (_castesLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),

              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                initialValue:
                    const [
                      'Practicing',
                      'Moderately Practicing',
                      'Prefer not to say',
                    ].contains(_religiousPractice)
                    ? _religiousPractice
                    : null,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Religious Practice'),
                  prefixIcon: Icon(Icons.mosque_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Practicing',
                    child: LocalizedText('Practicing'),
                  ),
                  DropdownMenuItem(
                    value: 'Moderately Practicing',
                    child: LocalizedText('Moderately Practicing'),
                  ),
                  DropdownMenuItem(
                    value: 'Prefer not to say',
                    child: LocalizedText('Prefer not to say'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _religiousPractice = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select an option';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                initialValue: _languages.contains(_language) ? _language : null,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Primary Language'),
                  prefixIcon: Icon(Icons.language),
                  border: OutlineInputBorder(),
                ),
                items: _languages
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: LocalizedText(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _language = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a language';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                initialValue:
                    const [
                      'Willing to relocate',
                      'Not willing to relocate',
                      'Maybe',
                    ].contains(_relocation)
                    ? _relocation
                    : null,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate(
                    'Willing to Relocate',
                  ),
                  prefixIcon: Icon(Icons.flight_takeoff_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Willing to relocate',
                    child: LocalizedText('Willing to relocate'),
                  ),

                  DropdownMenuItem(
                    value: 'Not willing to relocate',
                    child: LocalizedText('Not willing to relocate'),
                  ),

                  DropdownMenuItem(
                    value: 'Maybe',
                    child: LocalizedText('Maybe'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _relocation = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select an option';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _continue,
                  child: const LocalizedText(
                    'Continue',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
