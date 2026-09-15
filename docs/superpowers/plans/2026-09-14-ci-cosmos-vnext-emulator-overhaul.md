# CI Cosmos Emulator Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `.NET CI`'s `build` job pass reliably on GitHub Actions' standard (free-tier)
runner so `deploy` actually runs after every merge to `main`, and make a red push-triggered
`main` build impossible to miss again.

**Architecture:** Swap `dotnet-ci.yml`'s Cosmos emulator from the classic, crash-prone
`azure-cosmos-emulator:latest` image to `vnext-preview` (the same image local dev already runs
successfully) - lighter footprint, no known crash bug under resource constraints, plain-HTTP
instead of self-signed-HTTPS. Add a small `notify-on-failure` job that files/comments a GitHub
issue via the built-in token when `build` fails on a push to `main`.

**Tech Stack:** GitHub Actions (YAML), Docker, `actions/github-script@v7`, .NET 10 / xunit
(unchanged - no application code changes in this plan).

**Spec:** `docs/superpowers/specs/2026-09-14-ci-cosmos-emulator-overhaul-design.md`

## Global Constraints

- Stay on the standard `ubuntu-latest` GitHub-hosted runner - no bigger/paid runner (per spec
  Goals).
- No new secrets - the failure-notification job uses only the workflow's built-in
  `GITHUB_TOKEN` (per spec Design §3).
- `CosmosDb:UseEmulator: true` in `appsettings.Development.json` stays unchanged - it's a
  harmless no-op against a plain-HTTP endpoint, not something this plan touches (per spec
  Design §1).
- Do not change `deploy`'s own logic, triggers, or the app's runtime Cosmos/Blob provisioning
  behavior (per spec Non-goals).

---

### Task 1: Swap the CI Cosmos emulator image to `vnext-preview`

**Files:**
- Modify: `.github/workflows/dotnet-ci.yml:66-112` (the `Run tests against the Cosmos
  emulator...` step)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the `build` job's Cosmos emulator container now runs `vnext-preview` on plain
  HTTP - Task 4's verification run and Task 6's TECH_DEBT.md update both depend on this being
  in place first.

- [ ] **Step 1: Replace the emulator step's `run:` block and `env:` block**

Replace the entire step (currently `.github/workflows/dotnet-ci.yml:66-112`) with:

```yaml
      - name: Run tests against the Cosmos emulator, retrying on emulator crashes
        run: |
          # vnext-preview - the same image local Apple Silicon dev already runs (see
          # CLAUDE.md's "Setup - Cosmos DB Emulator") - is GA and documented to support both
          # amd64 (what this runner uses) and ARM64. Replaces the classic x64 image, whose own
          # documented crash bug under GitHub Actions' resource constraints (a fatal error in
          # its Windows-compat layer) is why this retry loop existed - see TECH_DEBT.md for the
          # two prior fix attempts (provisioning dedup, retry-with-backoff) that didn't resolve
          # it because neither addressed the emulator image itself.
          max_attempts=3
          for attempt in $(seq 1 "$max_attempts"); do
            echo "=== Attempt $attempt/$max_attempts: starting Cosmos emulator ==="
            docker rm -f cosmosdb-emulator >/dev/null 2>&1 || true
            docker run -d --name cosmosdb-emulator \
              -p 8081:8081 -p 1234:1234 \
              mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview

            # vnext-preview serves plain HTTP, not HTTPS - no self-signed cert to handshake
            # against, so this is the same plain-HTTP probe CLAUDE.md already documents for
            # local dev ("poll http://localhost:8081/ (200 once ready)"), not the classic
            # image's auth-free-static-file workaround this replaces.
            ready=false
            for i in $(seq 1 150); do
              curl -sf --max-time 5 http://localhost:8081/ -o /dev/null && { ready=true; break; }
              sleep 2
            done
            if [ "$ready" != "true" ]; then
              echo "Emulator did not become ready in time, retrying with a fresh container..."
              docker logs cosmosdb-emulator 2>&1 | tail -100
              continue
            fi

            if dotnet test CroApp.Api.Tests/CroApp.Api.Tests.csproj --no-build; then
              exit 0
            fi
            echo "Test run failed on attempt $attempt, retrying with a fresh emulator..."
            docker logs cosmosdb-emulator 2>&1 | tail -100
          done
          echo "All $max_attempts attempts failed."
          exit 1
        env:
          CosmosDb__ConnectionString: "AccountEndpoint=http://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="
          BlobStorage__ConnectionString: "UseDevelopmentStorage=true"
```

