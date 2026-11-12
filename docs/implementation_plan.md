# Dawak — Implementation Plan

## Execution order (adapted to what can be verified)

The prompt orders Foundation before Database. Flutter cannot be built in the authoring sandbox, while PostgreSQL can be run and tested, so the **database and security work is done and verified first**; Flutter work follows against a stable RPC contract (`database_schema.md` §7).

| # | Phase | Output | Verification here |
|---|---|---|---|
| 1 | Audit and planning | `docs/*` (this folder) | n/a |
| 2 | Database and security (prompt phase 3) | migrations, RLS, RPC, dev seed, SQL tests, test runner | **run** on local PostgreSQL 16 |
| 3 | Flutter foundation (prompt phase 2) | pubspec, theme, colours, localization (ar/en), routes/guards/bindings, Supabase init, shared widgets, error model | **written; not runnable** — static tools only |
| 4 | Auth + pharmacy onboarding | auth, registration wizard, status screens | written; not runnable |
| 5 | Pharmacy list + POS + dashboard + sales | availability list (add one by one, Excel/CSV import with server-side name matching and review, confirm all), POS, receipts (PDF), dashboard | written; not runnable |
| 6 | Customer discovery + reservations | search with freshness and distance, pharmacy, cart, orders, pharmacist order management | written; not runnable |
| 6b | Availability model (layers 1 + 2 + 3, decided 2026-10-30; replaces the original stock design) | location service, "ask the pharmacies nearby" (customer results/history, pharmacist inbox and answer), radius widening 1 → 3 → 5 → 10 km | **SQL run** (59 tests, 16 concurrency scenarios, 46 mutants); Dart written, not runnable |
| 7 | Admin + integration | approvals, catalogue, reports, audit; route/button audits; workflow tests | written; tests written, not runnable |
| 8 | Release readiness | Android/iOS/Supabase setup docs, release checklist, limitations | `release_checklist.md`, `progress.md` |

Phases 3–8 (including 6b) are all written; **no Dart file has been compiled or run** (see `progress.md`); the SQL of every phase has been run. The first task for anyone with the Flutter SDK is `flutter pub get && flutter analyze && flutter test`.

## Milestone rules

- Each milestone ends with its checks executed and results recorded in `progress.md`. Nothing is marked "passing" unless it was run.
- Dart tests are written together with the feature but flagged **UNRUN** in `progress.md` until a developer runs `flutter test`.
- Anything not completed is listed in `progress.md` as pending with its impact.

## Flutter architecture (feature-first)

```
lib/
  main.dart                      # bootstrap: env, Supabase.initialize, services, runApp
  app/
    app.dart                     # GetMaterialApp, theme, locale, RTL
    routes/{app_routes,app_pages,route_policy,session_snapshot,auth_middleware,page_factory}.dart
    bindings/dependencies.dart   # registerCoreDependencies(api, auth, files, prefs): repositories, locale, session
    theme/{app_colors,app_theme}.dart
  core/
    base/ config/ errors/ i18n/ services/ utils/ widgets/   # BaseController, Paged, ShellController; Env; AppFailure; translations
  data/
    models/  repositories/  datasources/
  features/
    auth/ onboarding/ legal/
    <area>/{<area>_pages.dart, i18n/, controllers/, views/, widgets/, services/}   # area = auth | customer | pharmacist | admin
```

Rules: controllers hold presentation state only; repositories map RPC/table results to models and data sources convert every failure to `AppFailure`; `data/datasources` is the only code that touches `SupabaseClient`; no queries in widgets; one controller instance per screen via bindings; subscriptions and timers are cancelled in `onClose`.

## Localization

Arabic (default) and English through GetX `Translations` (`core/i18n/app_translations.dart`), not ARB files: one `const Map<String, String>` per language and area, keys prefixed per area (core none, `auth_`, `c_`, `p_`, `a_`). `tool/static_checks.py` verifies that every key exists in both languages with the same placeholders and that the same key is never defined twice. RTL comes from the locale; layouts use directional insets and `LtrText` for numbers, codes and phone numbers.

## Dependencies (kept deliberately small)

`get`, `supabase_flutter`, `flutter_localizations` (sdk), `intl`, `shared_preferences`, `pdf`, `printing`, `share_plus`, `file_picker`, `url_launcher`, `geolocator` (device GPS; no map SDK — directions are links), `excel` (reads `.xlsx` price lists; `.csv` is parsed by our own reader), `equatable`. Dev: `flutter_test`, `flutter_lints`, `mocktail`. Charts are drawn with `CustomPainter` to avoid an extra dependency. Environment: Dart `>=3.6.0 <4.0.0`, Flutter `>=3.27.0` (`pubspec.yaml`).

## Configuration

`--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…` (see `.env.example`; values never committed). Only the anon key is ever used on the client. `AUTH_REQUIRE_EMAIL_CONFIRMATION` (dart-define, default `false`) toggles the verification screen.

## Scheduled work on the server

Three `pg_cron` jobs are required in production and are documented, not created, by the migrations: `private.expire_all_reservations()` (5 min), `private.advance_all_availability_requests()` (1 min) and the idempotency-key purge (daily). See `release_checklist.md` §1.

## Risks

| Risk | Mitigation |
|---|---|
| Dart code cannot be compiled in the sandbox | Conservative APIs, small dependency set, explicit `UNRUN` status, first task for the developer: `flutter pub get && flutter analyze && flutter test` and fix findings |
| Stub ≠ real Supabase | Documented; re-run SQL tests with `supabase db reset` + `supabase test db` on a real project |
| Large scope | Registry marks `S`/`A` items as sections so effort goes to routes; deferred items are documented |
| Availability is declared by pharmacies, not counted | Freshness shown on every offer, listings older than 30 days hidden, "confirm all" for pharmacists, and the nearby request asks the pharmacy at the moment the customer needs the answer (`availability_design.md`) |
| Plugin behaviour that only a device shows (GPS permission flow, `.xlsx` parsing) | Isolated behind `LocationGateway` and the import controller; verify on a device first (`release_checklist.md` §3) |
| Arabic font licensing | Cairo (SIL OFL 1.1) — developer downloads the TTFs into `assets/fonts/`; pubspec references them |
