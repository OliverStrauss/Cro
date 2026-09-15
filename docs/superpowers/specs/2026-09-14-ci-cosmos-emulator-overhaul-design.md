# CI Cosmos emulator overhaul + failure notification

## Problem

`dotnet-ci.yml`'s `deploy` job only runs when `build` passes (`needs: build`). `build` has
failed on every push to `main` since PR #177 (2026-09-13) - every test run ends with all 186
tests failing identically against `Microsoft.Azure.Cosmos.CosmosException: ServiceUnavailable
(503)`, "high demand in this region." As a result `cro-api` has been frozen at its pre-#179
build for two days while nine PRs (#190 through #210) merged into `main` without ever
deploying - discovered via a live-tested "shoo never works" report that turned out to be a
missing route on a stale deploy, not a code bug (see TECH_DEBT.md).

Three prior sessions already tried to fix this at the app/workflow-tuning layer and each
attempt still failed identically on GitHub Actions' actual runner, despite passing locally
every time:

1. **#193** - deduplicated `Program.cs`'s startup provisioning across the ~25
   `WebApplicationFactory`-backed test hosts so they share one provisioning run instead of
   ~25 redundant ones. Made the failure mode *worse* (a single caught 503 now fails every host
   sharing that cached task) rather than better.
2. **3895bd0** (2026-08-07) - disabled xunit's collection/assembly parallelism entirely
   (`xunit.runner.json`), so no two test classes ever hit the emulator concurrently. Confirmed
   still in effect. Didn't fix the current failure.
3. **#210** (`e4d9525`) - wrapped the provisioning call in a 3-attempt retry with backoff.
   Verified 186/186 passing locally, merged, and its own merge-triggered run still failed
   186/186 on all three of the *workflow's own* fresh-emulator retry attempts - one attempt
   ran 26 minutes before failing completely, which reads as sustained emulator distress, not a
   short blip a request-level retry can ride out.

With test-level concurrency already fully eliminated (fix #2) and the failure still 100%
reproducible on every attempt, the remaining explanation is that the classic
`azure-cosmos-emulator:latest` image itself doesn't run reliably in GitHub Actions'
resource-constrained standard runner (2 cores/7GB on the free tier). The workflow's own
existing comments already document this image's known crash bug under these constraints (a
fatal error in its Windows-compat layer, worked around with `--shm-size=1g`), and it's
configured for 10 partitions (`AZURE_COSMOS_EMULATOR_PARTITION_COUNT=10`), which is a
meaningful memory/CPU footprint before a single test even runs.

Separately: nothing notifies anyone when a push-triggered workflow fails on `main`. This
exact gap is called out twice already in TECH_DEBT.md and is a direct contributor to this
going unnoticed for two days.

## Goals

- Make `build` reliably pass on GitHub Actions' standard (free-tier) `ubuntu-latest` runner,
  so `deploy` actually runs after every merge to `main`.
- Stay within free-tier resource limits - no bigger/paid runner.
- Make a red push-triggered `main` build impossible to miss again.

## Non-goals

- Restructuring the test suite to reduce its dependence on a live Cosmos emulator (e.g. fakes
  for non-integration tests). Real, durable improvement, but a much bigger change than a CI
  fix - logged as a new TECH_DEBT.md item instead, not part of this change.
- Any change to `deploy`'s own logic, triggers, or the app's runtime Cosmos/Blob provisioning
  behavior (that block running unconditionally in every environment is intentional - see
  TECH_DEBT.md's "Blob container access" history - not something this touches).
- Slack or email notification channels - explicitly deferred in favor of an auto-filed GitHub
  issue, which needs no new secrets and ships immediately.

## Design

### 1. Replace the classic Cosmos emulator image with `vnext-preview`

Swap `mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest` for
`mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview` in the `Run tests...`
step of `dotnet-ci.yml`. This is the same image local dev already runs successfully on Apple
Silicon (see CLAUDE.md's setup section), confirmed via Microsoft's current docs to support
both ARM64 and amd64 (what GitHub-hosted runners use), GA as of Microsoft's own recent
announcement, and specifically documented with GitHub Actions CI examples - not an
ARM64-only preview.

Consequences of the swap, all mechanical:

- **Drop the classic-image-only flags**: `--shm-size=1g` (works around a bug specific to the
  classic image's compat layer) and `-e AZURE_COSMOS_EMULATOR_PARTITION_COUNT=10` /
  `-e AZURE_COSMOS_EMULATOR_ENABLE_DATA_PERSISTENCE=false` (classic-emulator-specific
  partition/persistence tuning that vnext-preview doesn't use - it doesn't pre-allocate a
  fixed partition count the way the classic image does, which is itself a large part of the
  reduced footprint). `docker run` becomes the same minimal form CLAUDE.md already documents
  for local dev: `--publish 8081:8081 --publish 1234:1234`.
- **Readiness probe**: vnext-preview serves plain HTTP, not HTTPS (no self-signed cert to
  handshake against) - replace the current `curl -sk -f https://localhost:8081/_explorer/emulator.pem`
  probe with a plain `curl -f http://localhost:8081/` polling loop, matching what CLAUDE.md
  already documents for local dev ("poll http://localhost:8081/ (200 once ready)"). Keep the
  existing `--max-time`-bounded, capped-attempts polling shape - just the URL/scheme changes.
- **Connection string**: the `CosmosDb__ConnectionString` env var in the test-run step changes
  from `https://localhost:8081/...` to `http://localhost:8081/...`.
- **`CosmosDb:UseEmulator` stays `true`, unchanged** - it's a harmless no-op against a
  plain-HTTP endpoint (nothing to TLS-bypass), same as it already is for local dev today. No
  code change needed in `Program.cs` or `appsettings.Development.json`.
- **Keep the existing fresh-container retry loop** (`docker rm -f` + up to 3 attempts) as
  defense-in-depth even though vnext-preview shouldn't hit the classic image's specific crash
  bug - it's cheap insurance against any other transient infra blip, and removing it isn't
  necessary to fix the actual problem.
- Update the two now-inaccurate CLAUDE.md gotchas once this ships: "CI uses a different Cosmos
  image" (CI and local dev will now use the *same* image) and the `--shm-size`/partition-count
  reasoning tied to the classic image.

This is approach 1 from the design discussion, and on its own is expected to close the actual
gap - it removes the specific image with the documented crash bug rather than tuning
parameters around it, using a lighter-by-design replacement that already works for this
project locally.

### 2. Keep the footprint minimal (approach 2, folded in as defense-in-depth)

vnext-preview's lack of a partition-count knob already removes most of the "approach 2" lever
(there's nothing analogous to lower). What still applies, to avoid adding footprint back:

- Don't enable optional heavier features the vnext-preview image supports but this project
  doesn't need for CI - e.g. leave `ENABLE_OTLP_EXPORTER`/OpenTelemetry off, don't request a
  larger-than-default `QUERY_BUFFER_SIZE_KB`.
- Confirm at implementation time whether vnext-preview persists data to disk by default inside
  the container and, if there's a flag to disable it (mirroring the classic image's
  `ENABLE_DATA_PERSISTENCE=false`), set it - each CI run gets a fresh container regardless, so
  persistence is pure overhead here.

If vnext-preview still turns out to be flaky on the actual GitHub Actions runner once tried
(can't be fully confirmed until the PR's own `pull_request`-triggered run exercises it), the
fallback is tuning the *classic* image's partition count down (the original approach 2) rather
than reverting - that decision point is called out explicitly in the rollout plan below.

### 3. Auto-file a GitHub issue when `build` fails on a push to `main`

Add a small trailing job (`needs: build`, `if: failure() && github.ref == 'refs/heads/main' &&
github.event_name == 'push'`) that opens a GitHub issue on failure, using the workflow's
built-in `GITHUB_TOKEN` via an inline `actions/github-script` step (official GitHub-maintained
action, no new dependency to vet) - no new secrets required. To avoid filing a duplicate issue
on every red run in a row, search for an existing open issue with a fixed label (e.g.
`ci-failure`) first: comment on it with the new failed run's link if one exists, otherwise
create a new one. Closing is left as a normal manual step (close the issue once `build` is
green again) rather than adding a second always-run job just to auto-close it - simplest thing
that actually closes the "nobody noticed for two days" gap; auto-closing can be added later if
the manual step turns out to be a real friction point.

## Rollout / verification plan

1. Ship this on its own branch/PR. Since `dotnet-ci.yml` is itself in the workflow's trigger
   `paths`, the PR's own `pull_request`-triggered run exercises the new emulator setup before
   anything merges - this is the real test of whether the vnext-preview swap actually works on
   GitHub Actions' runner, not just locally.
2. If that PR run is still flaky: apply the classic-image partition-count fallback (approach 2
   proper) instead of merging a still-broken pipeline, and note the outcome in TECH_DEBT.md.
3. Once `build` passes on the PR, merge and confirm on the resulting push-triggered run that
   `deploy` actually executes.
4. Re-run the live check from the shoo investigation (`curl -i -X POST
   https://cro-api.azurewebsites.net/birds/{id}/shoo`) and confirm it now returns a proper
   JSON `{"error": "..."}` 404 (app-level, route exists) instead of the empty-body routing-miss
   404 - proof the new build actually reached prod.
5. Mark the TECH_DEBT.md entry resolved with this evidence, and add a new lower-priority entry
   for the deferred "reduce emulator dependency surface" idea (non-goal above) as a future
   option if CI ever strains again.

## Files touched

- `.github/workflows/dotnet-ci.yml` - emulator image/flags, readiness probe, connection
  string, new failure-notification step/job
- `CLAUDE.md` - correct the two gotchas that become inaccurate once CI matches local dev's
  emulator
- `TECH_DEBT.md` - close out the CI entry with verification evidence; add the deferred
  test-architecture idea as a new item
