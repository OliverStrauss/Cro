# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Cro is a messaging app where users send "cro's" to other users. Each cro travels across a
map in real time, taking physical days to arrive rather than delivering instantly.

## Repository structure

This is a monorepo with two independently-buildable halves:

- `/app` — Flutter frontend (package name `cro_app`). Configured platforms: Android, Linux,
  Windows, Web (no iOS/macOS scaffolding has been generated).
- `/api` — .NET 10 ASP.NET Core Web API (`CroApp.Api`). Intended to be backed by Azure Cosmos
  DB (chosen for native geospatial query support — relevant for the map/delivery feature) —
  not yet integrated into the API project.
- `/.github/workflows` — CI, split into one workflow per half (see below).

## Commands

### Frontend (Flutter) — run from `/app`

- `flutter pub get` — install dependencies
- `flutter analyze` — lint/static analysis
- `flutter test` — run all tests
- `flutter test test/widget_test.dart` — run a single test file
- `flutter run` — launch the app

### Backend (.NET API) — run from `/api`

- `dotnet restore` — install dependencies
- `dotnet build` — build
- `dotnet run` — run the API locally
- `dotnet list package --include-transitive` — check for vulnerable transitive packages;
  the default `dotnet new webapi` template pulled in a vulnerable `Microsoft.OpenApi`
  transitive dependency, which had to be pinned explicitly to a patched version

## CI

Two GitHub Actions workflows, each scoped to its own `working-directory`, run on push to
`main` and on every pull request:

- `flutter-ci.yml` — `flutter pub get` → `flutter analyze` → `flutter test`, in `/app`
- `dotnet-ci.yml` — `dotnet restore` → `dotnet build`, in `/api`

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
