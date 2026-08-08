# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Cro is a messaging app where users send "cro's" to other users. Each cro travels across a
map in real time, taking physical days to arrive rather than delivering instantly.

## Repository structure

This is a monorepo with two independently-buildable halves:

- `/app` — Flutter frontend (package name `cro_app`). Configured platforms: Android, Linux,
  Windows, Web (no iOS/macOS scaffolding has been generated).
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

### Local Cosmos DB Emulator (required for running or testing the API)

The API and its tests connect to a Cosmos DB Emulator, not a live Azure account (none is
provisioned yet — see below). On this Apple Silicon/macOS machine, run the ARM64-native
`vnext-preview` Docker image (the classic Windows-only emulator and the older Linux image
don't work reliably here):

```
docker run -p 8081:8081 mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview
```

Startup can take 30-90 seconds — poll `https://localhost:8081/_explorer/emulator.pem` rather
than using a fixed sleep. One-time local secret setup (never commit the connection string):

```
cd api
dotnet user-secrets init
dotnet user-secrets set "CosmosDb:ConnectionString" "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="
```

That's the emulator's fixed, publicly-documented well-known key — identical on every install.
`appsettings.Development.json` sets `CosmosDb:UseEmulator: true`, which makes the API bypass
the emulator's self-signed TLS cert — this flag must never be true against a real endpoint.

No real Azure Cosmos DB account is provisioned yet. Creating one (`az cosmosdb create` /
`sql database create` / `sql container create --partition-key-path /id`) is a manual step
outside this repo, needed before any prod deployment — not required for local dev or CI,
both of which run entirely against the emulator.

The Waypoints container's partition key changed from `/id` to `/userId` (a user can have
up to 5 waypoints now, so the owning user's id is the partition key instead of the
waypoint's own id). `CreateContainerIfNotExistsAsync` (in `Program.cs`, dev-only startup
provisioning) is a no-op against an existing container, so a local "Waypoints" container
created before this change is stuck on the old partition key — drop it once via the
emulator's Data Explorer (`https://localhost:8081/_explorer/index.html`), or just remove
and re-run the emulator container to reset all local data, before running the API or tests
again. CI is unaffected — its Cosmos emulator service container is fresh every run.

### Local Azurite Emulator (required for profile picture upload/tests)

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

`UseDevelopmentStorage=true` is Azurite's own well-known connection-string alias (not a
secret, but kept in user-secrets anyway for consistency with `CosmosDb:ConnectionString` —
same category of value that becomes a real, non-hardcodable endpoint once a real Azure
Storage account exists). The `profile-pictures` container is provisioned on startup in
Development with `PublicAccessType.Blob` (public read for blobs, no listing) so uploaded
pictures are fetchable via a plain URL without SAS tokens — fine for local/dev, but real
access control is needed before any prod deployment, same accepted-tradeoff category as the
DevCorsPolicy and the Cosmos emulator's TLS bypass.

No real Azure Storage account is provisioned yet, for the same reasons as Cosmos above.

## CI

Two GitHub Actions workflows, each scoped to its own `working-directory`, run on push to
`main` and on every pull request:

- `flutter-ci.yml` — `flutter pub get` → `flutter analyze` → `flutter test`, in `/app`
- `dotnet-ci.yml` — runs a Cosmos emulator service container (the standard x64 image, not the
  ARM64 `vnext-preview` local dev needs) via the declarative `services:` block, plus Azurite
  started as a plain `docker run` step (the `services:` block can't pass `--skipApiVersionCheck`
  through — it always runs an image's default command, no args), waits for both to be ready,
  then `dotnet restore`/`build`/`test` against `CroApp.Api.Tests`, in `/api`

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
