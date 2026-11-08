import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nisa_e_sakina/models/user_profile.dart';
import 'package:nisa_e_sakina/services/app_language_service.dart';
import 'package:nisa_e_sakina/services/api_auth_service.dart';
import 'package:nisa_e_sakina/theme/nisa_theme.dart';
import 'package:nisa_e_sakina/presentation/nisa_premium/nisa_premium.dart';
import 'package:nisa_e_sakina/account_type_screen.dart';
import 'package:nisa_e_sakina/age_restricted_screen.dart';
import 'package:nisa_e_sakina/api_account_restrictions_screen.dart';
import 'package:nisa_e_sakina/api_admin_direct_ban_screen.dart';
import 'package:nisa_e_sakina/api_admin_reports_screen.dart';
import 'package:nisa_e_sakina/api_admin_user_management_screen.dart';
import 'package:nisa_e_sakina/api_admin_verification_screen.dart';
import 'package:nisa_e_sakina/api_blocked_users_screen.dart';
import 'package:nisa_e_sakina/api_chat_screen.dart';
import 'package:nisa_e_sakina/api_conversations_screen.dart';
import 'package:nisa_e_sakina/api_discovery_screen.dart';
import 'package:nisa_e_sakina/api_email_access_screen.dart';
import 'package:nisa_e_sakina/api_family_invitations_screen.dart';
import 'package:nisa_e_sakina/api_family_screen.dart';
import 'package:nisa_e_sakina/api_incoming_interests_screen.dart';
import 'package:nisa_e_sakina/api_login_screen.dart';
import 'package:nisa_e_sakina/api_matches_screen.dart';
import 'package:nisa_e_sakina/api_matchmaker_screen.dart';
import 'package:nisa_e_sakina/api_moderator_logs_screen.dart';
import 'package:nisa_e_sakina/api_moderator_recommendations_screen.dart';
import 'package:nisa_e_sakina/api_moderator_requests_screen.dart';
import 'package:nisa_e_sakina/api_my_reports_screen.dart';
import 'package:nisa_e_sakina/api_notifications_screen.dart';
import 'package:nisa_e_sakina/api_privacy_settings_screen.dart';
import 'package:nisa_e_sakina/api_sent_interests_screen.dart';
import 'package:nisa_e_sakina/api_session_management_screen.dart';
import 'package:nisa_e_sakina/api_verification_pending_screen.dart';
import 'package:nisa_e_sakina/api_verification_screen.dart';
import 'package:nisa_e_sakina/api_verification_upload_screen.dart';
import 'package:nisa_e_sakina/basic_profile_screen.dart';
import 'package:nisa_e_sakina/edit_profile_screen.dart';
import 'package:nisa_e_sakina/main.dart';
import 'package:nisa_e_sakina/matrimonial_preferences_screen.dart';
import 'package:nisa_e_sakina/report_user_screen.dart';

// No real endpoint or storage is used. These routes are tested with empty API
// collections; this does not claim that an administrator action was performed.
UserProfile profile() => UserProfile(
  uid: 'isolated',
  name: '',
  gender: 'male',
  dateOfBirth: DateTime(1995),
  city: '',
  maritalStatus: 'Never Married',
);

