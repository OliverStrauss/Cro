# Tech Debt

Accepted shortcuts, things flagged but out of scope at the time, and other known gaps
worth revisiting. See `CLAUDE.md` for the working conventions this file supports.

## ~~CI `deploy` job silently skipped on every push since #179, because `build` kept 503ing against its own Cosmos emulator~~ (resolved 2026-09-14)

Discovered 2026-09-14 while investigating a "Could not pin this bird" report: the pin feature
(#179, merged 2026-09-14 01:14 UTC) had never actually reached prod. `cro-api`'s last real
deploy predated that merge by 4+ hours, even though `dotnet-ci.yml`'s `deploy` job (fixed for
real on 2026-09-11, see the CD entry below) should have picked it up automatically. `gh run
list` showed `build` failing on that push (and on every push since) with the overall run
marked `failure` - not silently green, but nobody was watching for it, same blind spot the
2026-09-11 CD entry below already flags.

Root cause: `Program.cs`'s startup provisioning block (11 `CreateContainerIfNotExistsAsync`
calls, 5 blob-container calls) had just gone from Development-only to running unconditionally
in every environment (see the entry below). The integration test suite boots ~25 separate
in-process hosts, one per `IClassFixture<WebApplicationFactory<Program>>` test class - so all
~25 now independently ran the full provisioning block at startup, all racing each other
against the one shared local Cosmos emulator container in CI. `build`'s own diagnostics showed
the emulator pegged at 97-100% CPU right before every test failed identically with `Cosmos
Exception: ServiceUnavailable (503)` - the emulator getting starved under GitHub Actions'
resource limits, not a real app bug (the exact same 173 tests pass cleanly against the local
ARM64 emulator with room to spare).

Fixed by gating that provisioning block through a small `StartupProvisioning.RunOnceAsync`
helper (`Program.cs`), keyed by environment name via a `ConcurrentDictionary<string, Task>` -
all ~24 Development-environment test hosts now converge on one shared provisioning run instead
of 24 redundant ones, while `ProdCorsTests` (which exists specifically to prove this block also
runs under `Production`) still gets its own real run under its own key. Cuts ~25 concurrent
provisioning runs down to 2. No test file changes needed - this lives entirely in `Program.cs`,
since the operations being deduplicated were already idempotent by design.

Once `cro-api` was manually redeployed (`az webapp deploy`, same as the historical `OneDeploy`
entries in `az webapp log deployment list`) to unblock the pin feature immediately, a live
`curl` against `POST /birds/{id}/pin` confirmed the fix: an empty-body `404` (route missing
entirely) became a proper `{"error":"..."}` JSON response.

Worth a follow-up: nothing pages/notifies on a `push`-triggered workflow failing on `main` -
the exact same blind spot the 2026-09-11 CD entry below already called out and never actually
closed.

## Radio Log redesign (`redesign/radio-log-visual-overhaul`) has no visual comp and no browser QA pass

The whole-web-app visual overhaul (theme, typography, hairline card/button language - see
root `DESIGN.md`) was built code-led with no comp: this environment has no image-generation
tool available, so there was no north-star mockup to build toward or diff the finished build
against. Verification was `flutter analyze` (clean) and `flutter test` (all 118 tests pass,
after fixing font-asset bundling, a chip-list virtualization regression, and a 0.2px button
overflow the new fonts caused) - not a rendered screenshot or an in-browser pass, since this
repo's own convention (see CLAUDE.md's feedback memory) is that widget tests + analyze suffice
and heavy Playwright/CDP browser verification isn't worth standing up for Flutter web. That
means real layout at other viewport widths, hover/focus states, and fine spacing were never
visually inspected by anyone - worth an actual `flutter run` pass (map screen especially, the
most complex single surface touched) before merging, and worth treating `DESIGN.md` as the
source of truth for anything that looks off rather than reverting piecemeal.

