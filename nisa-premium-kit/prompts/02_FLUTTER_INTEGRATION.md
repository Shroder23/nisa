# Codex / Antigravity — integrate the approved designs

Implement the approved Nisa e Sakina visual redesign in the current Flutter app. This is presentation work, not a rewrite of the backend or product behavior. Read this kit's design system, screen recipes and approved reference images. The source map is based on an older local snapshot: inspect current routes before editing.

## Working scope

Preserve uncommitted work. Inspect AGENTS.md, current entry points, active theme, route ownership, localization, photo privacy, controllers and service contracts. Find which screens are active versus legacy. Keep a screen-by-screen checklist with route, file, implementation and verification status. Do not stop after changing ThemeData or Home.

The user's latest request prioritizes cleaner premium styling over literal replication of every detail in the old B image. Preserve B's structure; use the new tokens and approved individual designs for final appearance. Design boards illustrate style, not exact viewport geometry.

## Integrate the supplied code

Copy `flutter/lib/presentation/nisa_premium/` into `lib/presentation/nisa_premium/`. Apply `NisaPremiumTheme.apply(existingTheme)` at the active MaterialApp. Preserve fonts, delegates, locale, navigator, routes, providers and startup flags. The supplied code uses modern Flutter APIs matching the inspected source's CardThemeData/DialogThemeData/WidgetStateProperty usage. Confirm compatibility with the actual installed SDK instead of upgrading the project blindly.

Use NisaBrandAppBar on Home with real menu and notification callbacks; pass the app's real notification badge widget and brand mark. Use appropriate contextual headers elsewhere. Keep the existing five-tab shell, PageView/controller and large-screen navigation. Avoid duplicate Scaffold/AppBar/navigation ownership.

Replace the active Home body composition with NisaPremiumHomeBody. Supply the real welcome card, separate nearby state/rail and real recommendation list. Use NisaProfileCard with the real model's formatted title, fields, existing privacy-aware photo widget and existing callbacks. For compact rail cards, `compact: true`; for rows, `compact: false`.

These widgets contain no business logic. Do not pass empty callbacks merely to make the design look connected. Null callbacks must reflect a real disabled state. Translate labels through the existing localization service before passing them. Do not globally replace the existing photo widget with Image.network.

The provided Home component has one vertical CustomScrollView and a naturally sized horizontal rail; it cannot overlap the next section through a hardcoded floating offset. Keep requests outside build, preview rails small, recommendations lazy, and current pagination semantics intact. Wire the existing load-more trigger or add a compatible controller hook if required; the starter component itself does not implement API pagination.

## Make every reachable screen consistent

Use `design/SCREEN_CATALOG.md`, individual screen recipes and `design/SOURCE_MAP.csv`. Reconcile missing or new routes from the latest code. Apply the same components to all reachable member, family, verification, privacy and role-specific screens. Preserve security distinctions and role guards.

Keep forms functional, validation visible, fields keyboard-aware and primary actions reachable. Retain focus order, submission state, save/cancel behavior and unsaved-change handling. Keep official Google sign-in branding; do not use a generated G. Match document-upload copy to the actual policy and avoid unsupported security promises.

Do not add subscriptions, VIP membership, onboarding steps, chat features, fake approvals or new matching logic just because a mockup suggests them. For conceptual screens without an existing route, implement only when required by an existing workflow; otherwise mark them as optional design coverage.

## Real data only

Never introduce demo profiles, stock member photos, hardcoded counts, sample chats or artificial distances. In development screenshots use a separate design-only preview with neutral empty slots, not seed data in the database. In production use actual records, loading skeletons only during loading and honest empty/error states otherwise.

The heart must retain its existing meaning. If it sends interest, label and handle it as interest; do not turn it into favorites. Keep request deduplication, error feedback and state updates. If integration reveals a broken feature, repair presentation/navigation wiring within scope; document a backend gap before making unrelated server changes.

Keep location permission, approximate-location privacy, independent nearby/recommendation loading and retry behavior. Do not display exact coordinates. Keep Google OAuth/client-ID flags, session handling and API contracts unchanged. Do not treat all 401/403 responses as password-reset requirements.

## Accessibility and localization

Preserve large text rather than forcing textScaleFactor=1. Reflow at 320 logical pixels and at 2× text scaling. Use Directional padding/alignment and correct RTL navigation. Long labels can wrap; do not clip functional information merely to retain a compact screenshot. Verify Punjabi locale mapping instead of aliasing it to Hindi. Use script-compatible fonts and actual translation resources.

Use readable text contrast, keyboard focus indicators and touch targets of at least 48 logical pixels. Gold is decorative, not body text. Essential field borders need sufficient contrast or another clear boundary cue. Run contrast checks on tokens and rendered components.

## Validation and completion

Copy the included widget tests into test/ and adapt only package imports if needed. Run formatter, flutter analyze, appropriate existing tests and the new layout tests. Capture the real app at small/standard/large phone widths, normal/large text and RTL. Compare each implemented screen to its individual approved reference. Correct spacing, cropping, typography and hierarchy differences instead of merely reporting them.

Test loading, empty, retry, missing image, permission denied, keyboard-open and disabled/busy states. Check that every visible control retains its real action and route. Do not claim that an image mockup proves runtime functionality. Distinguish pre-existing failures from regressions.

Provide the completed screen checklist, changed files, actual screenshots, test commands/results and remaining blockers. If SDK, device or backend access is absent, say exactly which checks were not run and complete independent work. Do not claim this starter kit is already compiled or integrated.

Do not deploy, restart production services, change production database records or reset accounts for this design task. Use local or isolated test environments. Proceed through implementation without repeated approval requests for routine reversible design decisions.
