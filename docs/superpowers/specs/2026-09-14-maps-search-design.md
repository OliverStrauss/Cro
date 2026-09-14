# Maps-style search (addresses/businesses + hubs/nests)

## Overview

Add a Google-Maps-style search to the web shell: a search trigger next to the
notification bell that finds real-world addresses/businesses (via geocoding)
plus in-app Hubs and Nests (Waypoints), and pans/zooms the map to whichever
result is picked.

## Goals

- One search entry point, next to the bell, findable the same way on every
  platform (Linux/Windows/Web all share `WebShellScreen` now).
- Search covers three sources at once: real-world places, Hubs, Nests.
- Picking any result pans/zooms the map to it, reusing the existing animated
  camera-move mechanism (the one already used for "zoom to a bird's
  nest/hub" on notification tap) — this applies uniformly to all three
  result types, including plain address/place results.
- Picking a Hub/Nest result also opens that marker's panel content, same as
  tapping the marker directly on the map.
- Picking a Place (geocoded) result drops a transient pin at that location
  (cleared on the next search or map interaction), since there's no real
  Hub/Nest object to anchor to.

## Non-goals

- No new recommendation engine — `HubSuggestionsPanel` already covers
  "recommendations"; this feature is pure findability.
- No fuzzy matching, ranking/relevance tuning, or search history/autocomplete
  beyond what Nominatim and a simple prefix match already give.
- No change to who can see which Hubs/Nests — search only surfaces what the
  caller could already see via `GET /hubs` / `GET /waypoints` /
  `GET /friends/waypoints`.

## Architecture

### Backend: one merged search endpoint

New `GET /search?q=` in `api/Program.cs`, authenticated the same way as the
existing endpoints (`ClaimsPrincipal principal`). Empty/blank `q` returns an
empty result immediately, same behavior as `/users/search`.

Fans out to three sources in parallel and returns:

```
{
  "places": [ { "displayName": ..., "latitude": ..., "longitude": ... } ],
  "hubs":   [ Hub, ... ],
  "nests":  [ Waypoint, ... ]
}
```

- **Hubs/Nests** — add a `SearchByNamePrefixAsync`-style method to the Hub
  and Waypoint repos, copying `CosmosUserRepository
  .SearchByUsernamePrefixAsync`'s existing pattern exactly: case-insensitive
  prefix match, no fuzzy logic. Hub results are scoped to `Status: Approved`
  (same as the existing `GET /hubs` visibility rule); Nest results are
  scoped to the caller's own Waypoint plus friends' Waypoints (same as what
  `GET /waypoints` + `GET /friends/waypoints` already expose) — search must
  never surface a Waypoint the caller couldn't already see.
- **Places** — a new `IGeocodingService` interface with a `NominatimGeocodingService`
  implementation, called server-side (not from the Flutter client). Calling
  from the backend avoids two problems with calling Nominatim directly from
  Flutter web: its usage policy expects a real identifying `User-Agent`,
  which browser JS cannot set, and it keeps the third-party URL out of
  client code entirely.

### Nominatim usage-policy compliance

Nominatim's public instance usage policy caps free use at roughly 1
request/second and asks callers to send a real `User-Agent` identifying the
app (e.g. `CroApp/1.0`, no personal contact info hardcoded into committed
source — if a contact identifier is wanted, source it from config the same
way `MAPTILER_API_KEY` already is, not a literal in the code). The client-side
250ms debounce (see below) keeps real traffic well under that cap at
current scale. Log this as a tech-debt entry in `TECH_DEBT.md`, in the same
spirit as the existing "known dev-only shortcuts" section: once real
traffic grows, this needs either a self-hosted Nominatim instance or a move
to a paid provider (Mapbox was the runner-up choice when this was
scoped — see the design discussion this spec came from).

### Frontend

- `app/lib/services/search_service.dart` — mirrors `friends_service.dart`'s
  `searchUsers`: one `GET /search?q=` call, deserializes into the three
  result lists.
- A new floating search trigger placed next to the bell in the same
  `Positioned` row in `web_shell_screen.dart` (the row currently holding
  `FloatingActionsCluster`). Expands into a text field + dropdown, same
  250ms-debounce pattern as `web_profile_screen.dart`'s friend search.
- The dropdown is sectioned (Places / Hubs / Nests), each section using its
  own icon, matching the existing notification feed's `_FeedLabelChip`
  styling convention rather than inventing a new chip style.
- **Selecting any result** (Place, Hub, or Nest) triggers the same animated
  `MapController.move()` pan/zoom already used for the "zoom to a bird's
  nest/hub" notification-tap flow — this is the one camera-move code path,
  reused for all three result types, not reimplemented per type.
- Additionally, selecting a Hub/Nest result opens that marker's existing
  panel content (`HubPanelContent`/`NestPanelContent`), same as a direct
  map-marker tap.
- Additionally, selecting a Place result drops a transient marker at that
  lat/lng (no panel — there's nothing to show), cleared on the next search
  or on direct map interaction.

## Testing

- xunit: a test for `GET /search` covering hub matches, nest matches
  (including the friends'-nest visibility scope), an empty query, and the
  places passthrough — the places case mocks `IGeocodingService` so the
  test suite never hits the real network.
- Flutter widget test: the search trigger opens a sectioned dropdown and
  renders results from a fake `SearchService`, following the existing
  `webNotificationBell`/`webFriendSearchField`-style `Key(...)` naming
  convention for testability.

## Process notes for implementation

- **Use the project's graphify knowledge graph** (`graphify-out/graph.json`,
  already built for this repo) during implementation to locate the exact
  existing patterns being copied — `CosmosUserRepository
  .SearchByUsernamePrefixAsync`, the notification-tap camera-move code, the
  `_FeedLabelChip` styling, `web_profile_screen.dart`'s debounce pattern —
  via `graphify query "..."` rather than re-deriving them from scratch, and
  to sanity-check no sibling caller of a touched shared function
  (e.g. the Hub/Waypoint repos, `MapController` usage) is missed.
- **Follow this repo's CI practices**: run `flutter analyze` + `flutter
  test` from `/app` and `dotnet build`/`dotnet test` against
  `CroApp.Api.Tests/CroApp.Api.Tests.csproj` from `/api` before considering
  any piece done — matching `flutter-ci.yml`/`dotnet-ci.yml` exactly, since
  both run on every PR. This is a major logic change (new endpoint, new
  repo methods, new UI flow), so per this repo's workflow conventions it
  must ship with tests, not just manual verification.
- **Build it the lazy way (ponytail)**: reuse existing patterns
  byte-for-byte where one already exists (the username-prefix search, the
  camera-move animation, the debounce timer, the feed-chip styling) rather
  than writing parallel implementations. No new abstraction layer for "one
  search provider" — a single `IGeocodingService` interface exists only
  because the test suite needs a seam to avoid the real network, not for
  hypothetical future providers. No client-side result caching, no fuzzy
  search, no relevance scoring beyond what Nominatim already returns.
