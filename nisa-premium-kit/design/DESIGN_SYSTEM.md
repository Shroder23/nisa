# Design system — Quiet elegance

## Direction

An understated, trustworthy matrimonial service. Keep Option B's information hierarchy and improve refinement through spacing, alignment, typography and surface quality. Premium describes craftsmanship; do not introduce subscription tiers, exclusive-access claims, crowns or VIP badges.

## Tokens

| Token | Value | Use |
|---|---|---|
| Plum | #482438 | Brand header, primary actions, selected controls |
| Canvas | #FAF7F2 | Warm ivory page background |
| Surface | #FFFDFC | Cards, sheets, fields |
| Blush | #F2E6E8 | Welcome surface, selection backgrounds |
| Champagne | #B59463 | Decorative botanical mark, tiny accents only |
| Ink | #29232A | Body and heading text |
| Muted | #70666D | Supporting readable text |
| Border | #E4DAD6 | Nonessential surface dividers |

Gold is not a body-text color or a status claim. Low-contrast borders cannot be the only signal identifying an essential control: retain a visible label and an adequate control boundary/focus state. Error, warning and success use the existing semantic palette, not gold or plum for all states.

## Geometry

- Baseline artboard: 390 × 844 logical pixels. Export ideally 1170 × 2532; if unavailable, use the closest supported portrait canvas and record its size. Never stretch to fake the ratio.
- System insets are runtime-dependent. Reference layout allocations are not fixed constraints.
- Horizontal page gutter 20; on 320-wide screens 16 where needed. Center content on tablets, with sensible max widths (forms about 600; multi-column browse about 1120).
- Spacing scale: 4, 8, 12, 16, 20, 24, 32, 48.
- Surface radius 20; field/button 14; sheet/dialog 24; images 12–16.
- Buttons minimum 52 high, touch targets minimum 48 × 48. Increase height when text wraps.
- Border width 1; shadows very restrained. No luminous glows, glass blur, heavy bevels or simulated gold foil.
- Home rail: three compact cards at normal width; minimum card width about 112, gap 12. Use horizontal scrolling as width decreases. Cards may grow for larger type.
- Recommendation row: 80 × 80 thumbnail, 14 gap to text, 12 inside padding; natural card height. Large type can reflow image/actions above information.

## Typography

Brand/large editorial title may use an approved bundled serif. Interface typography remains a readable sans family with script-appropriate fallbacks. The code retains the application's existing fonts until licensed font assets are explicitly added.

Suggested sizes: brand 24/30, page title 24/32, section heading 18/26, body 16/24, supporting text 14/20, labels 12/18. Use 600 for emphasis rather than making everything bold. No letter spacing on joined scripts. Do not use stylized English serif fonts for Urdu or Punjabi.

Do not download fonts at runtime. If adding fonts, include their license and pubspec declarations and verify Urdu, Arabic, Punjabi and Latin coverage.

## Header and navigation

Home: deep plum brand header, menu, brand mark/wordmark, bell. Root tabs use coordinated headers. Nested forms and details use a back arrow and clear page title; avoid showing a redundant hamburger and bell everywhere. Welcome/login have no authenticated navigation.

Five root destinations remain Home, Search, Matches, Messages, Profile. Use one navigation owner. Nested full-screen routes follow the app's current back stack; do not add a second bottom bar merely because a generated reference includes it.

## Home layout

1. Brand header with real notification state.
2. Blush welcome card: real avatar, localized greeting, real name, short service copy.
3. Nearby section heading and See all; horizontal rail.
4. 24-pixel breathing space, hairline separator, 24-pixel space.
5. Recommendations heading and list of compact horizontal cards.
6. Persistent root navigation with content clear of its inset.

Remove the heavy outline around the entire nearby block; retain subtle borders on individual cards. Restrict botanical ornament to a tiny mark or a faint corner accent. No profile-completion panel inserted into Home; place completion/verification actions in Profile as appropriate to the existing product.

## Content and states

In design references, use empty warm-gray image rectangles and neutral text bars. Keep structural labels readable. Do not draw human-shaped placeholders, sample names, ages, cities, professions, online indicators, distances, badges, chat messages or metrics.

In the live app, loading bars appear only while loading. A missing image uses an image-unavailable fallback, an empty list has honest copy and a relevant action, and a failed request has retry feedback. Nearby, recommendations and messages maintain their own states.

Never infer verification from an uploaded document. A shield illustration must not imply approval. Avoid unsupported promises such as '100% secure' or 'end-to-end encrypted'. Use policy-reviewed wording for document handling. Use the official Google sign-in asset and permitted styling; never ship a generated lookalike G.

## Interaction and motion

Use restrained 160–220ms transitions for selection, sheets and progress; honor reduced-motion settings. Provide pressed, focused, disabled and loading states. Busy heart actions prevent duplicate requests. Avoid perpetual shimmer after failure. Accessible text describes the actual interest action, not just 'heart'.

## Image-reference limitations

The presentation boards are not dimensionally exact engineering artifacts. Do not copy their compressed proportions, generated typography mistakes, button labels, security copy, Google marks or arbitrary navigation placement blindly. The individual screen specifications and real application behavior take priority. Validate the final render on devices.
