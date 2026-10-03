import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nisa_e_sakina/services/app_language_service.dart';
import 'package:nisa_e_sakina/widgets/localized_text.dart';

const _preservedTerms = {
  'Nisa',
  'Nisa e Sakina',
  'Google',
  'Apple',
  'WhatsApp',
  'Facebook',
  'Instagram',
  'OTP',
  'SMS',
  'G', // Google sign-in mark, not a translated word.
};

// These exact French spellings are standard French UI terms, not English fallbacks.
const _sameFormLocalizedCopy = {
  'fr': {'Message', 'Messages', 'Notifications'},
};

const _stringCall =
    r'''\b(LocalizedText|Text|AppLanguageService\.translate)\s*\(\s*(?:const\s+)?(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')''';
const _uiProperty =
    r'''\b(labelText|hintText|helperText|errorText|tooltip|semanticsLabel)\s*:\s*(?:const\s+)?(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')''';

Map<String, Set<String>> _collectStaticCopy() {
  final localized = <String>{};
  final rawText = <String>{};
  final dynamicCopy = <String>{};
  final pattern = RegExp(_stringCall, multiLine: true, dotAll: true);
  final propertyPattern = RegExp(_uiProperty, multiLine: true, dotAll: true);

  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('app_language_service.dart')) continue;
    if (RegExp(r'\.(?:bak|backup)\.dart$').hasMatch(entity.path)) continue;

    final source = entity.readAsStringSync();
    for (final match in pattern.allMatches(source)) {
      final constructor = match.group(1)!;
      final rawLiteral = match.group(2) ?? match.group(3) ?? '';
      if (_hasInterpolation(rawLiteral)) {
        dynamicCopy.add('${entity.path}: $rawLiteral');
        continue;
      }
      final literal = _decodeDartLiteral(rawLiteral);
      if (_isNonLinguistic(literal)) continue;
      if (constructor == 'Text') {
        rawText.add('${entity.path}: $literal');
      } else {
        localized.add(literal);
      }
    }
    for (final match in propertyPattern.allMatches(source)) {
      final rawLiteral = match.group(2) ?? match.group(3) ?? '';
      if (_hasInterpolation(rawLiteral)) {
        dynamicCopy.add('${entity.path}: ${match.group(1)}: $rawLiteral');
        continue;
      }
      final literal = _decodeDartLiteral(rawLiteral);
      if (_isNonLinguistic(literal)) continue;
      rawText.add('${entity.path}: ${match.group(1)}: $literal');
    }
  }

  return {'localized': localized, 'rawText': rawText, 'dynamic': dynamicCopy};
}

bool _hasInterpolation(String value) {
  for (var index = 0; index < value.length; index++) {
    if (value.codeUnitAt(index) != 0x24) continue;
    var slashes = 0;
    for (
      var previous = index - 1;
      previous >= 0 && value.codeUnitAt(previous) == 0x5c;
      previous--
    ) {
      slashes++;
    }
    if (slashes.isEven) return true;
  }
  return false;
}

String _decodeDartLiteral(String value) {
  final result = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit != 0x5c || index + 1 >= value.length) {
      result.writeCharCode(unit);
      continue;
    }
    final next = value.codeUnitAt(++index);
    switch (next) {
      case 0x6e:
        result.write('\n');
        break;
      case 0x72:
        result.write('\r');
        break;
      case 0x74:
        result.write('\t');
        break;
      case 0x24:
        result.write(r'$');
        break;
      case 0x5c:
        result.write('\\');
        break;
      case 0x27:
        result.write("'");
        break;
      case 0x22:
        result.write('"');
        break;
      default:
        result
          ..writeCharCode(0x5c)
          ..writeCharCode(next);
    }
  }
  return result.toString();
}

bool _isNonLinguistic(String literal) {
  final value = literal.replaceAll(r"\'", "'").replaceAll(r'\"', '"').trim();
  return value.isEmpty ||
      _preservedTerms.contains(value) ||
      RegExp(r'^[^A-Za-z0-9]+$').hasMatch(value) ||
      RegExp(r'''^\d+\s*['′]\s*\d+\s*["″]$''').hasMatch(value);
}

