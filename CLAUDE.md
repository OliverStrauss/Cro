# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Cro is a messaging app where users send "cro's" to other users. Each cro travels across a
map in real time, taking physical days to arrive rather than delivering instantly.

The frontend is web-only going forward: there used to be a separate phone-optimized UI
(a bottom-tab `HomeScreen` and its own screens/widgets), but that's been retired in favor of
a single UI, `WebShellScreen`, used unconditionally on every platform. `main.dart` no longer
branches on `kIsWeb`.

## Role & working mode

Beyond implementing what's asked, work in these two modes by default:

### Tech-debt / tech-lead mindset

- Act as tech lead, not just an implementer. Before adding new code, check whether existing
  code should be refactored, deduplicated, or removed instead.
- Flag inconsistencies between `/app` and `/api` (naming drift, mismatched assumptions,
  config that no longer matches reality) rather than silently coding around them.
- Watch for: dead code, unresolved TODOs, missing tests on major logic changes, stale
  config, and places where a quick hack was used instead of the real fix.
- When something's worth fixing but out of scope for the current task, log it in
  `TECH_DEBT.md` (see below) rather than fixing it silently or dropping it.
- After a substantial session, summarize: what changed, what's now inconsistent or
  incomplete, and what you'd flag if this were a code review.

### Designer / UX mindset

- Don't implement requests purely literally — bring a point of view on whether the result
  is consistent with the app's existing patterns and worth pushing back on if not.
- Check new UI against the established palette and `ColorScheme` roles (see "UI theme /
  color palette" below) rather than introducing one-off colors or styles.
- Check new screens/widgets against existing conventions in `lib/web/screens/` and
  `lib/web/widgets/` — reuse existing patterns before inventing new ones.
- Weigh accessibility basics (contrast, tap-target size, readable text) as part of any UI
  change, not as an afterthought.
- Favor simplicity: if a requested feature would fragment the UX or add friction, say so
  and suggest a simpler alternative before building it as specified.

## Repository structure

This is a monorepo with two independently-buildable halves:

- `/app` — Flutter frontend (package name `cro_app`). Configured platforms: Android, Linux,
  Windows, Web (no iOS/macOS scaffolding has been generated) — Android/Linux/Windows builds
  still exist and still run, they just render the same web-first UI rather than a
  platform-specific one. The pre-auth `login_screen.dart`/`sign_up_screen.dart` live directly
  under `lib/screens/`; everything post-login lives under `lib/web/` (screens in
  `lib/web/screens/`, widgets in `lib/web/widgets/`) — that directory predates the mobile UI's
  removal and is simply the app's UI now, kept at its existing path/naming rather than
  renamed as part of that removal.
- `/api` — .NET 10 ASP.NET Core Web API (`CroApp.Api`), backed by Azure Cosmos DB via the
  `Microsoft.Azure.Cosmos` SDK directly (not EF Core's Cosmos provider — chosen for full
  control over partition keys and future geospatial queries for the map/delivery feature),
  plus Azure Blob Storage (via `Azure.Storage.Blobs`) for user-uploaded profile pictures.
  `api/CroApp.Api.Tests` holds the xunit integration test project.
- `/.github/workflows` — CI, split into one workflow per half (see below).

## Commands

### Frontend (Flutter) — run from `/app`

- `flutter pub get` — install dependencies
- `flutter analyze` — lint/static analysis
- `flutter test` — run all tests
- `flutter test test/widget_test.dart` — run a single test file
- `flutter run` — launch the app

### Backend (.NET API) — run from `/api`

- `dotnet restore CroApp.Api.Tests/CroApp.Api.Tests.csproj` — installs dependencies for both
  the API and the test project (via its `ProjectReference`). There's no `.sln`, so a bare
  `dotnet restore`/`build`/`test` in `/api` only picks up `CroApp.Api.csproj` and silently
  skips the nested test project — always target the test project's path explicitly.
- `dotnet build CroApp.Api.Tests/CroApp.Api.Tests.csproj --no-restore` — build both projects
- `dotnet test CroApp.Api.Tests/CroApp.Api.Tests.csproj --no-build` — run all tests (requires
  the Cosmos emulator and Azurite running locally, see below)
- `dotnet run` — run the API locally (also requires the emulator and Azurite running)
- `dotnet list package --vulnerable --include-transitive` — check for vulnerable transitive
  packages; the default `dotnet new webapi` template pulled in a vulnerable `Microsoft.OpenApi`
  transitive dependency, which had to be pinned explicitly to a patched version

## Local dev environment

### Setup — Cosmos DB Emulator (required for running or testing the API)

The API and its tests connect to a Cosmos DB Emulator, not a live Azure account (none is
provisioned yet). On this Apple Silicon/macOS machine, run the ARM64-native `vnext-preview`
Docker image (the classic Windows-only emulator and the older Linux image don't work
reliably here):

```
docker run -p 8081:8081 -p 1234:1234 mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview
```

Startup can take 30-90 seconds — poll `http://localhost:8081/` (200 once ready) rather than
using a fixed sleep. One-time local secret setup:

```
cd api
dotnet user-secrets init
dotnet user-secrets set "CosmosDb:ConnectionString" "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="
```

That's the emulator's fixed, publicly-documented well-known key — identical on every install
(see "Known dev-only shortcuts" below).

### Setup — Azurite Emulator (required for profile picture upload/tests)

Profile pictures go through Azure Blob Storage via `Azurite`, its official local emulator —
same story as Cosmos: no real Azure Storage account is provisioned yet, so local dev and CI
run entirely against the emulator. Azurite's Docker image lags behind the Azure.Storage.Blobs
SDK's request API version, so it needs `--skipApiVersionCheck` on startup (the error message
from a version mismatch names this flag directly):

