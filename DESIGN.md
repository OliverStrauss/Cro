---
name: Cro — Radio Log
description: A station-logbook world for a messaging app whose messages travel real days across a real map.
colors:
  waypoint-blue: "#5CB6E3"
  deep-waypoint: "#2A7194"
  sky-tint: "#BFE4F4"
  ink: "#2B2F33"
  fog: "#6B7280"
  delivery-amber: "#F3AA5E"
  background: "#D4D7DC"
  surface: "#FFFFFF"
  warm-surface: "#F4F2ED"
  alt-surface: "#F9F8F5"
  amber-ink: "#A2521F"
  success: "#4FA97C"
  alert-away: "#E8714A"
  hairline: "rgba(43, 47, 51, 0.14)"
typography:
  data:
    fontFamily: "IBM Plex Mono, monospace"
    fontSize: "11.5px"
    fontWeight: 500
    letterSpacing: "0.2px"
  label:
    fontFamily: "IBM Plex Mono, monospace"
    fontSize: "11px"
    fontWeight: 600
    letterSpacing: "0.8px"
  stamp:
    fontFamily: "IBM Plex Mono, monospace"
    fontSize: "10px"
    fontWeight: 700
    letterSpacing: "1.3px"
  body:
    fontFamily: "IBM Plex Sans, sans-serif"
    fontWeight: 400
rounded:
  sm: "3px"
  md: "4px"
spacing:
  hairline-width: "1px"
components:
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.md}"
  button-primary:
    backgroundColor: "{colors.waypoint-blue}"
    textColor: "{colors.surface}"
    rounded: "{rounded.md}"
  button-outlined:
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
---

<!-- Platform note: this is a Flutter app (web/desktop), not CSS/HTML. Tokens above map to
app/lib/theme.dart's CroColors/CroTextStyles/CroBorders constants, not stylesheet values.
No .impeccable/design.json sidecar accompanies this file - that sidecar's schema (HTML/CSS
component snippets for a browser shadow-DOM live panel) has no Flutter equivalent, and
fabricating placeholder markup would misrepresent what was actually built. Read
app/lib/theme.dart directly for the authoritative, type-checked token definitions. -->

# Design System: Cro — Radio Log

## Overview

**Creative North Star: "The Station Log"**

Cro's mechanism is a message that physically flies across real distance over real days —
the opposite of an instant chat bubble. Radio Log takes that literally: the app reads as a
ham-radio operator's logbook and QSL-card ritual, where every contact across distance is
proven, timestamped, and worth a hand-stamped confirmation. This replaces the rounded-bubble,
soft-shadow, Quicksand-headline messaging-app look every prior version of this app shared with
its whole category — the explicit complaint this redesign was commissioned to fix.

Density stays moderate and utilitarian: this is an Operate-mode surface (a map, a dock, panels
of state), not a marketing page, so legibility and scanability always outrank expression. Depth
comes from ruled hairline edges, not blur; color stays restrained, confined to a handful of
named roles instead of scattered accents; every short label, button, coordinate, timestamp, and
distance reads in one tracked monospace voice, as if it came off an instrument.

**Key Characteristics:**
- Hairline-bordered, boxy (4px radius) plates instead of soft-shadow rounded cards
- One data/label voice (IBM Plex Mono, tracked) for every short instrumental string; prose
  stays in IBM Plex Sans
- Color is restrained: amber is reserved for hand-stamped "confirmed/admin" moments, never a
  filled background field
