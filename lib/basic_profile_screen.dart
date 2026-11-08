import 'presentation/nisa_premium/nisa_premium.dart';

import 'dart:async';

import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';

import 'models/user_profile.dart';
import 'account_type_screen.dart';
import 'profile_details_screen.dart';
import 'services/location_service.dart';
import 'services/app_language_service.dart';
import 'services/app_state.dart';
import 'services/api_app_state.dart';

class BasicProfileScreen extends StatefulWidget {
  final String uid;
  final String email;
  final String phone;
  final String accountType;
  final String? initialName;
  final String? initialProfilePhoto;
  final UserProfile? existingProfile;

  const BasicProfileScreen({
    super.key,
    required this.uid,
    required this.email,
    required this.phone,
    required this.accountType,
    this.initialName,
    this.initialProfilePhoto,
    this.existingProfile,
  });

  @override
  State<BasicProfileScreen> createState() => _BasicProfileScreenState();
}

class _BasicProfileScreenState extends LanguageAwareState<BasicProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _cityController = TextEditingController(text: 'Karachi');
  final _countryController = TextEditingController(text: 'Pakistan');
  String? _education;
  String _religion = 'Islam';
  bool _sectsLoading = false;
  List<String> _cities = const [];
  bool _citiesLoading = false;

  String? _gender;
  String? _maritalStatus;
  DateTime? _dateOfBirth;
  bool _dateOfBirthError = false;
  final _dateOfBirthKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final existing = widget.existingProfile;
    _nameController.text = existing?.name.trim().isNotEmpty == true
        ? existing!.name
        : (widget.initialName?.trim() ?? '');

    if (existing != null) {
      _cityController.text = existing.city;
      _countryController.text = existing.country?.trim().isNotEmpty == true
          ? existing.country!
          : 'Pakistan';
      _education = existing.education;
      _religion = existing.religion?.trim().isNotEmpty == true
          ? existing.religion!
          : 'Islam';
      _gender = existing.gender;
      _maritalStatus = existing.maritalStatus;
      // The shared model uses 1900 as a null-date fallback. Treat it as an
      // empty field so API accounts without a DOB must enter a real one.
      _dateOfBirth = existing.dateOfBirth.year > 1900
          ? existing.dateOfBirth
          : null;
    }
    unawaited(LocationService.castes(_countryController.text));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> get _maritalOptions => [
    const DropdownMenuItem(
      value: 'Single (Never Married)',
      child: LocalizedText('Single (Never Married)'),
    ),
    if (_gender != 'Female')
      const DropdownMenuItem(value: 'Married', child: LocalizedText('Married')),
    const DropdownMenuItem(
      value: 'Separated',
      child: LocalizedText('Separated'),
    ),
    const DropdownMenuItem(value: 'Divorced', child: LocalizedText('Divorced')),
    const DropdownMenuItem(value: 'Widowed', child: LocalizedText('Widowed')),
  ];

  Future<String?> _pick(
    String title,
    List<String> values,
    String current,
  ) async {
    final search = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          final shown = values
              .where((v) => v.toLowerCase().contains(search.text.toLowerCase()))
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
      ),
    );
  }

  Future<String?> _countryChoice() async {
    final search = TextEditingController();
    var choices = <String>[
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
            title: const LocalizedText('Country'),
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

  Future<void> _chooseCountry() async {
    final value = await _countryChoice();
    if (value == null || !mounted) return;
    setState(() {
      _countryController.text = value;
      _cityController.clear();
      _cities = const [];
      _citiesLoading = true;
    });
    // Preload the caste list while the user is still on Basic Profile.
    unawaited(LocationService.castes(value));
    final cities = await LocationService.cities(value);
    if (mounted) {
      setState(() {
        _cities = cities;
        _citiesLoading = false;
      });
    }
  }

  Future<void> _chooseCity() async {
    if (_cities.isEmpty && !_citiesLoading) {
      setState(() => _citiesLoading = true);
      _cities = await LocationService.cities(_countryController.text);
      if (mounted) setState(() => _citiesLoading = false);
    }
    if (!mounted || _citiesLoading || _cities.isEmpty) return;
    final value = await _pick('City', _cities, _cityController.text);
    if (value != null && mounted) setState(() => _cityController.text = value);
  }

  Future<void> _chooseReligion() async {
    final value = await _pick(
      'Religion',
      LocationService.topReligions,
      _religion,
    );
    if (value == null || !mounted) return;
    setState(() {
      _religion = value;
      _sectsLoading = true;
    });
    unawaited(_loadSects(value));
  }

  Future<void> _loadSects(String religion) async {
    await LocationService.sects(religion);
    if (!mounted || _religion != religion) return;
    setState(() => _sectsLoading = false);
  }

  Future<void> _selectDateOfBirth() async {
    final now = DateTime.now();

    final initialDate = DateTime(now.year - 25, now.month, now.day);

    final lastDate = DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1940),
      lastDate: lastDate,
    );

    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dateOfBirthError = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  UserProfile? _profileFromForm() {
    if (_gender == null ||
        _dateOfBirth == null ||
        _maritalStatus == null ||
        _cityController.text.trim().isEmpty ||
        _education == null ||
        _education!.trim().isEmpty) {
      return null;
    }

    final existing = widget.existingProfile;
    if (existing != null) {
      existing
        ..name = _nameController.text.trim()
        ..gender = _gender!
        ..dateOfBirth = _dateOfBirth!
        ..city = _cityController.text.trim()
        ..country = _countryController.text.trim()
        ..education = _education
        ..religion = _religion
        ..caste = existing.caste
        ..maritalStatus = _maritalStatus!
        ..email = existing.email ?? widget.email
        ..phone = existing.phone ?? widget.phone;
      return existing;
    }

    return UserProfile(
      uid: widget.uid,
      accountType: widget.accountType,
      name: _nameController.text.trim(),
      gender: _gender!,
      dateOfBirth: _dateOfBirth!,
      city: _cityController.text.trim(),
      country: _countryController.text.trim(),
      education: _education,
      religion: _religion,
      maritalStatus: _maritalStatus!,
      email: widget.email,
      phone: widget.phone,
      profilePhoto: widget.initialProfilePhoto,
    );
  }

  Future<void> _handleBack() async {
    // Preserve a completed Basic Profile draft before returning. This is
    // deliberately non-blocking so Back remains immediate even offline.
    final draft = _profileFromForm();
    Future<void>? draftSave;
    if (draft != null) {
      draftSave = AppState.setUser(draft).catchError((error) {
        debugPrint('Basic profile back-save failed: $error');
      });
      unawaited(draftSave);
    }

    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    // API-restored incomplete accounts are rendered directly at the AuthGate
    // root. Returning to the Firebase-only account-type flow would fail in
    // PostgreSQL preview, so sign out to the API welcome route instead.
    if (ApiAppState.isSignedIn) {
      if (draftSave != null) await draftSave;
      try {
        await AppState.clearUser();
      } catch (error) {
        // The API session notifier is cleared even when the logout request
        // fails, so AuthGate can still return to the API welcome screen.
        debugPrint('API sign-out while leaving onboarding failed: $error');
      }
      return;
    }

    // AuthGate may display Basic Profile as the root route after Google
    // sign-in or account restoration. In that case there is no route to pop,
    // so return to the logical previous registration screen explicitly.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AccountTypeScreen(
          existingUid: widget.uid,
          existingEmail: widget.email,
          existingAccountType: widget.accountType,
        ),
      ),
    );
  }

  void _goToProfileDetails() {
    if (_dateOfBirth == null) {
      setState(() => _dateOfBirthError = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: LocalizedText('Please select your date of birth.'),
          ),
        );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext = _dateOfBirthKey.currentContext;
        if (targetContext != null && targetContext.mounted) {
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 250),
            alignment: 0.25,
          );
        }
      });
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_gender == null ||
        _maritalStatus == null ||
        _cityController.text.trim().isEmpty ||
        _education == null ||
        _education!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Please complete all required fields.'),
        ),
      );
      return;
    }

    final profile = _profileFromForm();
    if (profile == null) return;

    // Save the draft without blocking the transition. Profile Details saves
    // the complete profile again before advancing to preferences, so a
    // temporary network failure here must not trap the user on this screen.
    unawaited(
      AppState.setUser(profile).catchError((error) {
        debugPrint('Basic profile draft save failed: $error');
      }),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileDetailsScreen(profile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: LocalizedText('Basic Profile'),
        centerTitle: true,
        leading: IconButton(
          tooltip: AppLanguageService.translate('Back'),
          onPressed: _handleBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        actions: const [LanguageSelectorButton()],
      ),
      body: NisaPageBody(
        form: true,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                LocalizedText(
                  'Tell us about yourself',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 8),

                LocalizedText(
                  'This information will help us create your matrimonial profile.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),

                const SizedBox(height: 28),

                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.translate('Full Name'),
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 18),

                InkWell(
                  onTap: _chooseReligion,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLanguageService.translate('Religion'),
                      prefixIcon: const Icon(Icons.public_outlined),
                      suffixIcon: _sectsLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.arrow_drop_down),
                      border: const OutlineInputBorder(),
                    ),
                    child: LocalizedText(_religion),
                  ),
                ),

                const SizedBox(height: 18),

                DropdownButtonFormField<String>(
                  isExpanded: true,
                  itemHeight: null,
                  isDense: false,
                  initialValue: const ['Male', 'Female'].contains(_gender)
                      ? _gender
                      : null,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.translate('Gender'),
                    prefixIcon: Icon(Icons.wc_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Male',
                      child: LocalizedText('Male'),
                    ),
                    DropdownMenuItem(
                      value: 'Female',
                      child: LocalizedText('Female'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _gender = value;
                      if (value == 'Female' && _maritalStatus == 'Married') {
                        _maritalStatus = null;
                      }
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select your gender';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 18),

                InkWell(
                  key: _dateOfBirthKey,
                  onTap: _selectDateOfBirth,
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLanguageService.translate('Date of Birth'),
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(),
                      errorText: _dateOfBirthError
                          ? AppLanguageService.translate(
                              'Date of birth is required',
                            )
                          : null,
                    ),
                    child: LocalizedText(
                      _dateOfBirth == null
                          ? 'Select your date of birth'
                          : _formatDate(_dateOfBirth!),
                      style: TextStyle(
                        color: _dateOfBirth == null
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                InkWell(
                  onTap: _chooseCountry,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLanguageService.translate('Country'),
                      prefixIcon: Icon(Icons.public),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                      border: OutlineInputBorder(),
                    ),
                    child: LocalizedText(_countryController.text),
                  ),
                ),

                const SizedBox(height: 18),

                InkWell(
                  onTap: _chooseCity,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLanguageService.translate('City'),
                      prefixIcon: Icon(Icons.location_city_outlined),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                      border: OutlineInputBorder(),
                    ),
                    child: LocalizedText(
                      _citiesLoading
                          ? 'Loading cities...'
                          : (_cityController.text.isEmpty
                                ? 'Select city'
                                : _cityController.text),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                DropdownButtonFormField<String>(
                  isExpanded: true,
                  itemHeight: null,
                  isDense: false,
                  initialValue:
                      LocationService.educationOptions.contains(_education)
                      ? _education
                      : null,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.translate('Education'),
                    prefixIcon: const Icon(Icons.school_outlined),
                    border: const OutlineInputBorder(),
                  ),
                  items: LocationService.educationOptions
                      .map(
                        (v) =>
                            DropdownMenuItem(value: v, child: LocalizedText(v)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _education = value),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? AppLanguageService.translate(
                          'Please complete all required fields.',
                        )
                      : null,
                ),

                /* Legacy city field retained only for form compatibility. */
                Offstage(
                  offstage: true,
                  child: TextField(controller: _cityController),
                ),
                /*
              TextFormField(
                controller: _cityController,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('City'),
                  prefixIcon: Icon(Icons.location_city_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your city';
                  }
                  return null;
                },
              ), */

                const SizedBox(height: 18),

                DropdownButtonFormField<String>(
                  isExpanded: true,
                  itemHeight: null,
                  isDense: false,
                  initialValue:
                      _maritalOptions.any(
                        (item) => item.value == _maritalStatus,
                      )
                      ? _maritalStatus
                      : null,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.translate('Marital Status'),
                    prefixIcon: Icon(Icons.favorite_border),
                    border: OutlineInputBorder(),
                  ),
                  items: _maritalOptions,
                  onChanged: (value) {
                    setState(() {
                      _maritalStatus = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select your marital status';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _goToProfileDetails,
                    child: const LocalizedText(
                      'Continue',
                      style: TextStyle(
                        fontSize: 17,
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
}