```
docker run -p 10000:10000 -p 10001:10001 -p 10002:10002 \
  mcr.microsoft.com/azure-storage/azurite:latest \
  azurite --blobHost 0.0.0.0 --queueHost 0.0.0.0 --tableHost 0.0.0.0 --skipApiVersionCheck
```

One-time local secret setup:

```
cd api
dotnet user-secrets set "BlobStorage:ConnectionString" "UseDevelopmentStorage=true"
```

`UseDevelopmentStorage=true` is Azurite's own well-known connection-string alias (see "Known
dev-only shortcuts" below).

### Gotchas

- **Plain HTTP, not HTTPS**: the `vnext-preview` image serves a plain-HTTP gateway, not
  HTTPS — unlike the classic Windows emulator, there's no self-signed cert to bypass, and an
  `https://localhost:8081` connection string will hang/fail to connect (a raw TLS handshake
  against a plain-HTTP port fails in a way that's easy to mistake for "the emulator isn't
  running" — it is, this is just a scheme mismatch).
- **CI uses a different Cosmos image**: `appsettings.Development.json` sets
  `CosmosDb:UseEmulator: true`, which makes the API accept any TLS cert unconditionally —
  needed for CI's *different* emulator image (the classic x64 one, which serves a
  self-signed HTTPS cert), and harmless here since no TLS handshake ever happens against
  this image's plain-HTTP port. This flag must never be true against a real endpoint.
- **Stale Waypoints container after the partition-key change**: the Waypoints container's
  partition key changed from `/id` to `/userId` (a user can have up to 5 waypoints now, so
  the owning user's id is the partition key instead of the waypoint's own id).
  `CreateContainerIfNotExistsAsync` (in `Program.cs`, dev-only startup provisioning) is a
  no-op against an existing container, so a local "Waypoints" container created before this
  change is stuck on the old partition key — drop it once via the emulator's Data Explorer,
  served on its own port at `http://localhost:1234/` (not under `:8081`, and not the classic
  emulator's `/_explorer/index.html` path — this image's Explorer is a separate service), or
  just remove and re-run the emulator container to reset all local data, before running the
  API or tests again. CI is unaffected — its Cosmos emulator service container is fresh
  every run.
- **Hubs container**: a `Hubs` container (partition key `/status`) is provisioned the same
  dev-only way as Waypoints, for app-curated public landmark nests.
- **Dev user seeding on startup**: on startup, `Program.cs` also idempotently seeds two dev
  users if they don't already exist — `Oliver 1` (regular) and `Admin 1` (admin, can place
  Hubs via the map's "Add Hub" button). See "Seeding local dev data" below for the fuller
  seed tool.
- **Blob container access**: the `profile-pictures` container is provisioned on startup in
  Development with `PublicAccessType.Blob` (public read for blobs, no listing) so uploaded
  pictures are fetchable via a plain URL without SAS tokens — fine for local/dev, but real
  access control is needed before any prod deployment (see "Known dev-only shortcuts").

### Known dev-only shortcuts (never meaningful in prod)

These all fall in the same category — fixed, publicly-documented, or intentionally
permissive values that only work because nothing is pointed at a real Azure account yet.
None of these should ever reach a real endpoint or a prod deployment:

- Cosmos emulator's fixed well-known account key (above)
- `CosmosDb:UseEmulator: true` — unconditional TLS cert acceptance
- Azurite's `UseDevelopmentStorage=true` connection-string alias
- `profile-pictures` blob container's public read access
- `Program.cs`'s two seeded dev users' fixed password (`correct-horse-battery-staple`)
- `SeedDevUsers`' five seeded accounts' fixed password (`1`) — see below
- `DevCorsPolicy` (`Program.cs`) — Development-only CORS policy that allows any origin,
  header, and method. Needed because Flutter web's dev server binds a randomly-assigned
  localhost port each run, so a fixed-origin allow-list isn't practical locally. A real
  deployment needs a real allow-list scoped to the deployed web app's origin — not yet
  relevant since there's no prod deployment.

No real Azure Cosmos DB or Storage account is provisioned yet. Creating one
(`az cosmosdb create` / `sql database create` / `sql container create --partition-key-path
/id`, plus the Storage-account equivalent) is a manual step outside this repo, needed before
any prod deployment — not required for local dev or CI, both of which run entirely against
the emulators.

## Seeding local dev data