Note what's gone versus the old step: `--shm-size=1g`, the `10251-10254` port range, and the
`AZURE_COSMOS_EMULATOR_PARTITION_COUNT`/`AZURE_COSMOS_EMULATOR_ENABLE_DATA_PERSISTENCE` env
vars - all classic-image-only flags with no `vnext-preview` equivalent (it doesn't pre-allocate
a fixed partition count the way the classic image does, which is itself most of the reduced
footprint). Connection string scheme changed from `https://` to `http://`.

- [ ] **Step 2: Validate YAML syntax locally**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/dotnet-ci.yml'))" && echo VALID`
Expected: `VALID` (catches indentation/syntax mistakes before pushing - this cannot validate
the actual GitHub Actions semantics, only that the file parses)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/dotnet-ci.yml
git commit -m "Swap CI's Cosmos emulator from the classic image to vnext-preview

Removes the classic azure-cosmos-emulator:latest image's documented crash
bug under GitHub Actions' resource constraints entirely, rather than
continuing to tune retry/backoff parameters around it (two prior attempts
at that - provisioning dedup in #193, retry-with-backoff in #210 - both
still failed 186/186 on the actual runner despite passing locally).
vnext-preview is the same image local dev already runs reliably.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Add a failure-notification job

**Files:**
- Modify: `.github/workflows/dotnet-ci.yml` (append a new top-level job after `deploy`)

**Interfaces:**
- Consumes: the `build` job's pass/fail result (`needs: build`).
- Produces: an open GitHub issue titled `.NET CI failing on main` whenever `build` fails on a
  push to `main`; nothing else in this plan depends on this job's output.

- [ ] **Step 1: Append the `notify-on-failure` job**

Add this as a new top-level job at the end of `.github/workflows/dotnet-ci.yml` (after the
existing `deploy` job, same indentation level as `build`/`deploy`):

```yaml

  # Auto-files (or comments on an existing open) GitHub issue when `build` fails on a push to
  # main, so a red main build can't silently go unnoticed the way it did for two days before
  # this job existed - see TECH_DEBT.md. Runs on the workflow's built-in GITHUB_TOKEN, no new
  # secrets. Looks up existing issues by title rather than a label, so it has no dependency on
  # a label existing in the repo first.
  notify-on-failure:
    needs: build
    if: failure() && github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            const title = '.NET CI failing on main';
            const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
            const { data: openIssues } = await github.rest.issues.listForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
              state: 'open',
            });
            const existing = openIssues.find((i) => i.title === title && !i.pull_request);
            if (existing) {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: existing.number,
                body: `.NET CI failed again on \`main\`: ${runUrl}`,
              });
            } else {
              await github.rest.issues.create({
                owner: context.repo.owner,
                repo: context.repo.repo,
                title,
                body: `The \`build\` job failed on a push to \`main\`, which blocks \`deploy\` from running.\n\nFailed run: ${runUrl}\n\nClose this issue once \`build\` is green again on \`main\`.`,
              });
            }
```

- [ ] **Step 2: Validate YAML syntax locally**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/dotnet-ci.yml'))" && echo VALID`
Expected: `VALID`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/dotnet-ci.yml
git commit -m "Auto-file a GitHub issue when .NET CI fails on main

Nothing notified anyone when the push-triggered workflow failed on main -
flagged twice in TECH_DEBT.md as a direct contributor to deploy silently
sitting broken for two days. Uses the built-in GITHUB_TOKEN, no new
secrets; looks up existing open issues by title to avoid filing a
duplicate on every red run in a row.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Correct CLAUDE.md's now-inaccurate Cosmos/CI gotchas

