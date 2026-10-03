import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/server_config.dart';

class LocationService {
  static const anyCountry = 'Any country';
  static const anyCity = 'Any city';
  static const topReligions = <String>[
    'Islam',
    'Christianity',
    'Hinduism',
    'Buddhism',
    'Sikhism',
    'Judaism',
    'Jainism',
    "Bahá'í Faith",
    'Other',
  ];
  static final Map<String, List<String>> _sectCache = {};
  static final Map<String, List<String>> _casteCache = {};
  static const educationOptions = <String>[
    // Ordered from the highest qualification to the lowest. Intermediate,
    // A-Level, and Associate Diploma/DAE share the same matching level.
    'PhD / Doctorate', 'MPhil / Postgraduate', "Master's", "Bachelor's",
    'Intermediate / A-Level', 'Diploma / DAE', 'Secondary School',
    'Primary School', 'Other',
  ];
  static const offlineLanguages = <String>[
    'Urdu',
    'Punjabi',
    'Sindhi',
    'Pashto',
    'Balochi',
    'English',
    'Arabic',
    'Hindi',
    'Bengali',
    'Persian',
    'Turkish',
    'Chinese',
    'French',
    'German',
    'Spanish',
    'Russian',
    'Malay',
    'Tamil',
    'Telugu',
    'Gujarati',
    'Other',
  ];
  static final heightOptions = [
    for (var feet = 4; feet <= 7; feet++)
      for (var inches = 0; inches <= 11; inches++) "$feet'$inches\"",
  ];
  static const pakistanCities = <String>[
    'Karachi',
    'Lahore',
    'Islamabad',
    'Rawalpindi',
    'Peshawar',
    'Quetta',
    'Multan',
    'Faisalabad',
    'Hyderabad',
    'Sukkur',
    'Gujranwala',
    'Sialkot',
    'Bahawalpur',
    'Abbottabad',
    'Mardan',
    'Gwadar',
    'Sargodha',
    'Abbottabad',
    'Attock',
    'Badin',
    'Bannu',
    'Charsadda',
    'Chiniot',
    'Dadu',
    'Dera Ghazi Khan',
    'Dera Ismail Khan',
    'Ghotki',
    'Gilgit',
    'Gujrat',
    'Haripur',
    'Jhang',
    'Jhelum',
    'Kasur',
    'Khairpur',
    'Khanewal',
    'Khuzdar',
    'Kohat',
    'Larkana',
    'Layyah',
    'Lodhran',
    'Matiari',
    'Mianwali',
    'Mirpur',
    'Mirpur Khas',
    'Muzaffarabad',
    'Nawabshah',
    'Nowshera',
    'Okara',
    'Rahim Yar Khan',
    'Sahiwal',
    'Sheikhupura',
    'Shikarpur',
    'Skardu',
    'Swabi',
    'Swat',
    'Thatta',
    'Turbat',
    'Vehari',
    'Wah Cantt',
    'Wazirabad',
    'Zhob',
  ];
  // Offline Pakistani fallback. The Other option covers names not listed.
  static const pakistanCastes = <String>[
    'Any caste',
    'Other / Not listed',
    'Arain',
    'Awan',
    'Baloch',
    'Bhatti',
    'Brahui',
    'Chaudhary',
    'Cheema',
    'Chughtai',
    'Dar',
    'Dhobi',
    'Dogar',
    'Gakhar',
    'Gujjar',
    'Hashmi',
    'Jadoon',
    'Janjua',
    'Jat',
    'Jatoi',
    'Kakakhel',
    'Kamboh',
    'Kashmiri',
    'Khattak',
    'Khokhar',
    'Kiyani',
    'Khan',
    'Laghari',
    'Lodhi',
    'Mahar',
    'Mahesar',
    'Mahajir',
    'Makhdoom',
    'Malik',
    'Mallah',
    'Mansoori',
    'Marri',
    'Mehar',
    'Memon',
    'Mirani',
    'Mughal',
    'Niazi',
    'Noon',
    'Panhwar',
    'Paracha',
    'Pathan',
    'Qureshi',
    'Rajput',
    'Rind',
    'Sayed',
    'Sayyid',
    'Shaikh',
    'Sheikh',
    'Shah',
    'Shahwani',
    'Sial',
    'Soomro',
    'Sudhan',
    'Sultan',
    'Syed',
    'Tareen',
    'Tarkhan',
    'Tiwana',
    'Turi',
    'Wains',
    'Waraich',
    'Wattoo',
    'Yousafzai',
    'Zahid',
    'Zargar',
    'Abbasi',
    'Afridi',
    'Alizai',
    'Achakzai',
    'Bangash',
    'Bunerwal',
    'Durrani',
    'Kakar',
    'Kasi',
    'Khanzada',
    'Khilji',
    'Mohmand',
    'Orakzai',
    'Safi',
    'Shinwari',
    'Khatri',
    'Lohana',
    'Bania',
    'Bajwa',
    'Bains',
    'Bedi',
    'Bhandari',
    'Chopra',
    'Gill',
    'Grewal',
    'Khurana',
    'Mangat',
    'Sandhu',
    'Sangha',
    'Sidhu',
    'Sodhi',
    'Sethi',
    'Talwar',
    'Virk',
    'Other',
  ];
  static const offlineCountries = <String>[
    'Pakistan',
    'India',
    'Bangladesh',
    'United Arab Emirates',
    'Saudi Arabia',
    'Qatar',
    'Oman',
    'Kuwait',
    'Bahrain',
    'United Kingdom',
    'United States',
    'Canada',
    'Australia',
    'New Zealand',
    'China',
    'Japan',
    'Malaysia',
    'Turkey',
    'Germany',
    'France',
    'Italy',
    'Spain',
    'Russia',
    'South Africa',
  ];
  static Future<http.Response?> _getFromConfiguredServers(
    String path, {
    Map<String, String>? queryParameters,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final bases = <String>{
      ServerConfig.postgresApiBaseUrl,
      ServerConfig.baseUrl,
    };
    for (final base in bases) {
      try {
        final uri = Uri.parse('$base$path')
            .replace(queryParameters: queryParameters);
        final response = await http.get(uri).timeout(timeout);
        if (response.statusCode == 200) return response;
      } catch (_) {
        // Try the next configured host, then use the public catalogue fallback.
      }
    }
    return null;
  }

  static Future<List<String>> countries() async {
    try {
      final response = await _getFromConfiguredServers(
        '/api/locations/countries',
      );
      if (response?.statusCode == 200) {
        final values = List<String>.from(
          jsonDecode(response!.body)['countries'] as List,
        );
        values.removeWhere((v) => v.trim().toLowerCase() == 'pakistan');
        values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return [anyCountry, 'Pakistan', ...values];
      }
    } catch (_) {}
    // If the local server is stale or unavailable, still load the complete
    // country catalogue directly from the current upstream API.
    try {
      final response = await http
          .get(Uri.parse('https://countriesnow.space/api/v0.1/countries'))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = decoded['data'];
        if (raw is List) {
          final values =
              raw
                  .map(
                    (item) => item is Map
                        ? item['country']?.toString() ?? ''
                        : item.toString(),
                  )
                  .where(
                    (v) =>
                        v.trim().isNotEmpty &&
                        v.trim().toLowerCase() != 'pakistan',
                  )
                  .toSet()
                  .toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return [anyCountry, 'Pakistan', ...values];
        }
      }
    } catch (_) {}
    return [anyCountry, ...offlineCountries];
  }