`Program.cs`'s own startup seed (above) only ever creates those two bare accounts — enough to
have a known admin, but not enough to exercise friends, nests, or the map with. For that,
**always run the standalone seed tool** (`api/Tools/SeedDevUsers`) after the emulators are up
and `dotnet user-secrets` is configured, from `/api`:

```
dotnet run --project Tools/SeedDevUsers/SeedDevUsers.csproj
```

This wipes the entire `Users` container and replaces it with five fixed accounts — `Admin`,
`Test1`, `Test2`, `Oliver`, `Annie` — all password `1` (see "Known dev-only shortcuts"
above), already mutually Accepted-friends with each other with auto-assigned colors, plus
one private nest apiece around Ames. `Admin` is seeded with `IsAdmin: true`. It talks
directly to the Cosmos emulator rather than through the running API (there's no `DELETE
/users` endpoint to do the wipe through), so it works whether or not `dotnet run` is up, and
leaves Hubs, Birds, and Reactions untouched. Re-running it is the standard way to reset back
to this known-good dataset — note that it deletes *every* existing user (including any
you've registered by hand through the app), and each run mints fresh user ids, so a
previously-seeded user's id is not stable across runs.

## CI

Two GitHub Actions workflows, each scoped to its own `working-directory`, run on push to
`main` and on every pull request:

- `flutter-ci.yml` — `flutter pub get` → `flutter analyze` → `flutter test`, in `/app`
- `dotnet-ci.yml` — runs a Cosmos emulator service container (the standard x64 image, not the
  ARM64 `vnext-preview` local dev needs) via the declarative `services:` block, plus Azurite
  started as a plain `docker run` step (the `services:` block can't pass `--skipApiVersionCheck`
  through — it always runs an image's default command, no args), waits for both to be ready,
  then `dotnet restore`/`build`/`test` against `CroApp.Api.Tests`, in `/api`

## UI theme / color palette

The frontend uses a fixed 8-color brand palette, defined as `CroColors` and wired into a real
`ColorScheme`/`ThemeData` (`app/lib/theme.dart`, applied in `main.dart`) rather than Flutter's
default `ColorScheme.fromSeed`. Prefer `Theme.of(context).colorScheme.<role>` (or a `CroColors`
constant for the rare literal, e.g. an own-nest marker's border, which is always Waypoint blue
regardless of theme) over hardcoding a `Colors.*` value anywhere in `/app`.

| Palette color | Hex | `ColorScheme` role | Usage |
|---|---|---|---|
| Background | `#D4D7DC` | `ThemeData.scaffoldBackgroundColor` | App canvas — a ~30% Fog/white blend, chosen to read as a visibly darker grey canvas rather than near-white, so Fog's grey carries through the whole app rather than just secondary text |
| Surface | `#FFFFFF` | `colorScheme.surface` | Cards, bubbles |
| Waypoint blue | `#5CB6E3` | `colorScheme.primary` | Primary, buttons, links |
| Deep waypoint | `#2A7194` | `colorScheme.secondary`, `AppBarTheme` | Headers, pressed states |
| Sky tint | `#BFE4F4` | `colorScheme.primaryContainer` | In-transit highlight, selection |
| Ink | `#2B2F33` | `colorScheme.onSurface` | Primary text |
| Fog | `#6B7280` | `colorScheme.onSurfaceVariant` | Secondary text, timestamps |
| Delivery amber | `#F3AA5E` | `colorScheme.tertiary` | In-transit badge, unread-message badge — used sparingly |

`colorScheme.error`/`onError` are left at Material's defaults — the palette doesn't specify an
error color. `scaffoldBackgroundColor` is set independently of `colorScheme.surface` (rather
than letting Material 3 derive one from the other) so the palette's explicit
canvas-vs-card-surface split is preserved exactly.

## Tech debt tracking

Ongoing tech debt (accepted shortcuts, things flagged but out of scope at the time, etc.) is
tracked in `TECH_DEBT.md` at the repo root. Update it as you go rather than letting notes
about things-to-fix-later live only in commit messages or PR descriptions.

## Workflow conventions

- Issues are written as Jira-style user stories: "As the CroApp, I want ... so that ..."
  with an Acceptance Criteria checklist.
- One feature branch per issue, named `feature/<issue-number>-<short-description>`.
- PR descriptions include `Closes #<issue-number>` so merging auto-closes the issue.
- Stacked/dependent PRs are branched off the dependency branch, with the PR base set to
  that branch instead of `main`. GitHub does **not** auto-retarget a stacked PR's base to
  `main` after the parent PR merges — this must be done manually (re-target the PR, or
  merge/PR the child branch into `main` separately) or the child's changes can end up
  merged into the now-orphaned parent branch instead of `main`.
- Major logic changes must include tests.
- Issues/stories not written by Oliver directly (i.e. authored by Claude Code) end with:

  ```
  -Co Authored By Olivers Robot companion (claude code)
  ```
- After pushing a branch and opening a PR, do not sit and poll/watch CI status. Report
  "Done" plus a concise summary of exactly which files changed and what each change
  affects, then stop — merging and checking CI results is Oliver's call, not something to
  wait around for.
- CLAUDE.md-only changes can be pushed directly to `main`, no issue/branch/PR needed.
