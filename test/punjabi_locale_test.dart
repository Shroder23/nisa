import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nisa_e_sakina/services/app_language_service.dart';

void main() {
  test('Punjabi is identified as Pakistani Shahmukhi and RTL', () {
    final punjabi = AppLanguageService.languages.firstWhere(
      (language) => language.code == 'pa',
    );

    expect(punjabi.name, 'Punjabi (Pakistan)');
    expect(punjabi.nativeName, 'پنجابی');
    expect(punjabi.locale.scriptCode, 'Arab');
    expect(punjabi.locale.countryCode, 'PK');
    expect(AppLanguageService.textDirectionFor(punjabi), TextDirection.rtl);
  });

  test(
    'Punjabi dynamic, safety, verification, and error copy is Shahmukhi',
    () {
      AppLanguageService.selectedCode.value = 'pa';

      const copy = [
        'Block {name}?',
        'Email or password is incorrect.',
        'Set your password',
        'A verified badge is given only after parent or guardian verification is reviewed and approved.',
        'This user has been blocked.',
        'The server could not complete this request. Check the API logs for the cause.',
      ];
      for (final key in copy) {
        final translated = AppLanguageService.translate(key);
        expect(
          translated,
          isNot(key),
          reason: 'Missing Punjabi translation: $key',
        );
        expect(RegExp(r'[\u0900-\u097F]').hasMatch(translated), isFalse);
        expect(RegExp(r'[\u0A00-\u0A7F]').hasMatch(translated), isFalse);
      }

      expect(
        AppLanguageService.translate(
          'A verified badge is given only after parent or guardian verification is reviewed and approved.',
        ),
        'تصدیق شدہ بیج صرف ماں پیو یا سرپرست دی تصدیق دا جائزہ تے منظوری ملن توں بعد دتا جاندا اے۔',
      );
      expect(
        AppLanguageService.translateAge('Are you {age} or older?', age: 18),
        'کی تہاڈی عمر 18 سال یا اس توں ودھ اے؟',
      );
      expect(AppLanguageService.translate('Temporary ban'), 'عارضی پابندی');
    },
  );
}
