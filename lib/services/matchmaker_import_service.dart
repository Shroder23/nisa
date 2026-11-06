import 'dart:convert';

import '../models/matchmaker_profile.dart';

class MatchmakerImportResult {
  const MatchmakerImportResult(this.profiles, this.warnings);
  final List<MatchmakerProfile> profiles;
  final List<String> warnings;
}

class MatchmakerImportService {
  static const _aliases = <String, String>{
    'name': 'full_name', 'full name': 'full_name', 'fullname': 'full_name',
    'sex': 'gender', 'location': 'city', 'qualification': 'education',
    'occupation': 'profession', 'job': 'profession', 'work': 'profession',
    'mobile': 'phone', 'contact': 'phone', 'contact no': 'phone',
    'contact number': 'phone', 'whatsapp': 'phone', 'e-mail': 'email',
    'preference': 'partner_preferences', 'preferences': 'partner_preferences',
    'looking for': 'partner_preferences', 'requirements': 'partner_preferences',
    'marital status': 'marital_status', 'ref': 'external_reference',
    'reference': 'external_reference', 'id': 'external_reference',
  };

  static String _key(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll('_', ' ');
    return _aliases[normalized] ?? normalized.replaceAll(' ', '_');
  }

  static MatchmakerImportResult parseText(String input) {
    final records = input.split(RegExp(r'\n\s*(?:---+|={3,})\s*\n'));
    final profiles = <MatchmakerProfile>[];
    final warnings = <String>[];
    for (var i = 0; i < records.length; i++) {
      final map = <String, dynamic>{};
      for (final line in const LineSplitter().convert(records[i])) {
        final match = RegExp(r'^\s*([^:：-]{2,40})\s*[:：-]\s*(.+?)\s*$').firstMatch(line);
        if (match != null) map[_key(match.group(1)!)] = match.group(2)!.trim();
      }
      if (map.isEmpty && records[i].trim().isNotEmpty) {
        warnings.add('Record ${i + 1}: no labelled fields were recognized.');
        continue;
      }
      final p = MatchmakerProfile.fromJson(map);
      if (p.fullName.isEmpty || p.gender.isEmpty) {
        warnings.add('Record ${i + 1}: name and gender are required.');
      } else {
        profiles.add(p);
      }
    }
    return MatchmakerImportResult(_dedupe(profiles, warnings), warnings);
  }

  static MatchmakerImportResult parseJson(String input) {
    final decoded = jsonDecode(input);
    final rows = decoded is List ? decoded : [decoded];
    final profiles = <MatchmakerProfile>[];
    final warnings = <String>[];
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] is! Map) { warnings.add('Row ${i + 1}: not an object.'); continue; }
      final map = <String, dynamic>{};
      (rows[i] as Map).forEach((k, v) => map[_key(k.toString())] = v);
      final p = MatchmakerProfile.fromJson(map);
      if (p.fullName.isEmpty || p.gender.isEmpty) {
        warnings.add('Row ${i + 1}: name and gender are required.');
      } else {
        profiles.add(p);
      }
    }
    return MatchmakerImportResult(_dedupe(profiles, warnings), warnings);
  }

  static MatchmakerImportResult parseCsv(String input) {
    final lines = const LineSplitter().convert(input).where((e) => e.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const MatchmakerImportResult([], ['The CSV file is empty.']);
    final headers = _csvRow(lines.first).map(_key).toList();
    final profiles = <MatchmakerProfile>[];
    final warnings = <String>[];
    for (var i = 1; i < lines.length; i++) {
      final values = _csvRow(lines[i]);
      final map = <String, dynamic>{};
      for (var c = 0; c < headers.length && c < values.length; c++) {
        map[headers[c]] = values[c];
      }
      final p = MatchmakerProfile.fromJson(map);
      if (p.fullName.isEmpty || p.gender.isEmpty) {
        warnings.add('CSV row ${i + 1}: name and gender are required.');
      } else {
        profiles.add(p);
      }
    }
    return MatchmakerImportResult(_dedupe(profiles, warnings), warnings);
  }

  static List<String> _csvRow(String line) {
    final out = <String>[]; final b = StringBuffer(); var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') { b.write('"'); i++; }
        else {
          quoted = !quoted;
        }
      } else if (ch == ',' && !quoted) { out.add(b.toString().trim()); b.clear(); }
      else { b.write(ch); }
    }
    out.add(b.toString().trim()); return out;
  }

  static List<MatchmakerProfile> _dedupe(List<MatchmakerProfile> input, List<String> warnings) {
    final seen = <String>{}; final out = <MatchmakerProfile>[];
    for (final p in input) {
      final key = p.email.trim().toLowerCase().isNotEmpty ? 'e:${p.email.trim().toLowerCase()}'
          : p.phone.replaceAll(RegExp(r'\D'), '').isNotEmpty ? 'p:${p.phone.replaceAll(RegExp(r'\D'), '')}'
          : 'n:${p.fullName.toLowerCase()}|${p.age}|${p.city.toLowerCase()}';
      if (!seen.add(key)) { warnings.add('Possible duplicate skipped: ${p.fullName}.'); continue; }
      out.add(p);
    }
    return out;
  }

  static String toCsv(List<MatchmakerProfile> profiles) {
    const fields = ['full_name','gender','age','city','country','height','marital_status','education','profession','religion','sect','phone','email','partner_preferences','consent_status','verification_status','visibility','external_reference'];
    String esc(Object? v) { final s = v?.toString() ?? ''; return '"${s.replaceAll('"', '""')}"'; }
    final rows = <String>[fields.join(',')];
    for (final p in profiles) { final m = p.toJson(); rows.add(fields.map((f) => esc(m[f])).join(',')); }
    return rows.join('\r\n');
  }
}
