import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nisa_e_sakina/api_home_dashboard.dart';
import 'package:nisa_e_sakina/models/candidate_profile.dart';
import 'package:nisa_e_sakina/models/interest.dart';
import 'package:nisa_e_sakina/models/user_profile.dart';
import 'package:nisa_e_sakina/services/api_discovery_service.dart';
import 'package:nisa_e_sakina/services/app_language_service.dart';
import 'package:nisa_e_sakina/theme/nisa_theme.dart';
import 'package:nisa_e_sakina/widgets/api_candidate_cards.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (const bool.fromEnvironment('NISA_CAPTURE_HOME')) {
    testWidgets('capture Home widget preview at 360 and 411', (tester) async {
      final font = FontLoader('sans');
      font.addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/arial.ttf').readAsBytesSync(),
          ),
        ),
      );
      await tester.runAsync(font.load);
      for (final family in ['Roboto', 'Arial', 'Ahem']) {
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
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await tester.runAsync(icons.load);
      AppLanguageService.selectedCode.value = 'en';
      for (final width in [360.0, 411.0]) {
        await tester.binding.setSurfaceSize(Size(width, 850));
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: NisaTheme.light.copyWith(
              textButtonTheme: TextButtonThemeData(
                style: NisaTheme.light.textButtonTheme.style!.copyWith(
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontFamily: 'sans', fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            home: RepaintBoundary(
              key: boundaryKey,
              child: MediaQuery(
                data: MediaQueryData(size: Size(width, 850)),
                child: Scaffold(
                  backgroundColor: const Color(0xFFF8F5F2),
                  appBar: AppBar(
                    backgroundColor: const Color(0xFF582039),
                    foregroundColor: const Color(0xFFFFF9F2),
                    title: const Text(
                      'Nisa',
                      style: TextStyle(
                        color: Color(0xFFFFF9F2),
                        fontFamily: 'sans',
                      ),
                    ),
                    actions: const [
                      Icon(Icons.language),
                      SizedBox(width: 18),
                      Icon(Icons.notifications_outlined),
                      SizedBox(width: 12),
                    ],
                  ),
                  body: ApiHomeDashboard(
                    profile: _profile()..name = 'Preview member',
                    profileCompletion: 65,
                    onEditProfile: () {},
                    onSeeAll: () {},
                    locationSharingLoader: () async => true,
                    radiusLoader: () async => 25,
                    interestsLoader: () async => [],
                    nearbyLoader: (_, _) async => ApiDiscoveryPage(
                      profiles: [
                        _candidate('1'),
                        _candidate('2'),
                        _candidate('3'),
                        _candidate('4'),
                      ],
                      hasMore: false,
                    ),
                    recommendationLoader: (_) async => ApiDiscoveryPage(
                      profiles: [
                        _candidate('5'),
                        _candidate('6'),
                        _candidate('7'),
                      ],
                      hasMore: false,
                    ),
                  ),
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: 0,
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysShow,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.search),
                        label: 'Search',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.favorite_border),
                        label: 'Matches',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.chat_bubble_outline),
                        label: 'Messages',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline),
                        label: 'Profile',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('build/home-preview/home-${width.toInt()}.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.binding.setSurfaceSize(null);
    });
  }

  setUp(() {
    AppLanguageService.selectedCode.value = 'en';
    AppLanguageService.locale.value = const Locale('en');
  });

  testWidgets(
    'nearby rail renders profiles and excludes duplicates from feed',
    (tester) async {
      final nearby = [_candidate('a'), _candidate('b'), _candidate('a')];
      final recommendations = [
        _candidate('a'),
        _candidate('c'),
        _candidate('d'),
      ];

      await _pumpDashboard(
        tester,
        nearby: nearby,
        recommendations: recommendations,
      );

      expect(find.byKey(const ValueKey('nearby-rail')), findsOneWidget);
      expect(find.byKey(const ValueKey('nearby-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('nearby-b')), findsOneWidget);
      expect(find.byKey(const ValueKey('recommendation-a')), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recommendation-c')), findsOneWidget);
    },
  );

  testWidgets(
    'empty nearby and recommendation results stay in their sections',
    (tester) async {
      await _pumpDashboard(tester, nearby: const [], recommendations: const []);

      expect(find.byKey(const ValueKey('nearby-empty')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recommendations-empty')),
        findsOneWidget,
      );
    },
  );

  testWidgets('nearby and recommendation loading states render independently', (
    tester,
  ) async {
    final nearbyCompleter = Completer<ApiDiscoveryPage>();
    final recommendationCompleter = Completer<ApiDiscoveryPage>();

    await tester.pumpWidget(
      _testApp(
        ApiHomeDashboard(
          profile: _profile(),
          profileCompletion: 65,
          onEditProfile: () {},
          onSeeAll: () {},
          locationSharingLoader: () async => true,
          radiusLoader: () async => 25,
          interestsLoader: () async => const [],
          nearbyLoader: (_, _) => nearbyCompleter.future,
          recommendationLoader: (_) => recommendationCompleter.future,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('nearby-loading')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recommendations-loading')),
      findsOneWidget,
    );

    nearbyCompleter.complete(
      const ApiDiscoveryPage(profiles: [], hasMore: false),
    );
    recommendationCompleter.complete(
      const ApiDiscoveryPage(profiles: [], hasMore: false),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('nearby API failure has an inline retry', (tester) async {
    var calls = 0;
    await _pumpDashboard(
      tester,
      nearbyLoader: (_, _) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return ApiDiscoveryPage(
          profiles: [_candidate('retry')],
          hasMore: false,
        );
      },
      recommendations: [_candidate('recommendation')],
    );

    final error = find.byKey(const ValueKey('nearby-error'));
    expect(error, findsOneWidget);
    await tester.tap(
      find.descendant(of: error, matching: find.text('Try again')),
    );
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.byKey(const ValueKey('nearby-retry')), findsOneWidget);
  });

  testWidgets('location disabled never requests nearby profiles', (
    tester,
  ) async {
    var nearbyCalls = 0;
    await _pumpDashboard(
      tester,
      locationEnabled: false,
      nearbyLoader: (_, _) async {
        nearbyCalls++;
        return const ApiDiscoveryPage(profiles: [], hasMore: false);
      },
      recommendations: [_candidate('c')],
    );

    expect(find.byKey(const ValueKey('location-disabled')), findsOneWidget);
    expect(nearbyCalls, 0);
  });

  testWidgets('location permission denial keeps the enable state visible', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      locationEnabled: false,
      recommendations: [_candidate('c')],
      enableLocation: () async => throw StateError(
        'Location permission is needed for nearby recommendations.',
      ),
    );

    final disabled = find.byKey(const ValueKey('location-disabled'));
    await tester.tap(
      find.descendant(of: disabled, matching: find.text('Use my location')),
    );
    await tester.pumpAndSettle();

    expect(disabled, findsOneWidget);
    expect(
      find.text('Location permission is needed for nearby recommendations.'),
      findsOneWidget,
    );
  });

  testWidgets('layout stays ordered at phone widths, large text, and RTL', (
    tester,
  ) async {
    for (final width in [320.0, 360.0, 411.0, 900.0]) {
      AppLanguageService.selectedCode.value = width == 360 ? 'pa' : 'en';
      AppLanguageService.locale.value = width == 360
          ? const Locale.fromSubtags(
              languageCode: 'pa',
              scriptCode: 'Arab',
              countryCode: 'PK',
            )
          : const Locale('en');
      await tester.binding.setSurfaceSize(Size(width, 2200));
      await _pumpDashboard(
        tester,
        nearby: [_candidate('a'), _candidate('b')],
        recommendations: [_candidate('c')],
        textScaler: width == 320
            ? const TextScaler.linear(1.8)
            : TextScaler.noScaling,
        direction: width == 360 ? TextDirection.rtl : TextDirection.ltr,
      );

      final railBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('nearby-rail')))
          .dy;
      final recommendationTop = tester
          .getTopLeft(find.byKey(const ValueKey('recommendations-list')))
          .dy;
      expect(recommendationTop, greaterThan(railBottom));
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('missing photo fallback and interest state work in nearby rail', (
    tester,
  ) async {
    var sentTo = '';
    final profile = _candidate('interest', name: 'Amina');
    await _pumpDashboard(
      tester,
      nearby: [profile],
      recommendations: [_candidate('c')],
      interestSender: (profileId) async {
        sentTo = profileId;
        return Interest(
          id: 'interest-row',
          senderId: 'viewer',
          receiverId: profileId,
        );
      },
    );

    expect(find.text('A'), findsWidgets);
    final card = find.byType(ApiNearbyProfileCard);
    final interestButton = find.descendant(
      of: card,
      matching: find.byTooltip('Send interest'),
    );
    await tester.tap(interestButton);
    await tester.pumpAndSettle();

    expect(sentTo, 'interest');
    expect(
      find.descendant(of: card, matching: find.byTooltip('Interest sent')),
      findsOneWidget,
    );
  });

  testWidgets('see all and candidate taps use the supplied navigation paths', (
    tester,
  ) async {
    var seeAllCount = 0;
    CandidateProfile? opened;
    await _pumpDashboard(
      tester,
      nearby: [_candidate('near')],
      recommendations: [_candidate('recommended')],
      onSeeAll: () => seeAllCount++,
      openCandidate: (profile) async => opened = profile,
    );

    await tester.tap(find.byKey(const ValueKey('see-all-Nearby Profiles')));
    expect(seeAllCount, 1);

    await tester.tap(find.text('Member near, 27'));
    await tester.pumpAndSettle();
    expect(opened?.id, 'near');
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  List<CandidateProfile> nearby = const [],
  List<CandidateProfile> recommendations = const [],
  HomeNearbyLoader? nearbyLoader,
  bool locationEnabled = true,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  VoidCallback? onSeeAll,
  Future<Interest> Function(String)? interestSender,
  Future<void> Function(CandidateProfile)? openCandidate,
  Future<void> Function()? enableLocation,
}) async {
  await tester.pumpWidget(
    _testApp(
      ApiHomeDashboard(
        profile: _profile(),
        profileCompletion: 65,
        onEditProfile: () {},
        onSeeAll: onSeeAll ?? () {},
        locationSharingLoader: () async => locationEnabled,
        radiusLoader: () async => 25,
        interestsLoader: () async => const [],
        nearbyLoader:
            nearbyLoader ??
            (_, _) async => ApiDiscoveryPage(profiles: nearby, hasMore: false),
        recommendationLoader: (_) async =>
            ApiDiscoveryPage(profiles: recommendations, hasMore: false),
        interestSender: interestSender,
        openCandidate: openCandidate,
        enableLocation: enableLocation,
      ),
      textScaler: textScaler,
      direction: direction,
    ),
  );
  await tester.pumpAndSettle();
}

Widget _testApp(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: NisaTheme.light,
  home: MediaQuery(
    data: MediaQueryData(textScaler: textScaler),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(body: child),
    ),
  ),
);

UserProfile _profile() => UserProfile(
  uid: 'viewer',
  name: 'A very long member name that still needs to fit',
  gender: 'Female',
  dateOfBirth: DateTime(1995, 1, 1),
  city: 'Lahore',
  country: 'Pakistan',
  maritalStatus: 'Never Married',
);

CandidateProfile _candidate(String id, {String? name}) => CandidateProfile(
  id: id,
  name: name ?? 'Member $id',
  age: 27,
  gender: 'Male',
  city: 'Lahore',
  country: 'Pakistan',
  education: 'Graduate',
  profession: 'Engineer',
  height: "5'10\"",
  maritalStatus: 'Never Married',
  verified: true,
  recommendationReasons: const ['Preferred age range'],
);
