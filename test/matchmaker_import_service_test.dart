import 'package:flutter_test/flutter_test.dart';
import 'package:nisa_e_sakina/services/matchmaker_import_service.dart';

void main() {
  test('parses WhatsApp-style biodata and aliases', () {
    final r = MatchmakerImportService.parseText('''Name: Ayesha Khan\nGender: Female\nAge: 26\nLocation: Karachi\nQualification: MBBS\nOccupation: Doctor\nWhatsApp: +92 300 1234567\nLooking for: Educated practicing Muslim''');
    expect(r.profiles, hasLength(1));
    expect(r.profiles.single.city, 'Karachi');
    expect(r.profiles.single.profession, 'Doctor');
    expect(r.profiles.single.partnerPreferences, contains('Educated'));
  });
  test('deduplicates by phone', () {
    final r = MatchmakerImportService.parseText('''Name: A\nGender: Female\nPhone: +92 300 1\n---\nName: B\nGender: Female\nPhone: +92-300-1''');
    expect(r.profiles, hasLength(1));
    expect(r.warnings.any((e)=>e.contains('duplicate')), isTrue);
  });
  test('CSV supports quoted commas', () {
    final r = MatchmakerImportService.parseCsv('full_name,gender,city,profession\n"Khan, Ayesha",Female,Karachi,Doctor');
    expect(r.profiles.single.fullName, 'Khan, Ayesha');
  });
}
