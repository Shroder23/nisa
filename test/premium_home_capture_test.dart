import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nisa_e_sakina/presentation/nisa_premium/nisa_premium.dart';
import 'package:nisa_e_sakina/theme/nisa_theme.dart';

import 'premium_screen_catalog_test.dart' show loadFonts;

void main() {
  if (!const bool.fromEnvironment('NISA_CAPTURE_CATALOG')) return;
  testWidgets('capture neutral Home composition', (tester) async {
    await loadFonts(tester);
    for (final width in [360.0, 411.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      Widget slot(bool compact) => NisaProfileCard(
        title: '',
        openLabel: 'Design-only empty slot',
        onOpen: () {},
        compact: compact,
        photo: const NisaPhotoFallback(label: 'Photo unavailable'),
        actionLabel: 'Send interest',
        actionIcon: Icons.favorite_border,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: NisaPremiumTheme.apply(NisaTheme.light),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              appBar: NisaBrandAppBar(
                title: 'Nisa e Sakina',
                menuLabel: 'Menu',
                onMenu: () {},
                notificationLabel: 'Notifications',
                onNotifications: () {},
                brandMark: const Icon(
                  Icons.favorite,
                  color: NisaPremiumTheme.gold,
                ),
              ),
              body: NisaPremiumHomeBody(
                welcome: const NisaWelcomeCard(
                  greeting: 'Welcome back',
                  name: '',
                  subtitle: 'Find a meaningful connection.',
                  avatar: NisaPhotoFallback(label: 'Photo unavailable'),
                ),
                nearbyHeading: NisaSectionHeading(
                  title: 'Nearby Profiles',
                  icon: Icons.location_on,
                  actionLabel: 'See all',
                  onAction: () {},
                ),
                nearbyContent: NisaNearbyRail(
                  empty: const SizedBox(),
                  children: List.generate(3, (_) => slot(true)),
                ),
                recommendationHeading: const NisaSectionHeading(
                  title: 'Recommended for you',
                  icon: Icons.star_rounded,
                ),
                recommendationCount: 3,
                recommendationBuilder: (_, _) => slot(false),
                recommendationEmpty: const SizedBox(),
              ),
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
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
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final picture =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/premium-screens/home-neutral-${width.toInt()}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