void _selectTestLanguage(AppLanguage language) {
  // Tests only need the in-memory selection; avoid disk/plugin work for every
  // locale in the coverage and RTL loops.
  AppLanguageService.selectedCode.value = language.code;
  AppLanguageService.locale.value = language.locale;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Set<String>> inventory;

  setUpAll(() {
    inventory = _collectStaticCopy();
  });

  test('all localized static copy has translations for every app language', () {
    final missing = <String>[];
    final missingByLanguage = <String, List<String>>{};
    final sourceKeys = inventory['localized']!.toList()..sort();

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in sourceKeys) {
        final sameFormTerms =
            _sameFormLocalizedCopy[language.code] ?? const <String>{};
        if (AppLanguageService.translate(key) == key &&
            !_preservedTerms.contains(key) &&
            !sameFormTerms.contains(key)) {
          missing.add('${language.code}: $key');
          missingByLanguage.putIfAbsent(language.code, () => []).add(key);
        }
      }
    }

    final report = File('build/localization_missing_translations.txt');
    report.parent.createSync(recursive: true);
    report.writeAsStringSync(
      [
        'Missing locale/key pairs: ${missing.length}',
        for (final entry in missingByLanguage.entries) ...[
          '',
          '${entry.key}: ${entry.value.length}',
          ...entry.value,
        ],
      ].join('\n'),
    );

    expect(
      missing,
      isEmpty,
      reason:
          '${missing.length} untranslated locale/key pairs. See '
          'build/localization_missing_translations.txt.',
    );
  });

  test(
    'email and standard French navigation terms are localized correctly',
    () {
      final indonesian = AppLanguageService.languages.firstWhere(
        (language) => language.code == 'id',
      );
      _selectTestLanguage(indonesian);
      expect(AppLanguageService.translate('Email'), 'Surel');

      final french = AppLanguageService.languages.firstWhere(
        (language) => language.code == 'fr',
      );
      _selectTestLanguage(french);
      expect(AppLanguageService.translate('Message'), 'Message');
      expect(AppLanguageService.translate('Messages'), 'Messages');
      expect(AppLanguageService.translate('Notifications'), 'Notifications');
    },
  );

  test(
    'verification consent and badge copy is translated for every locale',
    () {
      const criticalKeys = [
        'A 6-digit verification code will be sent to this email before your Firebase account is created.',
        'A verified badge is given only after parent or guardian verification is reviewed and approved.',
        'Continue Without Verification',
        'Verification pending',
        'Verification Under Review',
        'Unverified profiles can use core Nisa features. Approved profiles display the Parent Verified badge.',
      ];

      for (final language in AppLanguageService.languages) {
        _selectTestLanguage(language);
        if (language.code == 'en') continue;
        for (final key in criticalKeys) {
          expect(
            AppLanguageService.translate(key),
            isNot(key),
            reason:
                '${language.code} is missing critical verification copy: $key',
          );
        }
      }
    },
  );

  test(
    'core profile, account, and moderation actions translate in every locale',
    () {
      const keys = [
        'About',
        'About Me',
        'Account Restricted',
        'Action taken',
        'Add profile photo',
        'Adjust filters',
        'Admin Access',
        'Admin Identity',
        'Admin UID copied.',
        'Admin key',
        'Age / Date of Birth',
        'Aligned preferences',
        'All categories',
        'All notifications marked as read.',
        'Already married / dishonest status',
        'Alternate wali / guardian',
        'Any height',
        'Appeal decision saved',
        'Appeal submitted for review',
        'Apply',
        'Approve',
        'Approve Verification',
        'Approve only after reviewing the parent/guardian ID and confirmation video.',
        'Approve verification?',
        'Are you sure you want to log out?',
      ];

      for (final language in AppLanguageService.languages) {
        _selectTestLanguage(language);
        if (language.code == 'en') continue;
        for (final key in keys) {
          expect(
            AppLanguageService.translate(key),
            isNot(key),
            reason: '${language.code} is missing: $key',
          );
        }
      }
    },
  );

  test('profile, preferences, and verification queue copy translates in every locale', () {
    const keys = [
      'No family member is linked yet.\n\n',
      'No pending ',
      'No pending family invitations were found for your ',
      'Practicing',
      'Prefer not to say',
      'Preferences to review',
      'Preferred Age',
      'Preferred Religious Practice',
      'Preparing your profile…',
      'Profile information ',
      'Profile photo updated.',
      'Profile unavailable',
      'Protected admin-only playback',
      'Provide at least one contact method. Email enables the ',
      'Queue priority',
      'Real profiles ranked using your matrimonial preferences.',
      'Reason',
      'Received',
      'Recommended: under 60 seconds',
      'Record the confirmation video',
      'Record verification video',
      'Reject',
      'Reject Verification',
      'Reject verification',
      'Relation',
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test('review and profile actions translate in every locale', () {
    const keys = [
      "Review and unblock people",
      "Review invitations sent to your email",
      "Review pending verification requests",
      "Review people who expressed interest",
      "Update your personal information",
      "Verify your profile",
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test('preferences, login, and account management labels translate in every locale', () {
    const keys = [
      "Matrimonial Preferences",
      "Password reset email sent.",
      "Please complete all required fields.",
      "Please enter the 6-digit code sent to",
      "Preferred City",
      "Preferred Country",
      "Preferred Height",
      "Preferred Marital Status",
      "Primary Language",
      "Profession",
      "Profile Details",
      "Recommended for you",
      "Religious Practice",
      "Willing to Relocate",
      "Admin Verification",
      "Blocked Users",
      "Change your preferred match criteria",
      "Family Invitations",
      "Invite a trusted family member",
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test(
    'verification completion and profile setup copy translates in every locale',
    () {
      const keys = [
        "Your parent identification and confirmation video were submitted successfully. Your profile will remain pending until an administrator reviews and approves the evidence.",
        "Your parent or wali verification was submitted successfully and is waiting for review by an authorized Nisa reviewer.",
        "Your profile is still loading.",
        "Your saved matrimonial preferences rank compatible profiles. Discovery filters only narrow the list when you choose them.",
        "Your verification documents have already been submitted. You do not need to upload them again while the request is being reviewed.",
        "Back",
        "Basic Profile",
        "Enter your email address first.",
        "Find a meaningful connection.",
        "Full Name",
        "Gender",
        "Height",
      ];

      for (final language in AppLanguageService.languages) {
        _selectTestLanguage(language);
        if (language.code == 'en') continue;
        for (final key in keys) {
          expect(
            AppLanguageService.translate(key),
            isNot(key),
            reason: '${language.code} is missing: $key',
          );
        }
      }
    },
  );

  test('verification, messaging, and account state copy translates in every locale', () {
    const keys = [
      "Verification is optional. Unverified members can still use discovery, interests, messaging after a match, blocking, and reporting.",
      "Verification is optional. You can continue without a Verified badge.",
      "Verification is under review",
      "Verification rejected",
      "Verification rejected. The user can submit corrected documents.",
      "Verification resubmission requested",
      "Parent verification not completed",
      "Parent verification is under review",
      "Parent verification approved",
      "Verified - no further action needed",
      "What are you looking for?",
      "When an incoming interest is accepted, the match will appear here.",
      "When someone sends an interest,\naccepts your request,\nor sends you a message,\nyou will see it here.",
      "When the review is completed, your status will change to verified or you will receive a reason if another submission is required.",
      "Willing to relocate",
      "Write a message...",
      "You are already signed in. ",
      "You are continuing an existing Firebase account. A new account will not be created.",
      "You are not signed in.",
      "You can learn more about verification before ",
      "You do not need to submit the documents again. The Parent Verified badge will appear only after the review is approved.",
      "You have not blocked anyone.",
      "You have not sent any interests yet.",
      "You have not submitted any reports.",
      "You matched. Start a respectful conversation.",
      "You must be 18 or older and have at least one profile photo. Your ID and video are private and can only be opened by an authorized Nisa reviewer. Approval adds the “Parent Verified” badge; it confirms this review and does not guarantee character or suitability.",
      "You will no longer be able to send interests or messages to each other. The profile will also be hidden from search.",
      "Your account is not properly linked. ",
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test('profile loading, blocking, and verification results translate in every locale', () {
    const keys = [
      "Tell us about yourself",
      "This profile will be hidden, and neither of you can send interests or messages. They will not be notified.",
      "This protected verification video is downloaded ",
      "This user has been blocked.",
      "Try Again",
      "Unable to load ",
      "Unable to load match",
      "Unable to load matches.",
      "Unable to load profiles.",
      "Unable to load recommendations.",
      "Update Profile Photo",
      "Uphold closure",
      "Use a different account",
      "Use this only for genuine safety, privacy, honesty, or misuse concerns.",
      "Use your camera",
      "User ID",
      "User blocked.",
      "User blocked. Messaging disabled.",
      "User unblocked.",
      "Verification Detail",
      "Verification Submitted",
      "Verification approved",
      "Verification approved.",
      "Verification documents are private, stored on the Nisa local server, and used only for verification review.",
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test('sign-in, verification, and profile safety copy translates in every locale', () {
    const keys = [
      "Sign in to continue your Nisa journey.",
      "Sign out",
      "Someone is interested in you",
      "Start Verification Upload",
      "Status",
      "Submit for Verification",
      "Submit report",
      "Submitted",
      "Take ID photo",
      "Take a photo",
      "Tell potential matches about yourself...",
      "Tell us a little more",
      "The parent or wali knows about and consents to this verification submission.",
      "The parent or wali should say their name and relationship, your name, confirm you are their son or daughter, and confirm they know you are seeking a spouse through Nisa and consent to being involved.",
      "The recipient must sign in using this email to accept. Phone-only invitations cannot be accepted yet. No email or SMS is sent.",
      "These details help families understand your background and preferences.",
      "This ID may be a PDF or could not be ",
      "This information will help us create your matrimonial profile.",
      "This notification has no destination yet.",
      "This person is interested ",
      "This profile is ",
      "This profile is no longer available.",
      "This profile will be hidden and neither of you can send interests or messages. They will not be notified.",
      "This profile will be hidden, and neither of you can send interests or messages.",
      "The parent or wali should say their name and relationship, your name, confirm you are their son or daughter, and confirmthey know you are seeking a spouse through Nisa and consent to being involved.",
      "The recipient must sign in using this email to accept. Phone-only invitations cannot be accepted yet. No email or SMS issent.",
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test(
    'account, reporting, and preference copy translates in every locale',
    () {
      const keys = [
        'Please sign in again.',
        'Religion',
        'Relocation',
        'Relocation Preference',
        'Remove family member?',
        'Reopen for review',
        'Report Profile',
        'Report decision saved',
        'Report profile',
        'Report resolved',
        'Report submitted for review.',
        'Report submitted.',
        'Request',
        'Request ID',
        'Required for verification:',
        'Resolve',
        'Role',
        'Save decision',
        'Scam or suspicious activity',
        'Sect',
        'Select an existing photo',
        'Send interest again',
        'Sent',
        'Set your preferred criteria. You can change these later.',
      ];

      for (final language in AppLanguageService.languages) {
        _selectTestLanguage(language);
        if (language.code == 'en') continue;
        for (final key in keys) {
          expect(
            AppLanguageService.translate(key),
            isNot(key),
            reason: '${language.code} is missing: $key',
          );
        }
      }
    },
  );

  test('discovery guidance and common actions translate in every locale', () {
    const keys = [
      'As more eligible profiles join Nisa, compatible profiles will appear here.',
      'Based only on the matrimonial preferences you have specified. ',
      'Broaden the discovery filters without changing your saved matrimonial preferences.',
      'Caste',
      'Change profile photo',
      'Checking this email address…',
      'Choose ID image',
      'Choose an existing video',
      'Choose from gallery',
      'Choose video from gallery',
      'Compatibility',
      'Contact details remain private until mutual acceptance.',
      'Copy UID',
      'Could not authorize ID preview: ',
      'Could not decline ',
      'Could not open ',
      'Could not refresh every dropdown option. Saved choices remain available.',
      'Could not restore your account',
      'Create Invite',
      'Created',
      'Date of Birth',
      'Date of birth is required',
      'Delete',
      'Details',
      'Dismiss',
      'Duplicate report',
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test('family and interaction messages translate in every locale', () {
    const keys = [
      'Education & Career',
      'Email (recommended)',
      'Email already registered',
      'Email already registered. Please use Login.',
      'Error',
      'Explain what happened. Do not include private documents unless necessary.',
      'Explain what must be corrected before resubmission.',
      'Fake or misleading information',
      'Family Verification',
      'Family connection removed.',
      'Family invitation created. The invited person can accept it ',
      'Family member removed.',
      'Family verification upload is not connected to PostgreSQL yet. Continuing below will leave this profile unverified.',
      'Father',
      'Female',
      'Firebase administrator UID',
      'For a Verified badge, submit one parent/guardian identification image and a short confirmation video. No linked guardian account is required.',
      'Guardian linked',
      'Harassment or disrespectful behavior',
      'Inappropriate profile',
      'Insufficient information',
      'Interaction Unavailable',
      'Interaction is unavailable because one of you has blocked the other.',
      'Interest Accepted',
      'Interest Declined',
      'Interest accepted. ',
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test('interest, invitation, and filter labels translate in every locale', () {
    const keys = [
      'Interest accepted. You are now matched if the interest is mutual.',
      'Interest already exists',
      'Interest declined.',
      'Interest sent again.',
      'Interest sent successfully.',
      'Interest sent.',
      'Interests',
      'Invitation created. It will appear in the recipient’s Nisa app when they sign in with that email.',
      'Invitations appear in Nisa when the recipient signs in with the invited email. No email or SMS is sent in this phase. Phone-only invitations cannot be accepted yet. Family information stays private and is not shown in discovery. Accepting does not grant a verification badge.',
      'Invite Family / Guardian',
      'Invite Member',
      'Invite a trusted adult family member or guardian. ',
      'Invite family / guardian',
      'Invite member',
      'Language',
      'Leave blank for any city',
      'Leave blank for any country',
      'Loading cities…',
      'Loading...',
      'Log Out?',
      'Male',
      'Marital status',
      'Mark all as read',
      'Mark reviewing',
      'Matrimonial Information',
      'Maximum',
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test('age, messaging, and account-state copy translates in every locale', () {
    const keys = [
      'Maximum age cannot be below minimum age.',
      'Maybe',
      'Messages can be up to 2,000 characters.',
      'Messaging is unavailable because one of you has blocked the other.',
      'Minimum',
      'Moderately Practicing',
      'Mother',
      'My preferences',
      'My reports',
      'Name',
      'Neither of you will be able to send interests or messages. They will not be notified.',
      'Neither of you will be able to send messages while the block is active.',
      'New Interest',
      'New interests sent ',
      'New match',
      'Nisa Member',
      'Nisa Startup Error',
      'Nisa could not start Firebase.',
      'Nisa is intended for adults (18 years and older). ',
      'No cities were returned for this country.',
      'No family members yet. Use Invite member to add a parent, guardian, or trusted family member.',
      'No further verification upload is required. Your verified badge remains active unless your verification status is changed by moderation.',
      'No notifications yet',
      'No open reports or appeals are waiting for review.',
      'No parent ID file found.',
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test('family verification, navigation, and notification copy translates in every locale', () {
    const keys = [
      'No pending requests loaded.',
      'No received interests yet.',
      'No recommendations yet.',
      'No violation found',
      'Not willing to relocate',
      'Notification deleted',
      'Notifications marked as read.',
      'Open conversation',
      'Open messages',
      'Open one of your matches and tap Message to start.',
      'Other',
      'Other outcome',
      'Outcome',
      'Parent / Guardian',
      'Parent Confirmation Video',
      'Parent ID',
      'Parent ID selected.',
      'Parent Identification',
      'Parent Verified',
      'Parent verification video selected.',
      'Personal Details',
      'Phone (optional if email is provided)',
      'Please explain the issue in at least 10 characters.',
      'Please provide both parent ID and parent video.',
      'Please select your date of birth.',
    ];

    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      for (final key in keys) {
        expect(
          AppLanguageService.translate(key),
          isNot(key),
          reason: '${language.code} is missing: $key',
        );
      }
    }
  });

  test('generic operation failure copy is localized for every locale', () {
    const key = 'Something went wrong. Please try again.';
    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      expect(
        AppLanguageService.translate(key),
        isNot(key),
        reason: '${language.code} is missing the generic error message',
      );
    }
  });

  test('dynamic block and report labels preserve translated templates', () {
    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      if (language.code == 'en') continue;
      const templates = {
        'Block {name}?': {'name': 'Amina'},
        'Report {name}': {'name': 'Amina'},
        'Welcome, {name}': {'name': 'Amina'},
        'Invited you as {role}': {'role': 'guardian'},
        'Reported member: {name}': {'name': 'Amina'},
        'Reporter: {name}': {'name': 'Amina'},
      };
      for (final entry in templates.entries) {
        final result = AppLanguageService.translateTemplate(
          entry.key,
          entry.value,
        );
        expect(RegExp(r'\{\w+\}').hasMatch(result), isFalse);
        expect(result, contains(entry.value.values.single));
        expect(result, isNot(entry.key));
      }
    }
  });

  test('visible labels do not bypass localization or use raw interpolated copy', () {
    final rawText = inventory['rawText']!.toList()..sort();
    final dynamicCopy = inventory['dynamic']!.toList()..sort();
    final report = File('build/localization_unwrapped_text.txt');
    report.parent.createSync(recursive: true);
    report.writeAsStringSync(
      [
        'Static direct Text/property literals: ${rawText.length}',
        ...rawText,
        '',
        'Interpolated literal strings: ${dynamicCopy.length}',
        ...dynamicCopy,
      ].join('\n'),
    );
    expect(
      rawText,
      isEmpty,
      reason:
          '${rawText.length} static Text/property literals bypass localization. '
          'See build/localization_unwrapped_text.txt.',
    );
    expect(
      dynamicCopy,
      isEmpty,
      reason:
          '${dynamicCopy.length} interpolated strings need localized '
          'templates. See build/localization_unwrapped_text.txt.',
    );
  });

  test('RTL language choices use RTL Flutter locales', () {
    const rtlCodes = {'ur', 'sd', 'ar', 'fa'};
    for (final language in AppLanguageService.languages.where(
      (item) => rtlCodes.contains(item.code),
    )) {
      expect(
        rtlCodes.contains(language.locale.languageCode),
        isTrue,
        reason: '${language.code} must map to an RTL Flutter locale',
      );
    }
  });

  test('number, age, and height formatting remain available by locale', () {
    for (final language in AppLanguageService.languages) {
      _selectTestLanguage(language);
      expect(
        AppLanguageService.translateAge('{age} years', age: 25),
        isNotEmpty,
      );
      expect(AppLanguageService.formatHeight('5\'7"'), isNotEmpty);
    }
    _selectTestLanguage(
      AppLanguageService.languages.firstWhere(
        (language) => language.code == 'ur',
      ),
    );
    expect(AppLanguageService.formatNumber(123), '١٢٣');
  });

  testWidgets('localized copy renders at large text size in RTL direction', (
    tester,
  ) async {
    _selectTestLanguage(
      AppLanguageService.languages.firstWhere(
        (language) => language.code == 'ar',
      ),
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const Directionality(
        textDirection: ui.TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: LocalizedText(
              'Your saved matrimonial preferences rank compatible profiles. Discovery filters only narrow the list when you choose them.',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