**Files:**
- Modify: `CLAUDE.md` (the "Gotchas" bullet list, and the "CI" section's `dotnet-ci.yml` bullet)

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Replace the "CI uses a different Cosmos image" gotcha**

Find this bullet in `CLAUDE.md`'s "Gotchas" section:

```
- **CI uses a different Cosmos image**: `appsettings.Development.json` sets
  `CosmosDb:UseEmulator: true`, which makes the API accept any TLS cert unconditionally —
  needed for CI's *different* emulator image (the classic x64 one, which serves a
  self-signed HTTPS cert), and harmless here since no TLS handshake ever happens against
  this image's plain-HTTP port. This flag must never be true against a real endpoint.
```

Replace it with:

```
- **`CosmosDb:UseEmulator: true` accepts any TLS cert unconditionally** (set in
  `appsettings.Development.json`) — a no-op today against both local dev's and CI's emulator,
  since both now run the plain-HTTP `vnext-preview` image and no TLS handshake ever happens
  against either. Kept in case either environment ever serves a self-signed HTTPS cert again.
  This flag must never be true against a real endpoint.
```

- [ ] **Step 2: Correct the `dotnet-ci.yml` bullet in the "CI" section**

Find this bullet:

```
- `dotnet-ci.yml` — runs a Cosmos emulator service container (the standard x64 image, not the
  ARM64 `vnext-preview` local dev needs) via the declarative `services:` block, plus Azurite
  started as a plain `docker run` step (the `services:` block can't pass `--skipApiVersionCheck`
  through — it always runs an image's default command, no args), waits for both to be ready,
  then `dotnet restore`/`build`/`test` against `CroApp.Api.Tests`, in `/api`
```

Replace it with:

```
- `dotnet-ci.yml` — runs the Cosmos emulator (`vnext-preview`, the same image local dev uses —
  see "Setup — Cosmos DB Emulator" above) via a manual `docker run` step wrapped in a
  fresh-container retry loop (up to 3 attempts — a still-possible emulator crash/hang under
  GitHub Actions' resource constraints can't be recovered by restarting a declarative
  `services:` container mid-job), plus Azurite started as a plain `docker run` step (its
  `--skipApiVersionCheck` flag isn't passable through a declarative `services:` block either),
  waits for both to be ready, then `dotnet restore`/`build`/`test` against `CroApp.Api.Tests`,
  in `/api`. A `build` failure on a push to `main` also files (or comments on an existing)
  GitHub issue so it can't go unnoticed.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Correct CLAUDE.md's Cosmos/CI docs for the vnext-preview swap

Both gotchas described the classic emulator image and a services: block
CI no longer uses (that description predates the manual-docker-run retry
loop rewrite). Updated now that CI and local dev share the same
vnext-preview image and plain-HTTP connection.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Push, open a PR, and verify its own CI run

This is the real acceptance test for Tasks 1-2: `dotnet-ci.yml` is itself in the workflow's
trigger `paths`, so the PR's own `pull_request`-triggered run exercises the new emulator setup
on GitHub Actions' actual runner before anything merges - this is the only way to know whether
the vnext-preview swap actually fixes the problem, since it couldn't be reproduced locally in
the first place (local ARM64 runs always passed).

**Files:** none (git/gh operations only)

**Interfaces:**
- Consumes: Tasks 1-3's commits.
- Produces: a pass/fail signal that determines whether Task 5 (fallback) runs.

- [ ] **Step 1: Push the branch**

```bash
git push -u origin fix/ci-cosmos-vnext-emulator
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "Swap CI's Cosmos emulator to vnext-preview + notify on main CI failure" --body "$(cat <<'EOF'
## Summary
- Swaps dotnet-ci.yml's Cosmos emulator from the classic, crash-prone azure-cosmos-emulator:latest image to vnext-preview - the same image local dev already runs reliably - removing the classic image's documented crash bug under GitHub Actions' resource constraints instead of continuing to tune retry/backoff parameters around it (two prior attempts at that, #193 and #210, both still failed 186/186 on the actual runner despite passing locally).
- Adds a notify-on-failure job that files/comments a GitHub issue via the built-in GITHUB_TOKEN when build fails on a push to main, closing a gap flagged twice in TECH_DEBT.md that let this go unnoticed for two days.
- Corrects two CLAUDE.md gotchas that described the old classic-image/services: block setup.
- Spec: docs/superpowers/specs/2026-09-14-ci-cosmos-emulator-overhaul-design.md

## Test plan
- [ ] This PR's own pull_request-triggered .NET CI run passes against the new vnext-preview emulator (the real test - local runs always passed even before this fix).
EOF
)"
```

- [ ] **Step 3: Watch this PR's own CI run to completion**

```bash
sleep 15
RUN_ID=$(gh run list --workflow=dotnet-ci.yml --branch=fix/ci-cosmos-vnext-emulator --event=pull_request --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID" --exit-status
```

Expected: exits 0 (the run's `build` job passed). This is a deliberate, one-time check of this
specific PR's own verification run (the acceptance test this plan's whole purpose is to
produce), not open-ended CI babysitting - report the result either way and stop here
regardless of outcome; do not proceed to merge (merging is Oliver's call, not this plan's).

- [ ] **Step 4: If Step 3 failed, run Task 5. If it passed, skip to Task 6.**

---

### Task 5 (contingency - only if Task 4's run failed): Fall back to tuning the classic image

Only execute this task if Task 4 Step 3 exited non-zero. This applies the spec's approach-2
fallback: keep the classic image, but cut its partition count down from the current
CI-unfriendly footprint - Microsoft's own CI-oriented guidance is a small partition count
(this plan uses 3).

**Files:**
- Modify: `.github/workflows/dotnet-ci.yml` (revert the emulator `docker run`/probe/connection
  string to the classic image, with a reduced partition count)

**Interfaces:**
- Consumes: Task 4's failure signal.
- Produces: an alternate `build` job configuration; re-triggers Task 4's verification loop.

- [ ] **Step 1: Revert to the classic image with a reduced partition count**

Replace Task 1's `docker run`/readiness-probe/`env:` block with:

```yaml
      - name: Run tests against the Cosmos emulator, retrying on emulator crashes
        run: |
          # vnext-preview turned out to still be unreliable on this runner (see the failed
          # verification run linked from this commit) - falling back to the classic image with
          # a much smaller partition count than the previous 10, per Microsoft's own
          # CI-oriented guidance, to reduce its memory/CPU footprint instead.
          max_attempts=3
          for attempt in $(seq 1 "$max_attempts"); do
            echo "=== Attempt $attempt/$max_attempts: starting Cosmos emulator ==="
            docker rm -f cosmosdb-emulator >/dev/null 2>&1 || true
            docker run -d --name cosmosdb-emulator \
              --shm-size=1g \
              -p 8081:8081 -p 10251-10254:10251-10254 \
              -e AZURE_COSMOS_EMULATOR_PARTITION_COUNT=3 \
              -e AZURE_COSMOS_EMULATOR_ENABLE_DATA_PERSISTENCE=false \
              mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:latest

            ready=false
            for i in $(seq 1 150); do
              curl -sk -f --max-time 5 https://localhost:8081/_explorer/emulator.pem -o /dev/null && { ready=true; break; }
              sleep 2
            done
            if [ "$ready" != "true" ]; then
              echo "Emulator did not become ready in time, retrying with a fresh container..."
              docker logs cosmosdb-emulator 2>&1 | tail -100
              continue
            fi

            if dotnet test CroApp.Api.Tests/CroApp.Api.Tests.csproj --no-build; then
              exit 0
            fi
            echo "Test run failed on attempt $attempt, retrying with a fresh emulator..."
            docker logs cosmosdb-emulator 2>&1 | tail -100
          done
          echo "All $max_attempts attempts failed."
          exit 1
        env:
          CosmosDb__ConnectionString: "AccountEndpoint=https://localhost:8081/;AccountKey=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="
          BlobStorage__ConnectionString: "UseDevelopmentStorage=true"
```

- [ ] **Step 2: Revert Task 3's CLAUDE.md edits**

`git checkout HEAD~3 -- CLAUDE.md` (or manually restore the two original bullets) - they
described the classic image and are accurate again now.

- [ ] **Step 3: Commit, push, and re-run Task 4's verification (Steps 1-3) against this fallback**

```bash
git add .github/workflows/dotnet-ci.yml CLAUDE.md
git commit -m "Fall back to a reduced-partition classic Cosmos emulator image

vnext-preview's own verification run was still unreliable on GitHub
Actions (see linked run). Reverting to the classic image but cutting
AZURE_COSMOS_EMULATOR_PARTITION_COUNT from 10 to 3 to reduce its
footprint, per Microsoft's own CI-oriented guidance.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git push
```

Then repeat Task 4 Step 3's watch loop against the new run.

---

### Task 6: Record the outcome in TECH_DEBT.md

**Files:**
- Modify: `TECH_DEBT.md` (append to the existing CI entry, and add a new entry for the
  deferred test-architecture idea from the spec's Non-goals)

**Interfaces:**
- Consumes: Task 4 (or Task 5)'s verification result.
- Produces: nothing other tasks depend on. This is the final task in this plan - full
  "resolved" closure (confirming `deploy` actually ran and a live `curl` against
  `POST /birds/{id}/shoo` returns a proper JSON 404 instead of a routing-miss 404) happens as a
  follow-up after Oliver merges the PR, not as part of this plan, since merging is his call.

- [ ] **Step 1: Append a dated update to the existing CI entry**

In `TECH_DEBT.md`, after the paragraph ending "...Needs a decision, not another patch." (added
by the earlier `docs/tech-debt-shoo-ci-503-still-broken` investigation), add:

```markdown

**CI overhaul PR opened 2026-09-14 (`fix/ci-cosmos-vnext-emulator`):** swapped the classic
Cosmos emulator image for `vnext-preview` (removes the classic image's own documented crash
bug rather than tuning around it - see the design spec at
`docs/superpowers/specs/2026-09-14-ci-cosmos-emulator-overhaul-design.md`) and added a
`notify-on-failure` job so a red push-triggered `main` build can't go unnoticed again. The
PR's own `pull_request`-triggered run against the new emulator [PASSED / required the
approach-2 fallback described in the same PR - see its commits]. Pending: merge, then confirm
`deploy` actually runs and a live `curl -i -X POST
https://cro-api.azurewebsites.net/birds/{id}/shoo` returns a proper JSON `{"error": "..."}`
404 instead of the routing-miss 404 this investigation found - only then is this entry fully
resolved.
```

Fill in the bracketed sentence based on Task 4/5's actual outcome before committing.

- [ ] **Step 2: Add a new entry for the deferred test-architecture idea**

At the end of `TECH_DEBT.md` (after the last existing entry, following the file's existing
`##`-per-entry format), add:

```markdown

## Integration tests depend entirely on a live Cosmos/Blob emulator - no fake/in-memory repository tier

All ~26 `CroApp.Api.Tests` classes spin up a full `WebApplicationFactory<Program>` against a
real Cosmos emulator and Azurite, with no lighter-weight tier for tests that don't actually
need real Cosmos semantics (partition routing, unique constraints, etc.). This is why CI's
reliability has always been bottlenecked on the emulator's own resource behavior rather than
the test suite's logic - see the CI entry above for the 2026-09-14 emulator-image swap that
addressed the immediate symptom. A fake/in-memory repository implementation for tests that
don't need real Cosmos semantics, reserving the live emulator for a small, deliberately-curated
integration subset, would remove this bottleneck close to entirely rather than depending on
whichever emulator image happens to behave under CI's resource constraints. Sized as a real
test-architecture project, not a CI-config tweak - not undertaken as part of the 2026-09-14
overhaul.
```

- [ ] **Step 3: Commit**

```bash
git add TECH_DEBT.md
git commit -m "Record CI overhaul PR outcome in TECH_DEBT.md

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git push
```

- [ ] **Step 4: Report to Oliver and stop**

Summarize what changed, the verification run's outcome, and that merging + the final
post-deploy live check are next (his call on timing) - per repo convention, do not poll CI or
merge from here.
