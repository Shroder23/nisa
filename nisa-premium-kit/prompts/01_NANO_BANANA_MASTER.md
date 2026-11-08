# Nano Banana 2 — master art direction

Use this prompt with one screen recipe from `screens/`. Attach the original B reference for Home. After approving Home, attach the approved Home image for subsequent screens.

---

You are designing the visual interface for Nisa e Sakina, an existing Pakistani matrimonial application. Generate an implementation-ready visual reference for the requested screen. This task is DESIGN ONLY.

REFERENCE PRIORITY

Use only the middle design labeled B — Nearby Rail from the original comparison. Preserve its Home hierarchy: brand header, welcome card, horizontal nearby rail, separate vertical recommendations, five-tab navigation. Improve refinement and clarity. Do not use Option A's ordering or Option C's dashboard grid.

For subsequent screens, use the approved redesigned Home image as the visual style anchor, but use the supplied screen recipe for layout and functionality.

STYLE

Quiet, premium, elegant, warm and trustworthy. Warm ivory #FAF7F2 background; off-white #FFFDFC surfaces; deep plum #482438 primary; blush #F2E6E8 secondary surfaces; champagne #B59463 as a very limited decorative accent; ink #29232A; muted #70666D; subtle border #E4DAD6.

Use generous intentional whitespace, precise alignment, matte flat surfaces, subtle borders, little or no shadow, consistent outlined icons, gently rounded cards. Brand typography can be editorial serif; functional labels must use highly legible sans typography. No heavy gradients, gold foil, neon glow, glassmorphism, crowns, VIP badges, ornamental wallpaper, exaggerated shadows, floating decoration or excessive cards within cards.

DESIGN ONLY — NO FAKE PROFILES

No people, photographs, faces, silhouettes, invented names, ages, cities, occupations, biographies, distances, verification claims, online status, message contents, unread counts, statistics or testimonials. Data-bearing areas use blank neutral image slots and unobtrusive gray bars. Structural text such as Search, Nearby profiles, Filters and Save changes must remain readable. Form values stay empty. These are design annotations, not fake app data.

Do not use the names or portraits from the reference. Do not imply that an empty API state contains members. Never use placeholder imagery as production profile photos.

GEOMETRY

Create one straight-on, flat portrait screen, not a collage. Target 390 × 844 logical-pixel proportions; export at the highest supported portrait resolution, ideally 1170 × 2532. If that exact canvas is unsupported, use the closest portrait ratio without stretching and state the actual dimensions in accompanying text if supported.

Use approximately 20-pixel page gutters, spacing increments of 4/8/12/16/20/24/32, 20-pixel card radii, 14-pixel controls and 24-pixel sheets. Controls must accommodate at least 48-pixel touch targets. No tiny text. Reserve realistic system and keyboard insets when relevant, without drawing a phone frame or notch.

CONTENT HIERARCHY

One clear primary action per task. Give forms visible labels. Use a back arrow for nested screens; use the menu only where the application has a root drawer. Welcome/login must not have authenticated navigation. The five-tab bar belongs to the root shell, not every modal or nested page.

STATE CONSISTENCY

Use only the state specified in the screen recipe. Distinguish a neutral design placeholder, a loading skeleton and a genuine empty state. Do not invent counts or statuses. Do not put a success checkmark on a pending or unverified state. No security claims or policy language unless supplied. Do not redraw third-party logos: use a neutral reserved logo slot for the official Google sign-in asset.

OUTPUT

Generate exactly one screen image for this request. No surrounding marketing board, device frame, perspective, arrows, code, fake file list or watermark. Where the interface allows naming, use the filename in the screen recipe. If it cannot create a named downloadable file, produce the image and let the user save it under that name; do not claim a file was written.

UI text and controls will be rendered in Flutter. The image is a reference, not a flattened production screen. Do not promise Dart files, editable Figma layers, SVG vectors, source-code ZIPs or tested integrations from an image-generation step.

Before finishing, visually check consistency with the approved Home reference, clipping, spacing, legibility, and the prohibition on invented member content.

NOW APPLY THE ATTACHED SCREEN RECIPE.

---

## Reusable revision prompt

Keep the approved colors, typography, radii and layout hierarchy unchanged. Correct only these discrepancies: [list specific discrepancies]. Preserve blank data placeholders. Output the revised single portrait screen. Do not introduce new sections or people.

## Optional decorative asset request

Create a subtle botanical corner ornament for Nisa e Sakina in matte champagne and muted blush, thin clean strokes, no text, no faces, no background scene. Leave ample negative space. Output a separate image with a genuinely transparent background if supported; otherwise provide a plain background and state transparency was not produced. Do not bake the ornament into a full-screen background. Flutter must draw typography, icons, cards and controls itself.

Filename: botanical_corner.png. Ask the coding agent to inspect its actual alpha channel before integrating. A checkerboard painted into pixels is not transparency.
