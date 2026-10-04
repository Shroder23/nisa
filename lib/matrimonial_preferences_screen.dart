import 'dart:async';

import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/matrimonial_preferences.dart';
import 'models/user_profile.dart';
import 'profile_details_screen.dart';
import 'services/app_state.dart';
import 'services/api_app_state.dart';
import 'verification_screen.dart';
import 'services/firestore_service.dart';
import 'services/location_service.dart';
import 'services/app_language_service.dart';

class MatrimonialPreferencesScreen extends StatefulWidget {
  final UserProfile profile;
  final bool isEditing;

  const MatrimonialPreferencesScreen({
    super.key,
    required this.profile,
    this.isEditing = false,
  });

  @override
  State<MatrimonialPreferencesScreen> createState() =>
      _MatrimonialPreferencesScreenState();
}

class _MatrimonialPreferencesScreenState
    extends LanguageAwareState<MatrimonialPreferencesScreen> {
  late int _minimumAge;
  late int _maximumAge;
  String? _minimumHeight;
  String? _maximumHeight;
  bool _isSaving = false;

  final _countryController = TextEditingController();
  final _cityController = TextEditingController();

  String? _maritalStatus;
  String? _education;
  String? _religiousPractice;

  String _relocationPreference = 'Willing to relocate';
  bool _citiesLoading = false;
  String? _citiesCountry;
  List<String> _loadedCities = const [];

  Future<String?> _pickLocation(
    String title,
    List<String> values,
    String current,
  ) async {
    final search = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, refresh) {
            final shown = values
                .where(
                  (v) => v.toLowerCase().contains(search.text.toLowerCase()),
                )
                .toList();
            return AlertDialog(
              title: LocalizedText(title),
              content: SizedBox(
                height: 420,
                width: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: AppLanguageService.translate('Search'),
                      ),
                      onChanged: (_) => refresh(() {}),
                    ),
                    Expanded(
                      child: ListView(
                        children: shown
                            .map(
                              (v) => ListTile(
                                title: LocalizedText(v),
                                selected: v == current,
                                onTap: () => Navigator.pop(dialogContext, v),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _countryChoice() async {
    final search = TextEditingController();
    var choices = <String>[
      LocationService.anyCountry,
      'Pakistan',
      'United Arab Emirates',
      'Saudi Arabia',
      'United Kingdom',
      'United States',
      'Canada',
      'Australia',
      'Qatar',
      'Malaysia',
      'Turkey',
    ];
    var loading = true;
    final request = LocationService.countries();
    var requested = false;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          if (!requested) {
            requested = true;
            request.then((loaded) {
              if (dialogContext.mounted) {
                refresh(() {
                  choices = loaded;
                  loading = false;
                });
              }
            });
          }
          final shown = choices
              .where((v) => v.toLowerCase().contains(search.text.toLowerCase()))
              .toList();
          return AlertDialog(
            title: const LocalizedText('Preferred Country'),
            content: SizedBox(
              height: 420,
              width: 420,
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: AppLanguageService.translate(
                        'Search countries',
                      ),
                    ),
                    onChanged: (_) => refresh(() {}),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: LinearProgressIndicator(),
                    ),
                  Expanded(
                    child: ListView(
                      children: shown
                          .map(
                            (v) => ListTile(
                              title: LocalizedText(v),
                              selected: v == _countryController.text,
                              onTap: () => Navigator.pop(dialogContext, v),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickCountry() async {
    final selected = await _countryChoice();
    if (selected == null || !mounted) return;
    final isAnyCountry = selected == LocationService.anyCountry;
    setState(() {
      _countryController.text = selected;
      _cityController.text = LocationService.anyCity;
      // Any city is available immediately, even while the complete world
      // catalogue is loading in the background.
      _loadedCities = [LocationService.anyCity];
      _citiesCountry = selected;
      _citiesLoading = true;
    });
    if (isAnyCountry) {
      unawaited(_loadAllCities());
    } else {
      await _loadCities(selected);
    }
  }

  Future<void> _loadCities(String country) async {
    final values = await LocationService.cities(country);
    if (mounted && _countryController.text == country) {
      setState(() {
        _loadedCities = [
          LocationService.anyCity,
          ...values.where((value) => value != LocationService.anyCity),
        ];
        _citiesLoading = false;
      });
    }
  }

  Future<void> _loadAllCities() async {
    final values = await LocationService.allCities();
    if (mounted && _countryController.text == LocationService.anyCountry) {
      setState(() {
        _loadedCities = [
          LocationService.anyCity,
          ...values.where((value) => value != LocationService.anyCity),
        ];
        _citiesLoading = false;
      });
    }
  }

  Future<void> _pickCity() async {
    final country = _countryController.text.trim().isEmpty
        ? 'Pakistan'
        : _countryController.text.trim();
    final isAnyCountry = country == LocationService.anyCountry;
    if (_citiesCountry != country ||
        (_loadedCities.isEmpty && !_citiesLoading)) {
      setState(() {
        _citiesCountry = country;
        _citiesLoading = true;
        _cityController.text = LocationService.anyCity;
        _loadedCities = [LocationService.anyCity];
      });
      if (isAnyCountry) {
        await _loadAllCities();
      } else {
        await _loadCities(country);
      }
    }
    if (!mounted) return;
    if (_citiesLoading) {
      await (isAnyCountry ? _loadAllCities() : _loadCities(country));
    }
    if (!mounted || _loadedCities.isEmpty) return;
    final selected = await _pickLocation(
      'Preferred City',
      _loadedCities,
      _cityController.text,
    );
    if (selected != null && mounted) {
      setState(() => _cityController.text = selected);
    }
  }

  @override
  void initState() {
    super.initState();

    final preferences = widget.profile.preferences;

    _minimumAge = preferences.minimumAge;
    _maximumAge = preferences.maximumAge;
    _minimumHeight = preferences.minimumHeight;
    _maximumHeight = preferences.maximumHeight;

    _countryController.text = preferences.country?.trim().isNotEmpty == true
        ? preferences.country!
        : 'Pakistan';
    _cityController.text = preferences.city?.trim().isNotEmpty == true
        ? preferences.city!
        : LocationService.anyCity;

    if (_countryController.text == LocationService.anyCountry) {
      _citiesCountry = LocationService.anyCountry;
      _citiesLoading = true;
      _loadedCities = [LocationService.anyCity];
      unawaited(_loadAllCities());
    }

    final savedMarital = preferences.maritalStatus?.trim();
    _maritalStatus = savedMarital == 'Never Married' || savedMarital == 'Single'
        ? 'Single (Never Married)'
        : (savedMarital?.isNotEmpty == true
              ? savedMarital
              : 'Single (Never Married)');
    _education = preferences.education?.trim().isNotEmpty == true
        ? preferences.education
        : 'Intermediate / A-Level';
    _religiousPractice =
        preferences.religiousPractice?.trim().isNotEmpty == true
        ? preferences.religiousPractice
        : 'Any';

    _relocationPreference = preferences.relocationPreference.trim().isNotEmpty
        ? preferences.relocationPreference
        : 'Maybe';
  }

  @override
  void dispose() {
    _countryController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  MatrimonialPreferences _preferencesFromForm() {
    return MatrimonialPreferences(
      minimumAge: _minimumAge,
      maximumAge: _maximumAge,
      minimumHeight: _minimumHeight,
      maximumHeight: _maximumHeight,
      country: _countryController.text.trim().isEmpty
          ? null
          : _countryController.text.trim(),
      city: _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
      maritalStatus: _maritalStatus,
      education: _education,
      religiousPractice: _religiousPractice,
      relocationPreference: _relocationPreference,
    );
  }

  Future<void> _handleBack() async {
    // Keep the latest preference values available when the user returns to
    // this screen. Persisting is best-effort and must not block navigation.
    widget.profile.preferences = _preferencesFromForm();
    unawaited(
      AppState.setUser(widget.profile).catchError((error) {
        debugPrint('Matrimonial preferences back-save failed: $error');
      }),
    );

    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    // On account restoration this screen can be the root route. Recreate the
    // logical previous step instead of leaving the Back button inert.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ProfileDetailsScreen(profile: widget.profile),
      ),
    );
  }

  Future<void> _continue() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final preferences = _preferencesFromForm();

    widget.profile.preferences = preferences;

    try {
      // Save the latest profile information as a draft.
      // This does NOT mark the account as complete.
      await AppState.setUser(widget.profile);
      if (!widget.isEditing && !ApiAppState.isSignedIn) {
        unawaited(
          FirestoreService.setRegistrationStep(
            uid: widget.profile.uid!,
            step: 'preferences',
          ).catchError((error) {
            debugPrint('Preferences step sync deferred: $error');
          }),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );

      return;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }

    if (!mounted) return;

    if (widget.isEditing) {
      Navigator.pop(context, true);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VerificationScreen(
          profile: widget.profile,
          isRegistration: true,
        ),
      ),
    );
  }

  Widget _preferencesSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: colors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LocalizedText(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _ageFields() => Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<int>(
          initialValue: _minimumAge,
          decoration: InputDecoration(
            labelText: AppLanguageService.translate('Minimum'),
            border: const OutlineInputBorder(),
          ),
          items: List.generate(
            43,
            (index) => DropdownMenuItem(
              value: index + 18,
              child: LocalizedAgeText('{age} years', age: index + 18),
            ),
          ),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _minimumAge = value;
              if (_maximumAge < _minimumAge) {
                _maximumAge = _minimumAge;
              }
            });
          },
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: DropdownButtonFormField<int>(
          initialValue: _maximumAge,
          decoration: InputDecoration(
            labelText: AppLanguageService.translate('Maximum'),
            border: const OutlineInputBorder(),
          ),
          items: List.generate(
            43,
            (index) => DropdownMenuItem(
              value: index + 18,
              child: LocalizedAgeText('{age} years', age: index + 18),
            ),
          ),
          onChanged: (value) {
            if (value == null) return;
            if (value < _minimumAge) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: LocalizedText(
                    'Maximum age cannot be below minimum age.',
                  ),
                ),
              );
              return;
            }
            setState(() => _maximumAge = value);
          },
        ),
      ),
    ],
  );

  Widget _heightFields() => Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: _minimumHeight,
          hint: const LocalizedText('Any height'),
          decoration: InputDecoration(
            labelText: AppLanguageService.translate('Minimum'),
            border: const OutlineInputBorder(),
          ),
          items: _heightItems(),
          onChanged: (value) => setState(() => _minimumHeight = value),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: _maximumHeight,
          hint: const LocalizedText('Any height'),
          decoration: InputDecoration(
            labelText: AppLanguageService.translate('Maximum'),
            border: const OutlineInputBorder(),
          ),
          items: _heightItems(),
          onChanged: (value) => setState(() => _maximumHeight = value),
        ),
      ),
    ],
  );

  Widget _locationFields() => Column(
    children: [
      TextFormField(
        controller: _countryController,
        readOnly: true,
        onTap: _pickCountry,
        decoration: InputDecoration(
          labelText: AppLanguageService.translate('Preferred Country'),
          hintText: AppLanguageService.translate('Leave blank for any country'),
          prefixIcon: const Icon(Icons.public),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _cityController,
        readOnly: true,
        onTap: _pickCity,
        decoration: InputDecoration(
          labelText: AppLanguageService.translate('Preferred City'),
          hintText: AppLanguageService.translate('Leave blank for any city'),
          prefixIcon: const Icon(Icons.location_city_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          border: const OutlineInputBorder(),
        ),
      ),
    ],
  );

  Widget _matchingCriteriaFields() => Column(
    children: [
      DropdownButtonFormField<String>(
        initialValue:
            const [
              'Any',
              'Single (Never Married)',
              'Married',
              'Separated',
              'Divorced',
              'Widowed',
            ].contains(_maritalStatus)
            ? _maritalStatus
            : null,
        decoration: InputDecoration(
          labelText: AppLanguageService.translate('Preferred Marital Status'),
          prefixIcon: const Icon(Icons.favorite_border),
          border: const OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: 'Any',
            child: LocalizedText('Any marital status'),
          ),
          DropdownMenuItem(
            value: 'Single (Never Married)',
            child: LocalizedText('Single (Never Married)'),
          ),
          DropdownMenuItem(value: 'Married', child: LocalizedText('Married')),
          DropdownMenuItem(
            value: 'Separated',
            child: LocalizedText('Separated'),
          ),
          DropdownMenuItem(value: 'Divorced', child: LocalizedText('Divorced')),
          DropdownMenuItem(value: 'Widowed', child: LocalizedText('Widowed')),
        ],
        onChanged: (value) => setState(() => _maritalStatus = value),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue:
            ['Any', ...LocationService.educationOptions].contains(_education)
            ? _education
            : null,
        decoration: InputDecoration(
          labelText: AppLanguageService.translate('Minimum Education'),
          prefixIcon: const Icon(Icons.school_outlined),
          border: const OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: 'Any', child: LocalizedText('Any')),
          ...LocationService.educationOptions.map(
            (value) =>
                DropdownMenuItem(value: value, child: LocalizedText(value)),
          ),
        ],
        onChanged: (value) => setState(() => _education = value),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue:
            const [
              'Any',
              'Practicing',
              'Moderately Practicing',
            ].contains(_religiousPractice)
            ? _religiousPractice
            : null,
        decoration: InputDecoration(
          labelText: AppLanguageService.translate(
            'Preferred Religious Practice',
          ),
          prefixIcon: const Icon(Icons.mosque_outlined),
          border: const OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 'Any', child: LocalizedText('Any')),
          DropdownMenuItem(
            value: 'Practicing',
            child: LocalizedText('Practicing'),
          ),
          DropdownMenuItem(
            value: 'Moderately Practicing',
            child: LocalizedText('Moderately Practicing'),
          ),
        ],
        onChanged: (value) => setState(() => _religiousPractice = value),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _relocationPreference,
        decoration: InputDecoration(
          labelText: AppLanguageService.translate('Relocation Preference'),
          prefixIcon: const Icon(Icons.flight_takeoff_outlined),
          border: const OutlineInputBorder(),
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
          DropdownMenuItem(value: 'Maybe', child: LocalizedText('Maybe')),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() => _relocationPreference = value);
        },
      ),
    ],
  );

  Widget _reviewRow(String label, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LocalizedText(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Align(alignment: AlignmentDirectional.centerEnd, child: value),
        ),
      ],
    ),
  );

  Widget _reviewGroup(String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          title,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        ...rows,
      ],
    ),
  );

  Widget _reviewSummary() => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ExpansionTile(
      leading: Icon(
        Icons.fact_check_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const LocalizedText('Review'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        _reviewGroup('Preferred Age', [
          _reviewRow(
            'Minimum',
            LocalizedAgeText('{age} years', age: _minimumAge),
          ),
          _reviewRow(
            'Maximum',
            LocalizedAgeText('{age} years', age: _maximumAge),
          ),
        ]),
        _reviewGroup('Preferred Height', [
          _reviewRow(
            'Minimum',
            _minimumHeight == null
                ? const LocalizedText('Any height')
                : LocalizedHeightText(_minimumHeight!),
          ),
          _reviewRow(
            'Maximum',
            _maximumHeight == null
                ? const LocalizedText('Any height')
                : LocalizedHeightText(_maximumHeight!),
          ),
        ]),
        _reviewGroup('My preferences', [
          _reviewRow(
            'Preferred Country',
            LocalizedText(_countryController.text),
          ),
          _reviewRow('Preferred City', LocalizedText(_cityController.text)),
          _reviewRow(
            'Preferred Marital Status',
            LocalizedText(_maritalStatus ?? 'Any'),
          ),
          _reviewRow('Minimum Education', LocalizedText(_education ?? 'Any')),
          _reviewRow(
            'Preferred Religious Practice',
            LocalizedText(_religiousPractice ?? 'Any'),
          ),
          _reviewRow(
            'Relocation Preference',
            LocalizedText(_relocationPreference),
          ),
        ]),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: LocalizedText('Matrimonial Preferences'),
        centerTitle: true,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: _handleBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: const [LanguageSelectorButton()],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (!widget.isEditing)
                  Row(
                    children: List.generate(
                      4,
                      (index) => Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                LocalizedText(
                  'What are you looking for?',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                LocalizedText(
                  'Set your preferred criteria. You can change these later.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                _preferencesSection(
                  title: 'Preferred Age',
                  icon: Icons.cake_outlined,
                  child: _ageFields(),
                ),
                _preferencesSection(
                  title: 'Preferred Height',
                  icon: Icons.height,
                  child: _heightFields(),
                ),
                _preferencesSection(
                  title: 'My preferences',
                  icon: Icons.tune_rounded,
                  child: Column(
                    children: [
                      _locationFields(),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(height: 1),
                      ),
                      _matchingCriteriaFields(),
                    ],
                  ),
                ),
                _reviewSummary(),
                const SizedBox(height: 4),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _continue,
                    child: LocalizedText(
                      _isSaving
                          ? 'Saving…'
                          : widget.isEditing
                          ? 'Save Preferences'
                          : 'Continue',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> _heightItems() => [
    for (var feet = 4; feet <= 7; feet++)
      for (var inches = 0; inches < 12; inches++)
        DropdownMenuItem(
          value: "$feet'$inches\"",
          child: LocalizedHeightText("$feet'$inches\""),
        ),
  ];
}