A few lower-traffic corners were deliberately left in their prior visual language rather than
retouched: `bird_payload_view.dart`'s message/audio/image content (correctly stays prose, not
data-voice, so untouched), the small in-map radius values on Hub vs. nest markers (11px vs.
fully rounded - a pre-existing distinction, preserved), and `cro_logo_mark.dart`'s drawn
squircle mark (already a real authored asset, not a generic tell). None of these needed
fixing; noting them so a future pass doesn't assume they were missed.

## `POST /birds/compose` / `BirdService.ComposeAndSendAsync` are now test-only, unreachable from the UI

Users no longer spawn birds themselves - every user is auto-provisioned a fixed 5-bird starter
roster instead (`BirdTypeCatalog.StarterRoster`, lazily created in `BirdService.ListAsync` and
attached to a nest in `AssignUnassignedBirdsToNestAsync`). The `/birds/compose` endpoint and
`ComposeAndSendAsync` were deliberately left in place rather than deleted, because
`api/CroApp.Api.Tests/{BirdArrivalEndpointTests,BirdComposeEndpointTests,BirdEndpointTests,
FriendshipEndpointTests,EventEndpointTests,BirdSendEndpointTests,HubMessageEndpointTests,
BirdReactionEndpointTests,BirdDeleteEndpointTests}.cs` all use it as their only way to put a bird
into a specific test state (type/content/media/position) - ripping it out would mean rewriting
every one of those setup helpers around the new starter-roster shape in the same pass, which
wasn't attempted here. `MaxBirdsPerUser` already makes it a no-op for a real user (they start at
the cap), so this is inert in production, but it's still surface area: worth either (a) rewriting
the test helpers to provision-then-rename/resend instead of composing, and deleting the endpoint,
or (b) formally repurposing it as an admin/test-only route (auth-gated to `IsAdmin`, not just
left implicitly unreachable because nothing in the UI calls it).

## `DELETE /birds/{id}` is now unreachable from the frontend, same shape as `/birds/compose` above

`BirdPanelContent`'s Delete button (which called `BirdService.deleteBird` /
`DELETE /birds/{id}`) was removed from the UI (2026-09-10) - there was no way back to the
fixed 5-bird starter roster once a bird was deleted (spawning is gone, see the `/birds/compose`
entry above), so exposing permanent deletion in the UI no longer made sense. The Flutter
`BirdService.deleteBird` wrapper and the backend `DELETE /birds/{id}` endpoint/`DeleteAsync`
were left in place rather than deleted, same reasoning as `/birds/compose`: worth checking
before ripping them out whether `api/CroApp.Api.Tests` (e.g. `BirdDeleteEndpointTests.cs`)
relies on the endpoint for setup/teardown. Revisit alongside that entry - both are now
test-only/no-UI-caller surface area with the same "delete or formally repurpose as
admin-only" choice ahead of them.

## Pinning a bird (`ReceivedBirdSheet`'s pin icon) doesn't know it's already pinned across sessions

