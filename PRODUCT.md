# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

A small, known circle of friends and family — people who already know each other in real
life — using Cro as a slower, deliberate way to stay in touch. Not an open public app for
strangers to sign up into; the friends system, small hub-suggestion moderation queue, and
fixed dev-seeded accounts all assume a known, trusted group rather than anonymous scale.

## Product Purpose

Cro is a messaging app where users send "cro's" (birds) to other users. Unlike instant
messaging, each cro travels across a map in real time and takes physical days to arrive
rather than delivering instantly. Success is defined in two stages, in order: first, a
personal/portfolio project demonstrating solid architecture, CI/CD, and craft; second — once
that bar is met — real, regular usage by its friend circle sending cro's to each other.

## Positioning

The mechanism a neighboring messaging app could not truthfully copy without becoming a
different product: delivery is deliberately slow and physically simulated (a cro travels a
real map over real days), not instant. That travel time is the product's point, not a
limitation to engineer away.

## Operating Context

- **Nests**: physical waypoint locations a user places on the map (up to 5 per user); cro's
  depart from and arrive at nests.
- **Hubs**: app-curated public landmark nests with their own message board; users can suggest
  a hub, and admins moderate a suggestion queue before it goes live.
- **Friends**: a request/accept relationship gates who can send cro's to whom.
- **Birds**: the cro's/messages themselves, sendable between friends, reactable, and visible
  in transit on the map in real time.
- Web is the single, unconditional UI (`WebShellScreen`) across every platform Cro builds
  for — there is no separate mobile-optimized UI anymore. Linux and Windows desktop builds
  still exist and run, but render the same web-first UI rather than a platform-specific one.
- Backend is a real deployed system, not just local/demo: a real Azure Cosmos DB + Blob
  Storage account (`croappstorage`, `cro-prod` resource group) is provisioned and deployed
  via an Azure CD pipeline, alongside local Cosmos/Azurite emulators for dev and CI.

## Capabilities and Constraints

- Account creation requires email verification and enforces one email per user.
- Profile pictures and other user-uploaded images go through Azure Blob Storage.
- Admins (`IsAdmin`) moderate the suggested-hubs queue.
- Configured build platforms are Linux, Windows, and Web — no iOS/macOS/Android scaffolding
  currently exists.

## Brand Commitments

- Product terminology is fixed and load-bearing: **cro** (the message/bird), **nest**
  (a user's waypoint location), **hub** (an app-curated public nest), **waypoint** (the
  underlying map location concept), **bird** (the traveling cro). Preserve this vocabulary
  rather than introducing synonyms.
- A fixed 8-color brand palette (`CroColors`) is already wired into a real `ColorScheme`/
  `ThemeData` (`app/lib/theme.dart`) — Background, Surface, Waypoint blue (primary), Deep
  waypoint (secondary), Sky tint, Ink, Fog, Delivery amber (tertiary). This is confirmed,
  binding visual system, not open for reinvention.

## Evidence on Hand

No real customers, testimonials, press, or case studies exist yet — this is a
friends-and-family-stage product. Local/dev data is a fixed 5-account seeded dataset
(`Admin`, `Test1`, `Test2`, `Oliver`, `Annie`) used for development and testing only; future
work must not present it as real evidence or real users.

## Product Principles

- Deliberateness over instancy: the real-time, multi-day travel mechanic is the core
  differentiator — never shortcut it toward instant delivery for convenience.
- Design for a known circle, not anonymous scale: trust, moderation, and onboarding
  assumptions should fit friends who already know each other, not strangers.
- Craft is a first-class goal, not a nice-to-have: this project doubles as a portfolio piece,
  so architecture, CI/CD, and UX quality matter alongside feature velocity.
- Once the craft bar is met, design for real regular usage by the friend circle — not just a
  demo that looks good once.

## Accessibility & Inclusion

No product-specific accessibility standard has been established beyond general basics
(contrast, tap-target size, readable text) already called out as a working default in
CLAUDE.md's designer/UX mindset guidance.
