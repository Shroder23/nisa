import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nisa_e_sakina/presentation/nisa_premium/nisa_premium.dart';

Widget host(Widget child, {double scale = 1, bool rtl = false}) => MaterialApp(
  theme: NisaPremiumTheme.apply(ThemeData(useMaterial3: true)),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(body: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('narrow RTL large text keeps rail above recommendation section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        NisaPremiumHomeBody(
          welcome: const NisaWelcomeCard(
            greeting: 'Greeting',
            name: '',
            subtitle:
                'Interface text that must wrap safely at large text sizes.',
            avatar: NisaPhotoFallback(label: 'Unavailable image'),
          ),
          nearbyHeading: const NisaSectionHeading(title: 'Nearby profiles'),
          nearbyContent: NisaNearbyRail(
            key: const ValueKey('rail'),
            empty: const SizedBox.shrink(),
            children: List.generate(
              3,
              (_) => NisaProfileCard(
                title: 'Neutral content slot with deliberately long text',
                location: 'Neutral secondary text slot',
                photo: const NisaPhotoFallback(label: 'Unavailable image'),
                openLabel: 'Open record',
                onOpen: () {},
                compact: true,
              ),
            ),
          ),
          recommendationHeading: const Text(
            'Recommendations',
            key: ValueKey('heading'),
          ),
          recommendationCount: 0,
          recommendationBuilder: (_, _) => const SizedBox.shrink(),
          recommendationEmpty: const Text('No results'),
        ),
        scale: 2,
        rtl: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final rail = tester.getRect(find.byKey(const ValueKey('rail')));
    final heading = tester.getRect(find.byKey(const ValueKey('heading')));
    expect(heading.top, greaterThanOrEqualTo(rail.bottom));
  });

  testWidgets('profile action does not also open the profile', (tester) async {
    var opens = 0;
    var actions = 0;
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 152,
            child: NisaProfileCard(
              title: 'Content slot',
              openLabel: 'Open record',
              onOpen: () => opens++,
              photo: const NisaPhotoFallback(label: 'Unavailable image'),
              actionLabel: 'Send interest',
              actionIcon: Icons.favorite_border,
              onAction: () => actions++,
              compact: true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Send interest'));
    expect(actions, 1);
    expect(opens, 0);
  });

  testWidgets('busy interest action cannot submit again', (tester) async {
    var actions = 0;
    await tester.pumpWidget(
      host(
        NisaProfileCard(
          title: 'Content slot',
          openLabel: 'Open record',
          onOpen: () {},
          photo: const NisaPhotoFallback(label: 'Unavailable image'),
          actionLabel: 'Send interest',
          actionIcon: Icons.favorite_border,
          onAction: () => actions++,
          actionBusy: true,
        ),
      ),
    );
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
    expect(actions, 0);
  });

  testWidgets('empty rail renders honest supplied empty state', (tester) async {
    await tester.pumpWidget(
      host(
        const NisaNearbyRail(empty: Text('No nearby results'), children: []),
      ),
    );
    expect(find.text('No nearby results'), findsOneWidget);
    expect(find.byType(NisaProfileCard), findsNothing);
  });
}
