# Nisa e Sakina — Premium Nearby Rail design kit

Prepared 8 November 2026. Design and presentation code only; no fake profiles.

## What this delivers

- A complete screen-design specification and individual Nano Banana 2 prompts.
- Reusable Flutter theme, Home layout, nearby rail, real-data profile cards, welcome card, section headings and state cards.
- An integration brief for Codex or Antigravity that preserves the application's current behavior.
- A source-screen mapping based on the available repository snapshot.
- Widget tests to run in your Flutter environment.

The two visual boards shown in the conversation are concept illustrations. They are not screenshots of the app, individual production screen assets, or proof of implementation. The written layout specifications take precedence over image-generation inaccuracies. They were generated here, not by Nano Banana 2.

## Start here

1. Open `prompts/01_NANO_BANANA_MASTER.md`. Attach the original comparison image and use **only B** as the structural reference.
2. Generate `prompts/screens/01_home.md` first. Save the approved image as `01_home.png`.
3. For each next screen, provide the master prompt, that screen's prompt and the approved Home image. Generate one full portrait screen per request.
4. Open your actual Flutter project in Codex/Antigravity. Provide this kit, approved screen images and `prompts/02_FLUTTER_INTEGRATION.md`.
5. Integrate the provided Dart files into existing live screens, then run the checks below.

Nano Banana 2 produces image references and raster artwork. A screenshot is not editable Flutter UI; use the coding agent for Dart, routes and integration. Do not add the image-generation API to the matrimonial app for this task.

## Included source and scope

`flutter/lib/presentation/nisa_premium/` contains:

- `nisa_premium_theme.dart`: overlay on the existing theme, retaining its font choices.
- `nisa_premium_widgets.dart`: reusable real-data visual components.
- `nisa_premium_home.dart`: Home brand AppBar and a single-scroll body.
- `nisa_premium.dart`: exports.

These are integration components, not a replacement app. They contain no backend calls, fabricated members or new authentication logic. Secondary-screen designs are specified in individual prompt files; their complete Dart screens are not implemented by this starter kit.

The source map was grounded in local `nisa-latest` commit `3e254f8` (6 November 2026). It is a filesystem inventory, not proof that every legacy route is active. The latest remote changes were not fetched. Reconcile the mapping against the actual current project before integrating.

## First code change

Copy `flutter/lib/presentation/nisa_premium` into your app's `lib/presentation/` directory. In the existing MaterialApp file:

```dart
import 'presentation/nisa_premium/nisa_premium.dart';

// Inside the existing MaterialApp; preserve every other argument:
theme: NisaPremiumTheme.apply(NisaTheme.light),
```

This changes shared styling only. It does not complete the redesign by itself. If `NisaTheme.light` has changed, apply the overlay to the actual active theme. Keep localization delegates, navigator keys, route guards, startup flags and providers intact.

Build `NisaPremiumHomeBody` inside the existing Home tab. Supply existing widgets/data and callbacks. Do not nest a second Scaffold or duplicate navigation. An explicit `labelBehavior` on the current NavigationBar overrides the theme: reconcile that property for visible labels.

## Verification

Flutter and Dart executables were unavailable in the preparation environment. The Dart source and tests have not been compiled or run. No app integration or live API testing is claimed.

In the real project, after integrating:

```powershell
dart format lib/presentation/nisa_premium test/nisa_premium_layout_test.dart
flutter analyze
flutter test test/nisa_premium_layout_test.dart
flutter test
flutter run <your existing device and --dart-define arguments>
```

The final command is a template: retain your current API and Google client-ID flags. Do not paste the angle-bracket placeholder literally.

Inspect Android at 320, 390 and 430 logical-pixel widths; text scaling 1.0, 1.5 and 2.0; RTL; long translations; keyboard-open forms; and actual loading/error/empty states. Do not claim screenshot fidelity until you compare the running app against the approved individual screen.

## No fabricated content

Design images use blank image slots and neutral bars for data-bearing content. In production, render real authorized data. Use skeletons only while loading; show genuine empty or unavailable states otherwise. Never replace empty API results with demo people, fake verification, fake distance, fake messages or fake counts.

## Sources

- Google image-generation documentation: https://ai.google.dev/gemini-api/docs/image-generation
- Flutter themes: https://docs.flutter.dev/cookbook/design/themes
- Flutter accessibility: https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility

See `VALIDATION.md` for exactly what was checked for this package.
