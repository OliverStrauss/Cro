# Cro

Cro is a messaging app where users send "cro's" to other people. Each cro travels across
a map in real time, taking physical days to arrive, instead of being delivered instantly.

Built after a summer Internship using a similar tech stack learned while working there. Heavy use and learning of claude and proper Ci/CD practices used in my personal projects for the first time.

## Repository layout

This is a monorepo with two halves:

- **[`/app`](app/)** — Flutter frontend (web, desktop)
- **[`/api`](api/)** — .NET (C#) API backend, backed by Azure Cosmos DB

## Getting started

### Frontend (Flutter)

```bash
cd app
flutter pub get
flutter run
```

### Backend (.NET API)

```bash
cd api
dotnet restore
dotnet run
```

## CI

GitHub Actions builds and tests each half independently — see `.github/workflows/`.
