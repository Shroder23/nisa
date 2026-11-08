import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nisa_e_sakina/widgets/api_profile_photo.dart';

void main() {
  testWidgets('API profile photos preserve the member initial fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ApiProfilePhoto(fallbackText: 'Shamiq', radius: 24),
        ),
      ),
    );

    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('API profile photos preserve the person icon fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ApiProfilePhoto(radius: 24))),
    );

    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}
