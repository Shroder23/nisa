import 'dart:io';

import 'services/app_language_service.dart';
import 'widgets/localized_text.dart';
import 'widgets/language_selector_button.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'models/user_profile.dart';
import 'services/app_state.dart';
import 'services/api_app_state.dart';
import 'services/api_profile_service.dart';
import 'services/age_eligibility_service.dart';
import 'age_restricted_screen.dart';
import 'services/location_service.dart';
import 'widgets/profile_photo.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends LanguageAwareState<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _countryController;
  late final TextEditingController _educationController;
  late final TextEditingController _professionController;
  late final TextEditingController _aboutController;
  late final TextEditingController _languageController;

  String? _height;
  String? _relocation;
  late DateTime _dateOfBirth;
  bool _isSaving = false;
  bool _citiesLoading = false;
  bool _uploadingProfilePhoto = false;
  String? _profilePhotoUrl;
  final ImagePicker _imagePicker = ImagePicker();
  String? _citiesCountry;
  List<String> _loadedCities = const [];
  String? _normalizeHeight(String? value) {
    if (value == null) {
      return null;
    }

    return LocationService.heightOptions.contains(value) ? value : null;
  }

  List<String> _languageOptions = List<String>.from(
    LocationService.offlineLanguages,
  );

  Future<String?> _searchChoice(
    String title,
    List<String> choices,
    String? current,
  ) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var filtered = List<String>.from(choices);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: LocalizedText(title),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: AppLanguageService.translate('Search'),
                    ),
                    onChanged: (query) => setDialogState(() {
                      filtered = choices
                          .where(
                            (v) =>
                                v.toLowerCase().contains(query.toLowerCase()),
                          )
                          .toList();
                    }),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: filtered
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
          ),
        );
      },
    );
  }

  Future<String?> _countryChoice() async {
    final controller = TextEditingController();
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
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!requested) {
              requested = true;
              request.then((loaded) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    choices = loaded;
                    loading = false;
                  });
                }
              });
            }
            final query = controller.text.toLowerCase();
            final filtered = choices
                .where((v) => v.toLowerCase().contains(query))
                .toList();
            return AlertDialog(
              title: const LocalizedText('Country'),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: AppLanguageService.translate(
                          'Search countries',
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: LinearProgressIndicator(),
                      ),
                    Expanded(
                      child: ListView(
                        children: filtered
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
        );
      },
    );
  }

  Future<void> _chooseCountry() async {
    final value = await _countryChoice();
    if (value == null || !mounted) {
      return;
    }
    setState(() {
      _countryController.text = value;
      _cityController.text = value.trim().toLowerCase() == 'pakistan'
          ? 'Karachi'
          : '';
      _loadedCities = const [];
      _citiesCountry = value;
      _citiesLoading = true;
    });
    await _loadCities(value);
  }

  Future<void> _loadCities(String country) async {
    try {
      final cities = await LocationService.cities(country);
      if (!mounted || _countryController.text != country) {
        return;
      }
      setState(() {
        _loadedCities = cities;
        _citiesLoading = false;
      });
    } catch (_) {
      if (mounted && _countryController.text == country) {
        setState(() => _citiesLoading = false);
      }
    }
  }

  Future<void> _chooseCity() async {
    final country = _countryController.text.trim().isEmpty
        ? 'Pakistan'
        : _countryController.text.trim();
    if (_citiesCountry != country ||
        (_loadedCities.isEmpty && !_citiesLoading)) {
      setState(() {
        _citiesCountry = country;
        _citiesLoading = true;
        _cityController.clear();
      });
      await _loadCities(country);
    }
    if (!mounted) {
      return;
    }
    if (_citiesLoading) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('Loading cities…')));
      return;
    }
    var cities = List<String>.from(_loadedCities);
    if (_cityController.text.isNotEmpty &&
        !cities.contains(_cityController.text)) {
      cities = [...cities, _cityController.text];
    }
    if (cities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('No cities were returned for this country.'),
        ),
      );
      return;
    }
    final value = await _searchChoice('City', cities, _cityController.text);
    if (value != null && mounted) {
      setState(() => _cityController.text = value);
    }
  }

  String? _normalizeRelocation(String? value) {
    final text = value?.trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    if (text == 'Yes') {
      return 'Willing to relocate';
    }

    if (text == 'No') {
      return 'Not willing to relocate';
    }

    return text;
  }

  @override
  void initState() {
    super.initState();

    final profile = widget.profile;

    _nameController = TextEditingController(text: profile.name);
    _cityController = TextEditingController(
      text: profile.city.trim().isEmpty ? 'Karachi' : profile.city,
    );
    _countryController = TextEditingController(
      text: profile.country?.trim().isNotEmpty == true
          ? profile.country
          : 'Pakistan',
    );
    _educationController = TextEditingController(text: profile.education ?? '');
    _professionController = TextEditingController(
      text: profile.profession ?? '',
    );
    _aboutController = TextEditingController(text: profile.aboutMe ?? '');
    _languageController = TextEditingController(
      text: profile.language?.trim().isNotEmpty == true
          ? profile.language
          : 'Urdu',
    );
    LocationService.languages().then((values) {
      if (mounted) {
        setState(() => _languageOptions = values);
      }
    });

    _height = profile.height;
    _relocation = _normalizeRelocation(widget.profile.relocation);
    _dateOfBirth = profile.dateOfBirth;
    _profilePhotoUrl = profile.profilePhoto;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _educationController.dispose();
    _professionController.dispose();
    _aboutController.dispose();
    _languageController.dispose();

    super.dispose();
  }

  int _ageFrom(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;

    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }

    return age;
  }

  String _formatDate(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();

    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth,
      firstDate: DateTime(1920, 1, 1),
      lastDate: now,
      helpText: 'Select date of birth',
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _dateOfBirth = selected;
    });
  }

  Future<void> _chooseAndUploadProfilePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const LocalizedText('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const LocalizedText('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) {
      return;
    }

    final selected = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (selected == null || !mounted) {
      return;
    }

    setState(() => _uploadingProfilePhoto = true);
    try {
      final photoUrl = await ApiProfileService.uploadMyProfilePhoto(
        File(selected.path),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profilePhotoUrl = photoUrl;
        widget.profile.profilePhoto = photoUrl;
        ApiAppState.currentProfile.value = widget.profile;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('Profile photo uploaded.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('Something went wrong. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingProfilePhoto = false);
      }
    }
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }

    final profile = widget.profile;
    final oldDateOfBirth = profile.dateOfBirth;
    final dobChanged =
        oldDateOfBirth.year != _dateOfBirth.year ||
        oldDateOfBirth.month != _dateOfBirth.month ||
        oldDateOfBirth.day != _dateOfBirth.day;

    setState(() {
      _isSaving = true;
    });

    try {
      if (dobChanged) {
        if (ApiAppState.isSignedIn) {
          throw StateError(
            'Date of birth changes are not enabled in the PostgreSQL preview.',
          );
        }
        final result = await AgeEligibilityService.updateDateOfBirth(
          _dateOfBirth,
        );

        profile.dateOfBirth = _dateOfBirth;

        if (result.isBlocked) {
          if (!mounted) {
            return;
          }

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AgeRestrictedScreen()),
            (route) => false,
          );

          return;
        }

        if (!result.isEligible) {
          throw StateError('The updated date of birth could not be confirmed.');
        }
      }

      profile.name = _nameController.text.trim();
      profile.city = _cityController.text.trim();
      profile.country = _countryController.text.trim().isEmpty
          ? null
          : _countryController.text.trim();

      profile.education = _educationController.text.trim().isEmpty
          ? null
          : _educationController.text.trim();

      profile.profession = _professionController.text.trim().isEmpty
          ? null
          : _professionController.text.trim();

      profile.aboutMe = _aboutController.text.trim().isEmpty
          ? null
          : _aboutController.text.trim();

      profile.language = _languageController.text.trim().isEmpty
          ? null
          : _languageController.text.trim();

      profile.height = _normalizeHeight(_height) ?? _height;
      profile.relocation = _relocation;

      await AppState.setUser(profile);

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Edit Profile'),
        centerTitle: true,
        actions: const [LanguageSelectorButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (ApiAppState.isSignedIn) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      ProfilePhoto(
                        imageUrl: _profilePhotoUrl,
                        radius: 34,
                        fallbackText: _nameController.text,
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: LocalizedText(
                          'Add a profile photo before submitting parent verification.',
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _isSaving || _uploadingProfilePhoto
                            ? null
                            : _chooseAndUploadProfilePhoto,
                        icon: _uploadingProfilePhoto
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_a_photo_outlined),
                        label: Text(
                          _profilePhotoUrl == null ? 'Add' : 'Change',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Full Name'),
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 18),

            InkWell(
              onTap: _isSaving || ApiAppState.isSignedIn
                  ? null
                  : _pickDateOfBirth,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate(
                    'Age / Date of Birth',
                  ),
                  helperText: ApiAppState.isSignedIn
                      ? 'Date of birth cannot be changed in this preview.'
                      : null,
                  prefixIcon: Icon(Icons.cake_outlined),
                  suffixIcon: Icon(Icons.calendar_month_outlined),
                  border: OutlineInputBorder(),
                ),
                child: LocalizedRichText(
                  spanBuilder: () => TextSpan(
                    children: [
                      TextSpan(
                        text: AppLanguageService.translateAge(
                          '{age} years',
                          age: _ageFrom(_dateOfBirth),
                        ),
                      ),
                      const TextSpan(text: ' ('),
                      TextSpan(text: _formatDate(_dateOfBirth)),
                      const TextSpan(text: ')'),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            InkWell(
              onTap: _isSaving ? null : _chooseCountry,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('Country'),
                  prefixIcon: Icon(Icons.public),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                  border: OutlineInputBorder(),
                ),
                child: LocalizedText(
                  _countryController.text.isEmpty
                      ? 'Pakistan'
                      : _countryController.text,
                ),
              ),
            ),

            const SizedBox(height: 18),

            InkWell(
              onTap: _isSaving ? null : _chooseCity,
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

            /* Controllers are retained so the existing save path and legacy
               profiles continue to work. */
            Offstage(
              offstage: true,
              child: Column(
                children: [
                  TextField(controller: _cityController),
                  TextField(controller: _countryController),
                ],
              ),
            ),

            /*
            TextFormField(
              controller: _cityController,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('City'),
                prefixIcon: Icon(Icons.location_city_outlined),
                border: OutlineInputBorder(),
              ),
            ), */
            const SizedBox(height: 18),

            /* TextFormField(
              controller: _countryController,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Country'),
                prefixIcon: Icon(Icons.public),
                border: OutlineInputBorder(),
              ),
            ), */
            const SizedBox(height: 18),

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
                    (v) => DropdownMenuItem(
                      value: v,
                      child: LocalizedHeightText(v),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _height = value;
                });
              },
            ),

            const SizedBox(height: 18),

            DropdownButtonFormField<String>(
              initialValue:
                  LocationService.educationOptions.contains(
                    _educationController.text,
                  )
                  ? _educationController.text
                  : null,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Education'),
                prefixIcon: Icon(Icons.school_outlined),
                border: OutlineInputBorder(),
              ),
              items: LocationService.educationOptions
                  .map(
                    (v) => DropdownMenuItem(value: v, child: LocalizedText(v)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _educationController.text = value ?? ''),
            ),

            const SizedBox(height: 18),

            TextFormField(
              controller: _professionController,
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Profession'),
                prefixIcon: Icon(Icons.work_outline),
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 18),

            TextFormField(
              controller: _languageController,
              readOnly: true,
              onTap: () async {
                final value = await _searchChoice(
                  'Language',
                  _languageOptions,
                  _languageController.text,
                );
                if (value != null) {
                  setState(() => _languageController.text = value);
                }
              },
              decoration: InputDecoration(
                labelText: AppLanguageService.translate('Language'),
                prefixIcon: Icon(Icons.language),
                border: OutlineInputBorder(),
              ),
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
                labelText: AppLanguageService.translate('Relocation'),
                prefixIcon: Icon(Icons.flight_takeoff),
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
                DropdownMenuItem(value: 'Maybe', child: LocalizedText('Maybe')),
              ],
              onChanged: (value) {
                setState(() {
                  _relocation = value;
                });
              },
            ),

            const SizedBox(height: 18),

            if (!ApiAppState.isSignedIn)
              TextFormField(
                controller: _aboutController,
                maxLines: 5,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: AppLanguageService.translate('About Me'),
                  hintText: AppLanguageService.translate(
                    'Tell potential matches about yourself...',
                  ),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),

            const SizedBox(height: 16),

            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: LocalizedText(
                  _isSaving ? 'Saving...' : 'Save Changes',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
