class ReligionService {
  ReligionService._();

  static const religions = <String>[
    'Islam',
    'Christianity',
    'Hinduism',
    'Sikhism',
    'Judaism',
    'Buddhism',
    'Jainism',
    'Baháʼí Faith',
    'Other',
  ];

  static const Map<String, List<String>> _sects = {
    'Islam': ['Sunni', 'Shia', 'Ibadi', 'Ahmadiyya', 'Other'],
    'Christianity': ['Catholic', 'Orthodox', 'Protestant', 'Anglican', 'Other'],
    'Hinduism': ['Vaishnavism', 'Shaivism', 'Shaktism', 'Smartism', 'Other'],
    'Sikhism': ['Khalsa', 'Nihang', 'Namdhari', 'Other'],
    'Judaism': [
      'Orthodox',
      'Conservative',
      'Reform',
      'Reconstructionist',
      'Other',
    ],
    'Buddhism': ['Theravada', 'Mahayana', 'Vajrayana', 'Other'],
    'Jainism': ['Digambara', 'Svetambara', 'Other'],
    'Baháʼí Faith': ['Baháʼí Faith'],
    'Other': ['Other'],
  };

  static final Map<String, List<String>> _cache = <String, List<String>>{};

  static List<String> cachedSects(String religion) {
    return List<String>.from(
      _cache[religion] ?? _sects[religion] ?? const ['Other'],
    );
  }

  /// Returns immediately from the offline catalogue and caches the result.
  /// Keeping this asynchronous lets a future server-backed catalogue be added
  /// without changing the registration screens.
  static Future<List<String>> sectsFor(String religion) async {
    final values = cachedSects(religion);
    _cache[religion] = values;
    await Future<void>.value();
    return List<String>.from(values);
  }
}