  static Future<List<String>> cities(String country) async {
    if (country.trim().toLowerCase() == anyCountry.toLowerCase()) {
      return const [];
    }
    if (country.trim().toLowerCase() == 'pakistan') {
      return List<String>.from(pakistanCities);
    }
    try {
      final response = await _getFromConfiguredServers(
        '/api/locations/cities',
        queryParameters: {'country': country},
      );
      if (response?.statusCode == 200) {
        final decoded = jsonDecode(response!.body) as Map<String, dynamic>;
        final raw = decoded['cities'] ?? decoded['data'];
        if (raw is List) {
          return raw
              .map((v) => v.toString())
              .where((v) => v.trim().isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    // Compatibility fallback for servers running the old location route.
    try {
      final upstream = Uri.parse(
        'https://countriesnow.space/api/v0.1/countries/cities/q',
      ).replace(queryParameters: {'country': country});
      final response = await http
          .get(upstream)
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = decoded['data'];
        if (raw is List) {
          return raw
              .map((v) => v.toString())
              .where((v) => v.trim().isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  static Future<List<String>> allCities() async {
    try {
      final response = await _getFromConfiguredServers(
        '/api/locations/all-cities',
        timeout: const Duration(seconds: 20),
      );
      if (response?.statusCode == 200) {
        final decoded = jsonDecode(response!.body) as Map<String, dynamic>;
        final raw = decoded['cities'] ?? decoded['data'];
        if (raw is List) {
          return raw
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        }
      }
    } catch (_) {}

    // Compatibility fallback for a client pointed at an older server.
    try {
      final response = await http
          .get(Uri.parse('https://countriesnow.space/api/v0.1/countries'))
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = decoded['data'];
        if (raw is List) {
          final cities = <String>{};
          for (final item in raw) {
            if (item is Map && item['cities'] is List) {
              cities.addAll(
                (item['cities'] as List)
                    .map((value) => value.toString().trim())
                    .where((value) => value.isNotEmpty),
              );
            }
          }
          return cities.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        }
      }
    } catch (_) {}
    return const [];
  }

  static Future<List<String>> languages() async {
    try {
      final response = await http.get(
        Uri.parse('${ServerConfig.baseUrl}/api/locations/languages'),
      );
      if (response.statusCode == 200) {
        final raw = jsonDecode(response.body)['languages'];
        if (raw is List) {
          final values =
              raw
                  .map((v) => v.toString())
                  .where(
                    (v) => v.trim().isNotEmpty && v.toLowerCase() != 'urdu',
                  )
                  .toSet()
                  .toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return ['Urdu', ...values];
        }
      }
    } catch (_) {}
    return List<String>.from(offlineLanguages);
  }

  static Future<List<String>> sects(String religion) async {
    final key = religion.trim().toLowerCase();
    final cached = _sectCache[key];
    if (cached != null) return List<String>.from(cached);

    const catalog = <String, List<String>>{
      'islam': ['Sunni', 'Shia', 'Ibadi', 'Ahmadiyya', 'Other'],
      'christianity': [
        'Catholic',
        'Orthodox',
        'Protestant',
        'Anglican',
        'Other',
      ],
      'hinduism': ['Vaishnavism', 'Shaivism', 'Shaktism', 'Smartism', 'Other'],
      'buddhism': ['Theravada', 'Mahayana', 'Vajrayana', 'Other'],
      'sikhism': ['Khalsa', 'Namdhari', 'Nirankari', 'Other'],
      'judaism': ['Orthodox', 'Conservative', 'Reform', 'Other'],
      'jainism': ['Digambara', 'Svetambara', 'Other'],
      "bahá'í faith": ["Bahá'í Faith"],
      'other': ['Other'],
    };

    // Keep the catalogue cached so a religion change on Basic Profile starts
    // the load before Profile Details is opened.
    await Future<void>.delayed(Duration.zero);
    final values = List<String>.from(catalog[key] ?? const ['Other']);
    _sectCache[key] = values;
    return List<String>.from(values);
  }

  static Future<List<String>> castes(String country) async {
    final normalized = country.trim().toLowerCase();
    if (normalized == 'pakistan') {
      final values = List<String>.from(pakistanCastes);
      _casteCache[normalized] = values;
      return values;
    }

    final cached = _casteCache[normalized];
    if (cached != null) return List<String>.from(cached);

    try {
      final uri = Uri.parse('${ServerConfig.baseUrl}/api/locations/castes')
          .replace(queryParameters: {'country': country.trim()});
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final raw = decoded['castes'];
        if (raw is List) {
          final values = raw
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList();
          if (values.isNotEmpty) {
            _casteCache[normalized] = values;
            return List<String>.from(values);
          }
        }
      }
    } catch (_) {}

    return const ['Any caste', 'Other / Not listed'];
  }

  static String normalizeEducationCategory(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) return 'Other';
    if (text.contains('primary')) return 'Primary School';
    if (text.contains('phd') ||
        text.contains('ph.d') ||
        text.contains('doctorate')) {
      return 'PhD / Doctorate';
    }
    if (text.contains('mphil') || text.contains('m.phil')) {
      return 'MPhil / Postgraduate';
    }
    if (text.contains('master') ||
        text.contains('mba') ||
        text.contains('msc') ||
        text.contains('m.sc') ||
        text.startsWith('ms ')) {
      return "Master's";
    }
    if (text.contains('bachelor') ||
        text.contains('bsc') ||
        text.contains('b.sc') ||
        text.startsWith('bs ') ||
        text.contains('b.e') ||
        text.contains('btech') ||
        text.contains('b.tech')) {
      return "Bachelor's";
    }
    // Intermediate, A-Level, and Associate Diploma/DAE are intentionally
    // equivalent for minimum-education matching.
    if (text.contains('intermediate') ||
        text.contains('a-level') ||
        text.contains('a level') ||
        text.contains('hsc') ||
        text.contains('associate') ||
        text.contains('diploma') ||
        text.contains('dae')) {
      return 'Intermediate / A-Level';
    }
    if (text.contains('matric') ||
        text.contains('o-level') ||
        text.contains('o level') ||
        text.contains('secondary') ||
        text.contains('high school')) {
      return 'Secondary School';
    }
    return 'Other';
  }

  static int? educationRank(String category) {
    switch (normalizeEducationCategory(category)) {
      case 'Primary School':
        return 1;
      case 'Secondary School':
        return 2;
      case 'Intermediate / A-Level':
        return 3;
      case "Bachelor's":
        return 4;
      case "Master's":
        return 5;
      case 'MPhil / Postgraduate':
        return 6;
      case 'PhD / Doctorate':
        return 7;
    }
    return null;
  }

  static bool educationMeetsMinimum(String? minimum, String? actual) {
    final required = minimum?.trim();
    if (required == null ||
        required.isEmpty ||
        required.toLowerCase() == 'any' ||
        required.toLowerCase() == 'any education') {
      return true;
    }

    final value = actual?.trim();
    if (value == null || value.isEmpty) return false;

    final requiredCategory = normalizeEducationCategory(required);
    final actualCategory = normalizeEducationCategory(value);
    if (requiredCategory == 'Other') return actualCategory == 'Other';

    final requiredRank = educationRank(requiredCategory);
    final actualRank = educationRank(actualCategory);
    return requiredRank != null &&
        actualRank != null &&
        actualRank >= requiredRank;
  }
}