final catalog = <String, Widget Function()>{
  '16-welcome': () => const WelcomeScreen(),
  '17-login': () => const ApiLoginScreen(),
  '19-email-access': () => const ApiEmailAccessScreen(),
  '21-password-recovery': () => const ApiPasswordResetScreen(initialEmail: ''),
  '22-account-type': () => const AccountTypeScreen(),
  '23-basic-profile': () => const BasicProfileScreen(
    uid: 'isolated',
    email: '',
    phone: '',
    accountType: 'unverified',
  ),
  '24-age-confirmation': () => const AgeConfirmationScreen(),
  '25-age-restriction': () => const AgeRestrictedScreen(),
  '02-search': () => ApiDiscoveryScreen(currentUser: profile()),
  '08-received-interests': () => const ApiIncomingInterestsScreen(),
  '09-sent-interests': () => const ApiSentInterestsScreen(),
  '10-matches': () => const ApiMatchesScreen(),
  '11-messages': () => const ApiConversationsScreen(),
  '12-conversation': () => const ApiChatScreen(
    conversationId: 'isolated',
    otherUserName: '',
    otherUserId: 'isolated-other',
  ),
  '14-edit-profile': () => EditProfileScreen(profile: profile()),
  '15-preferences': () =>
      MatrimonialPreferencesScreen(profile: profile(), isEditing: true),
  '26-notifications': () => const ApiNotificationsScreen(),
  '27-family': () => const ApiFamilyScreen(),
  '28-invitations': () => const ApiFamilyInvitationsScreen(),
  '29-matchmaker': () => const ApiMatchmakerScreen(),
  '30-verification': () => ApiVerificationScreen(profile: profile()),
  '31-verification-upload': () => const ApiVerificationUploadScreen(),
  '32-verification-pending': () => const ApiVerificationPendingScreen(),
  '33-privacy': () => const ApiPrivacySettingsScreen(),
  '34-blocked': () => const ApiBlockedUsersScreen(),
  '35-sessions': () => const ApiSessionManagementScreen(),
  '37-report': () => const ReportUserScreen(
    reportedUserId: 'isolated-other',
    reportedUserName: '',
  ),
  '38-my-reports': () => const ApiMyReportsScreen(),
  '40-restrictions': () => const ApiAccountRestrictionsScreen(),
  '43-admin-reports': () => const ApiAdminReportsScreen(),
  '44-admin-users': () => const ApiAdminUserManagementScreen(),
  '45-admin-restriction': () => const ApiAdminDirectBanScreen(),
  '46-admin-verification': () => const ApiAdminVerificationScreen(),
  '50-moderator-recommendations': () =>
      const ApiModeratorRecommendationsScreen(),
  '51-moderator-logs': () => const ApiModeratorLogsScreen(),
  '52-moderator-requests': () => const ApiModeratorRequestsScreen(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('NISA_CAPTURE_CATALOG');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'nisa_api_access_token': 'isolated',
      'nisa_api_refresh_token': 'isolated',
    });
    ApiAuthService.currentAccount.value = {'id': 'isolated'};
  });
  for (final variant in [
    (390.0, 1.0, 'en'),
    (320.0, 2.0, 'en'),
    (411.0, 2.0, 'pa'),
  ]) {
    for (final entry in catalog.entries) {
      testWidgets('${entry.key} ${variant.$1} ${variant.$2} ${variant.$3}', (
        tester,
      ) async {
        await http.runWithClient(
          () async {
            tester.view.physicalSize = Size(variant.$1, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            AppLanguageService.selectedCode.value = variant.$3;
            AppLanguageService.locale.value = variant.$3 == 'pa'
                ? const Locale.fromSubtags(
                    languageCode: 'pa',
                    scriptCode: 'Arab',
                    countryCode: 'PK',
                  )
                : const Locale('en');
            if (capture) await loadFonts(tester);
            final boundary = GlobalKey();
            await tester.pumpWidget(
              MaterialApp(
                theme: NisaPremiumTheme.apply(NisaTheme.light),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(variant.$1, 900),
                    textScaler: TextScaler.linear(variant.$2),
                  ),
                  child: Directionality(
                    textDirection: variant.$3 == 'pa'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: RepaintBoundary(key: boundary, child: entry.value()),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull);
            if (capture &&
                variant.$2 == 1 &&
                !['14-edit-profile', '15-preferences'].contains(entry.key)) {
              await tester.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File('build/premium-screens/${entry.key}.png');
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          },
          () => MockClient((request) async {
            // Fail closed on writes; no test can modify a real member account.
            if (request.method != 'GET') {
              return http.Response('{"detail":"isolated preview"}', 403);
            }
            final data = <String, dynamic>{
              'profiles': [],
              'interests': [],
              'conversations': [],
              'messages': [],
              'notifications': [],
              'members': [],
              'invitations': [],
              'requests': [],
              'reports': [],
              'restrictions': [],
              'sessions': [],
              'users': [],
              'logs': [],
              'recommendations': [],
              'blocked_users': [],
              'blocks': [],
              'has_more': false,
              'enabled': false,
              'status': 'not_submitted',
              'settings': {
                'show_online_status': true,
                'share_read_receipts': true,
              },
              'account': null,
              'is_admin': false,
              'can_review': false,
            };
            return http.Response(
              jsonEncode(data),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
      });
    }
  }
}

Future<void> loadFonts(WidgetTester tester) async {
  for (final family in ['sans', 'Roboto', 'Arial', 'Ahem']) {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/arial.ttf').readAsBytesSync(),
          ),
        ),
      );
    await tester.runAsync(loader.load);
  }
  final loader = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await tester.runAsync(loader.load);
}