`PinnedBird.Id` is deterministic per delivery (`{birdId}:{receiverId}:{deliveredAtTicks}`), so
re-pinning the same still-resident delivery is an idempotent upsert server-side - no duplicate
rows. But the web sheet itself (`ReceivedBirdSheet`) has no way to know on open whether an
earlier visit already pinned this exact delivery (that would need a
`GET /birds/{id}/pin-status`-shaped call, or threading `GET /pins/mine` results down into
`NestPanelContent`/`ReceivedBirdSheet`, neither of which exists yet) - so the pin icon always
starts unpinned each time the sheet is reopened, even if it's already saved. Tapping it again
in that state is harmless (same idempotent upsert), but the icon lies about the true state
until the user has tapped it once in the current sheet instance. Worth fixing if this becomes
confusing in practice - the fix is straightforward (pass the caller's already-loaded
`GET /pins/mine` list down and match on `birdId` + the bird's own `updatedAt`).

## `GET /pins/public` is a full cross-partition scan, same tradeoff `GET /birds/public` already accepts

See the `ponytail:` comment on `CosmosPinnedBirdRepository.ListPublicAsync` - fine at this
project's scale, same shortcut `BirdService.ListPublicInTransitAsync` already takes. Upgrade
path if the `Pins` container ever gets large: a composite index on `(isPublic, createdAt)` so
the newest-first ordering can run server-side instead of in memory.

## Backend integration tests appear to write into the shared local dev Cosmos database

While investigating the above, `HubMessages`/`Users`/etc. in the local Cosmos emulator (the one
`docker run ... azure-cosmos-emulator:vnext-preview` from CLAUDE.md's setup) contained many rows
with usernames like `delete-user-<guid>`, `bird-send-user-<guid>`, `event-hub-<guid>` — these read
like fixture data generated by `api/CroApp.Api.Tests`, not anything created through the app or the
dev seed tools. Confirmed 2026-09-10: every fixture's `WebApplicationFactory<Program>` reuses
`CosmosDb:ConnectionString` as-is (the same emulator/`CroApp` database `dotnet run` points at) -
there's no scoped/temporary database per test run. Until 2026-09-10 this was largely masked by the
now-fixed "fixture config gap" above (17/18 fixtures failed to boot at all, so most test files
never got the chance to write anything); now that every fixture boots, all 18 files' throwaway
rows land in the shared local dev data on every `dotnet test`. Not a problem for `SeedFixedDevUsersOnStartup`'s
Users wipe-and-reseed (Users gets fully replaced on the next `dotnet run` regardless), but Hubs/
Waypoints/Birds/Reactions are left untouched by that reseed, so their test-fixture rows accumulate
indefinitely. Fix: point the test host at a disposable/per-run database name instead of the dev
one, or accept it and add a periodic manual cleanup step.

## `HubPanelContent`'s header can't reuse the shared `PanelHeader` widget

`app/lib/web/widgets/hub_panel_content.dart` hand-rolls its own header instead of using
`PanelHeader` (`app/lib/web/widgets/panel_header.dart`), which every other panel body
(nest, bird, friend bird) uses. `PanelHeader` is a left-aligned `Row` (static avatar |
title/subtitle | close button); the Hub header is a centered `Column` with the avatar
itself acting as a tappable "suggest a photo" control (camera-badge overlay, upload
spinner state) - a shape `PanelHeader`'s API has no room for (`avatar` is a static
`Widget`, no `onTap`/loading slot). Flagged during the #128 frontend-refinement pass
rather than generalizing `PanelHeader` to fit both layouts, since that's a real design
question (does a second layout mode belong on the shared widget, or does Hub's tappable-
avatar pattern belong on every panel eventually?) rather than a mechanical fix. Revisit if
a third panel needs a non-Row header shape, which would make the case for a shared
variant clearer.

## `WebProfileScreen` and `WebShellData` fetch overlapping friends data independently

Both `app/lib/web/screens/web_profile_screen.dart` (formerly `web_friends_screen.dart`,
merged into Profile by #174) and `app/lib/web/state/web_shell_data.dart` call
`friendsService.getFriends`/`getIncomingRequests` and now both poll on their own
`Timer.periodic(3s)` (added for live-update support - see the notifications/friend-requests
live-feel pass). `WebShellData`'s copy exists only to drive the nav rail's incoming-invite
badge count (`WebShellController.friendsBadgeCount`); `WebProfileScreen`'s is the full list
it renders below the profile card. A real fix would lift this to one shared source of truth
in `WebShellData` and have `WebProfileScreen` consume it instead of fetching its own copy,
but that also touches the rail's badge wiring - out of scope for just merging the two screens.
Revisit if a third consumer of friends/incoming-request data shows up.

## `GET /events`/`EventService.ListAsync` are now unreachable from the frontend

`app/lib/web/services/event_service.dart`'s `listEvents` (backed the old `WebYouScreen`'s
"flights logged" stat tile) was deleted in #174 once that screen was merged into
`WebProfileScreen` without a stats grid - it was its only caller anywhere in `/app`. The
backend `GET /events` endpoint (`api/Program.cs`) and its `EventService`/`CosmosEventRepository`
plumbing were deliberately left in place rather than deleted, same reasoning as the
`/birds/compose` entry above: removing a backend endpoint is a bigger, separate change than a
frontend screen merge, and it's not yet confirmed nothing else (an admin tool, a future
mobile client) depends on it. Worth either deleting it outright or confirming it's genuinely
orphaned before doing so.

