# Dawak (دواك)

Syrian pharmacy discovery, availability and reservation platform — Flutter (GetX) + Supabase. Roles: customer, pharmacist (owner / manager / cashier), admin. Arabic-first (RTL) with English. Cash at pickup, no map SDK, no service-role key in the app.

**Availability model, not stock.** Pharmacies keep a list of what is available (with price); customers see the confirmed pharmacies nearest first, and can *ask the pharmacies nearby* (1 → 3 → 5 → 10 km, widening automatically). See `docs/availability_design.md`.

## Start here

1. Read `docs/progress.md` — what was actually run and what was not. **No Dart command has ever been run** (no Flutter SDK was available); the SQL side was run on a local PostgreSQL 16 with a Supabase stub.
2. On a machine with Flutter ≥ 3.27: `flutter pub get && flutter analyze && flutter test` (expect to fix compile errors first), see `docs/release_checklist.md` §0.
3. Supabase: either the nine files in `supabase/migrations/` or the single `supabase/combined/dawak_full_schema.sql` (regenerate with `python3 tool/build_full_sql.py`), then schedule the three `pg_cron` jobs (`docs/release_checklist.md` §1).
4. `android/` and `ios/` do not exist yet: `flutter create .` and apply the platform notes (location permissions included) from `docs/release_checklist.md` §2.
5. Run with `flutter run --dart-define-from-file=.env` (copy `.env.example`; only the URL and the anon key).

## Map

| Path | What |
|---|---|
| `lib/` | the app (`app`, `core`, `data`, `features/{auth,customer,pharmacist,admin}`) |
| `test/` | Dart tests (UNRUN) |
| `supabase/migrations/` | the database (9 migrations); `supabase/tests/` SQL, concurrency and mutation tests |
| `tool/` | static checkers that stand in for a compiler (syntax, cross-references, translations/routes) and the combined-SQL builder |
| `docs/` | requirements, design, schema, security model, conventions, screen registry, navigation, release checklist, progress |