- State reads in more than color alone where it matters (a bird's dock card border widens
  while it's actually in flight)

## Colors

The existing 8-color CroColors brand palette is unchanged and load-bearing (see PRODUCT.md) —
this redesign is a material/typography/shape shift on top of it, not a palette replacement.

### Primary
- **Waypoint Blue** (`#5CB6E3`): primary actions, live/in-transit state, selection.

### Secondary
- **Deep Waypoint** (`#2A7194`): headers, pressed states, secondary text-links (Rename,
  Unblock, Send request).

### Tertiary
- **Delivery Amber** (`#F3AA5E`) / **Amber Ink** (`#A2521F`): the hand-stamped
  confirm/admin/arrival accent. Used sparingly — a hairline border or the CroTextStyles.stamp
  text color, never a filled background field.

### Neutral
- **Ink** (`#2B2F33`): primary text, and — at 14% alpha — every hairline rule and border.
- **Fog** (`#6B7280`): secondary text, timestamps, disabled labels.
- **Background** (`#D4D7DC`): app canvas.
- **Surface** (`#FFFFFF`): cards, panels, plates.
- **Sky Tint** (`#BFE4F4`): in-transit highlight wash.
- **Warm Surface / Alt Surface** (`#F4F2ED` / `#F9F8F5`): delivered-mail and payload-card
  backgrounds.

### Named Rules
**The Hairline Rule.** Every card, button, dialog, and input border is `ink` at 14% opacity,
1px wide (`CroBorders.hairline`/`hairlineSide`) — one weight of line everywhere, not a dozen
independently-tuned grays or a soft drop shadow standing in for an edge.

**The Amber Restraint Rule.** Delivery amber marks a confirmed, arrived, or admin moment. It
never fills a background field or a large surface; it lives in a stamp's text color or a
hairline border only.

## Typography

**Display/Label Font:** IBM Plex Mono (with monospace fallback)
**Body Font:** IBM Plex Sans (with sans-serif fallback)

**Character:** A logbook's instrument voice (tracked monospace) for everything short and
factual — labels, buttons, badges, coordinates, timestamps, distances — paired with a plain
humanist sans for actual prose (messages, descriptions, dialog copy), so the data voice never
has to carry a sentence.

### Hierarchy
- **Title** (IBM Plex Mono, w700/w600, tracked 0.2–0.3px): screen and panel headings, the "Cro"
  wordmark.
- **Label** (IBM Plex Mono, w600, tracked 0.6–0.8px): every button, nav item, chip, and
  short action link — this is `ThemeData.textTheme.labelLarge/Medium/Small`, so it's also what
  every stock `ElevatedButton`/`OutlinedButton`/`TextButton`/`Chip` picks up automatically.
- **Data** (IBM Plex Mono, w500, tracked 0.2px, `CroTextStyles.data`): coordinates, distances,
  timestamps, meta lines — read-only instrument values.
- **Stamp** (IBM Plex Mono, w700, tracked 1.3px, `CroTextStyles.stamp`): the amber
  confirmed/arrived mark specifically.
- **Body** (IBM Plex Sans, default Material weights): message content, descriptions, dialog
  copy, form field text.

### Named Rules
**The One Voice Rule.** A short factual string (a label, a button, a coordinate, a timestamp)
is always set in the Mono data/label voice via `CroTextStyles`, never a bare ad hoc
`TextStyle`. A sentence of prose never is.

## Layout

Flutter widget tree, not CSS — no grid/breakpoint system beyond what already existed
(`LayoutBuilder`'s 840px split in the auth shell). Panel/dock/card padding and gaps are
unchanged from the incumbent layout; this pass changed material and type, not composition.

## Elevation & Depth

Hybrid, weighted toward flat. Resting cards, panels, dialogs, and inputs are flat with a 1px
hairline border (`CroBorders.hairline`) — no ambient shadow. A soft, wide, low-opacity shadow
is reserved for elements that genuinely float over other content (the notifications dropdown,
the context panel, the Your Birds dock, the hidden-dock pill, a bottom sheet, the auth card) —
there, the hairline border still defines the edge and the shadow only adds separation from
what's behind it.

### Named Rules
**The Ruled-Edge Rule.** Depth on a resting surface comes from its hairline border, not a
shadow. A shadow only appears on a surface that visually floats over other content.

## Shapes

Boxy and understated: a single 4px corner radius (`CroBorders.radius`) for cards, buttons,
inputs, and dialogs; 3px (`CroBorders.radiusSmall`) for small chips, tags, and stamps. Avatars
and map-marker dots stay circular (an identity convention, not part of the card language).
Nest map markers stay fully rounded and larger than Hub markers (boxier, radius 11) — a
pre-existing distinction this pass preserved rather than changed.

## Components

### Buttons
- **Shape:** 4px radius (`CroBorders.radius`), no pill shapes anywhere in the app.
- **Primary (`ElevatedButton`):** Waypoint Blue fill, white text, no elevation shadow.
- **Outlined:** Ink at 24% alpha hairline border, ink text.
- **Text:** Deep Waypoint text, no fill.
- All three inherit the Label voice from `ThemeData.textTheme.labelLarge` automatically — a
  bare `ElevatedButton`/`OutlinedButton`/`TextButton` needs no per-call styling to be on-brand.
- A hand-rolled "button" (`Material` + `InkWell` + `Text`, still common for compact inline
  actions like Rename/Delete/Unblock) sets its label explicitly via `CroTextStyles.label` —
  the theme cascade only reaches real Button widgets.

### Chips / Badges
- **Style:** hairline border in the relevant semantic color, no filled background, `CroTextStyles.label` or `.stamp` text. Alert badges (unread counts, "N waiting") are the one
  exception: filled `alertAway`, since they're meant to demand attention.

### Cards / Containers
- **Corner Style:** 4px radius.
- **Background:** Surface white (or Warm/Alt Surface for a payload/delivered-mail card).
- **Border:** 1px hairline (ink @ 14%), or the relevant accent color at selected/highlighted
  state (Waypoint Blue selected nest, Delivery Amber selected hub, per-friend trail color).
- **Shadow:** none at rest; see Elevation & Depth for floating surfaces.

### Inputs / Fields
- **Style:** hairline-bordered rectangle (`CroBorders.radius`), transparent/white fill —
  replaced the prior filled, fully-rounded (12px), borderless pill field on the login/sign-up
  screens.
- **Focus:** border becomes Waypoint Blue at 1.5px.
- **Error:** border becomes the Material error color at 1.2px.

### Navigation (Icon Rail)
- Deep Waypoint background, white icon + Label-voice text per item, unread badges in
  Alert-Away. Unchanged in shape from the incumbent rail; only the label typography moved to
  the Mono/tracked voice.

### Dock Bird Card (signature component)
The "Your birds" dock's per-bird card carries state in two channels at once: its background
tint and border color (existing convention), plus — new in this pass — its border **weight**:
a bird actually in flight gets a 2px border, a settled one (home/away/at a hub) gets 1px. This
is the direction's line-form-carries-state discipline in its smallest, most literal form.

## Do's and Don'ts

### Do:
- **Do** set every short factual string (label, button, coordinate, timestamp, distance) via
  `CroTextStyles.data`/`.label`/`.stamp`, never a bare `TextStyle`.
- **Do** use `CroBorders.hairline()`/`hairlineSide()` and `CroBorders.radius`/`radiusSmall` for
  any hand-rolled `Container`/`BoxDecoration` border — don't invent a new radius or a new
  border alpha per widget.
- **Do** keep amber confined to a stamp's text color or a hairline border.
- **Do** prefer a real `ElevatedButton`/`OutlinedButton`/`TextButton`/`Chip` over a custom
  `Material`+`InkWell` construction where the interaction is a plain button — it gets the
  theme's shape and typography for free.

### Don't:
- **Don't** reintroduce a soft `BoxShadow`-only card border — every resting surface gets a
  hairline border first; a shadow is only for a surface that floats over other content.
- **Don't** fill a badge or chip's background with Delivery Amber — that reads as the
  category-default "orange accent everywhere" this redesign was commissioned to move away
  from. Reserve the fill for genuine alert badges (unread counts), which use `alertAway`, not
  amber.
- **Don't** rename product vocabulary (cro, nest, hub, bird, waypoint) into world-flavored
  synonyms ("station", "contact") in user-facing copy — the visual world dresses the existing
  words, it doesn't replace them (see PRODUCT.md's Brand Commitments).
- **Don't** use Quicksand or Inter anywhere in `/app` — both were fully replaced by IBM Plex
  Mono/Sans, and their font asset files were removed from `assets/fonts/`.