## `SendBirdDialog`'s distance/ETA preview assumes `BirdTravelOptions.SpeedMultiplier` is 1.0

The redesigned send dialog (`app/lib/widgets/send_bird_dialog.dart`) shows each destination's
distance and travel time up front, computed client-side with a Dart port of the backend's
haversine-distance/base-speed formula (`BirdSpeed` in `app/lib/models/bird.dart`, mirroring
`GeoDistance.cs`/`BirdTypeCatalog.cs`). `BirdTravelOptions.SpeedMultiplier` (the server-side
tuning knob applied on top of a bird type's base speed) isn't exposed to the client at all, so
this preview silently assumes it's the default 1.0. Harmless today since nothing sets it to
anything else, but if an environment ever tunes it, the dialog's preview would drift from the
real ETA the send actually gets. Fix by exposing the multiplier through a small config
endpoint (or embedding it in whatever settings payload the web shell already loads on start)
if that tuning is ever actually used.

## Unbounded cross-partition scans and no pagination across most repositories

Flagged while scoping the real-Azure launch plan (issues #140/#141). `CosmosUserRepository`
(`GetByUsernameAsync` - every `/login`, and `SearchByUsernamePrefixAsync`),
`CosmosBirdRepository` (`GetByIdAsync`, `GetByNestIdAsync`, `GetManyByUserIdsAsync`),
`CosmosHubRepository.GetAsync`, `CosmosHubPictureSuggestionRepository` (`ListPendingAsync`,
`GetAsync`), and `CosmosWaypointRepository` (`GetByIdAsync`, `GetManyByUserIdsAsync`) all run
cross-partition scans with no pagination, each already commented in source as "fine at
current tiny counts." Accepted at today's user count; revisit if account/row counts grow
enough that these scans show up in Cosmos RU cost or latency.

## `CosmosEventRepository`'s per-user event history is never pruned

`QueryByUserIdAsync` is single-partition (good) but sorts/limits **client-side in memory**
after loading a user's entire event history, which is never pruned or TTL'd (per the
existing comment at `CosmosEventRepository.cs`) - unlike `HubMessages`' 7-day TTL. Every
`/events`, `/notifications`, and `/notifications/unread-count` call re-reads the whole
history. Fine at launch scale; will need either a TTL (losing the "permanent record" property
noted in `Program.cs`'s Events container comment) or real server-side pagination once
long-lived accounts accumulate enough history for this to matter.

## ~~Blob container public-access + CORS is a manual prod step, not automated anywhere~~ (resolved 2026-09-14)

`Program.cs`'s startup block that sets every picture container to `PublicAccessType.Blob`
and adds a permissive Blob CORS rule only ran `if (app.Environment.IsDevelopment())`. Going
live on `croappstorage`/`cro-prod` (#149's CD pipeline) hit this directly: no one ran the
prod-equivalent step, so every picture container was private with no CORS, and every picture
screen (profile, birds, nests, hubs) failed to load images in production. Fixed manually via
`az storage container set-permission`/`az storage cors add` on 2026-09-10 (see CLAUDE.md) as
a stopgap, then fixed for good below.

## ~~New Cosmos containers need a manual prod step too - the `Pins` container launched missing from prod~~ (resolved 2026-09-14)

Same root cause as the blob-storage entry above, second occurrence: a brand-new Cosmos
container (`Pins`, added by #179's pin feature) never got created against the real
`cro-app-cosmos` account (`cro-prod`) since container creation was Development-only.
Discovered 2026-09-14: pinning a bird worked fine locally but failed in production with a
generic "Could not pin this bird" popup (the Cosmos SDK throwing on a missing container
isn't a caught `ServiceException`, so it surfaces as an unhandled 500 with no JSON `error`
body for the client to show). Fixed as a stopgap via `az cosmosdb sql container create -g
cro-prod -a cro-app-cosmos -d CroApp -n Pins --partition-key-path /receiverId`.

**Real fix for both entries**: `Program.cs`'s container/blob-container provisioning block no
longer checks `app.Environment.IsDevelopment()` - it now runs on every boot, in every
environment. `CreateContainerIfNotExistsAsync`/`CreateIfNotExistsAsync` are idempotent
no-ops once a container exists, so this costs nothing at steady state and means a brand-new
container defined in code reaches prod automatically on the next deploy, closing this class
of bug for good instead of relying on someone remembering a matching `az` command. Only the
destructive dev-user-reseeding step (which wipes `Users`) stays gated to Development - see
the comments in `Program.cs`. `ProdCorsTests` (`CorsTests.cs`) now exercises this path under
a `Production` environment to catch a regression back to the old gate.

## `GET /birds/public` is a full cross-partition scan with no index/materialized view

`BirdService.ListPublicInTransitAsync` (#156) backs the "any user can see a public bird
in flight" feature by querying `CosmosBirdRepository.ListPublicTravelingAsync`, which scans
every partition in the Birds container (`WHERE c.isPublic = true AND c.isTraveling = true`,
no partition key) rather than something scoped like `ListTravelingForUsersAsync`'s
friend-id list. Fine at this project's user-base scale; if the Birds container ever gets
large, replace it with a materialized "public birds" view/index instead of a full scan on
every poll (the web shell polls this every 3 seconds - see `WebShellData.startPolling`).

## No rate limiting, refresh tokens, or crash reporting/observability

Also flagged while scoping the launch plan. None of these exist today: no `AddRateLimiter`
(the 5 file-upload endpoints are the main exposure once request size limits are in place -
see #140), no refresh-token flow (a 60-minute access token just requires re-login on expiry,
now that #141 makes a 401 log the user out cleanly instead of failing silently), and no
crash reporting/APM on either half (Application Insights would be the natural add for the
API given it's already targeting Azure App Service; Flutter web has no equivalent wired up
at all). None of these block an initial small-scale launch; revisit once there's real traffic
to justify them.

## CD had been silently failing on every push since #149, and password-reset email used SMTP (which Azure App Service blocks)

Discovered 2026-09-11 while chasing a "forgot-password email never arrives" report. Two
compounding issues, both now fixed:

- `dotnet-ci.yml`'s `deploy` job had failed on *every single push* to `main` since #149
  introduced it - `cro-api`'s SCM basic-auth publishing credentials were disabled (likely an
  Azure platform default applied after the App Service was created), which breaks
  publish-profile-based deploys regardless of whether the profile secret itself is valid.
  Net effect: prod was silently stuck running whatever was deployed once, manually, before
  #163 (password reset) even existed - nobody noticed because `build` (tests) kept passing
  and the workflow's overall status looked normal in the PR view. Fixed by re-enabling basic
  auth (`az resource update ... basicPublishingCredentialsPolicies/scm --set
  properties.allow=true`) and rotating `AZURE_WEBAPP_PUBLISH_PROFILE` to a fresh profile.
  Re-enabling basic auth is a minor security relaxation vs. the alternative (OIDC/federated
  service-principal login, no shared long-lived secret) - worth migrating the deploy step to
  that eventually, but out of scope for just unblocking delivery. Worth adding a lightweight
  CI check that deploy-job failures on `main` actually page/notify someone, since GitHub's PR
  UI doesn't surface a `push`-triggered workflow's later failure back onto the PR that caused it.
- Once deploy was unblocked, `/forgot-password` started 500ing: `SmtpEmailSender` (plain
  `System.Net.Mail.SmtpClient`, port 587) can't complete a connection from `cro-api` at all -
  Azure App Service's shared/Basic plans block outbound SMTP ports at the platform level for
  anti-spam reasons, independent of credentials or sender verification. First swapped in a
  SendGrid-over-HTTPS sender, but that hit repeated 401s from malformed/invalid API keys
  copied out of SendGrid's dashboard - settled on Azure Communication Services' Email API
  instead (`AcsEmailSender`, using the official `Azure.Communication.Email` SDK rather than
  hand-rolling the REST API's HMAC request signing), since it's provisioned and keyed entirely
  via `az` CLI in the same subscription - no dashboard, no secret to copy by hand. Provisioned:
  a `cro-comm` Communication Services resource, a `cro-email-svc` Email Service with an
  `AzureManaged` domain (auto-verified, no external DNS needed - sends from
  `DoNotReply@<guid>.azurecomm.net`), linked together. Pay-per-email (~$0.00025/email), not a
  persistent free tier like SendGrid's, but negligible at this app's volume. Config is
  `Acs:ConnectionString`/`Acs:FromAddress` (Azure App Service settings updated to match).
  Sender address is cosmetically rough (an auto-generated GUID subdomain) since Cro doesn't
  own a real domain yet - functionally fine, purely a trust/polish issue. Revisit (add a
  custom domain to the `cro-email-svc` Email Service, verify via DNS TXT/CNAME records) once
  Cro has a real domain for other reasons.

## `GET /search`'s places section depends on Nominatim's free public instance

`NominatimGeocodingService` calls `nominatim.openstreetmap.org` directly - no API key, no
billing, chosen specifically because it pairs naturally with the map's existing OSM tiles
(flutter_map + MapTiler/raw-OSM tiles) rather than pulling in an unrelated paid provider like
Google Places. Its usage policy caps free use at roughly 1 request/second and expects a real
identifying `User-Agent` (set at registration in `Program.cs`); the web shell's 250ms search
debounce keeps real traffic well under that cap at this app's current scale, and a transient
outage there degrades to an empty Places section rather than failing the whole search (see
`IGeocodingService`'s try/catch in the `/search` endpoint). Once real user traffic grows
enough to risk that rate cap, this needs either a self-hosted Nominatim instance or a move to
a paid geocoder (Mapbox was the runner-up when this was scoped, for its generous free tier and
much better address/POI coverage than Nominatim's OSM-derived data).

## `CLAUDE.md` describes a 5-waypoints-per-user model that `WaypointService` doesn't implement

Discovered 2026-09-14 while building the "shoo a bird home" feature (#204): `CLAUDE.md`'s
"Stale Waypoints container" gotcha says "a user can have up to 5 waypoints now (the owning
user's id is the partition key instead of the waypoint's own id)" - but
`WaypointService.CreateAsync` still hard-caps every user at exactly one nest (`if (existing.Count
> 0) throw new ServiceException(409, ...)`), and nothing else in `/api` reads or enforces a
5-waypoint limit anywhere. The partition-key-is-`/userId` part of that note is still accurate
(and is genuinely why `ShooAsync`'s "home nest" lookup here could safely assume `FirstOrDefault`
over `ListByUserIdAsync` finds at most one match), but the "up to 5" cap itself was either never
implemented or was reverted without the doc being updated. Left as-is rather than fixed silently
here since it's unclear which one is the intended design - either `WaypointService` needs a real
multi-nest cap (and every "the user's one nest" assumption sprinkled across `BirdService`/
`PinService`/`DeleteAsync` needs revisiting), or `CLAUDE.md` just needs its stale "up to 5"
phrase corrected to "one."
