# Dawak — Release checklist

Everything below is **to be done by a person with the tools** (Flutter SDK, Supabase CLI or dashboard, Android Studio / Xcode). None of it has been executed: the authoring environment had no Flutter SDK, no Supabase CLI and no real Supabase project (see `progress.md`). Tick the boxes as you go.

## 0. First commands on a machine with the Flutter SDK (do this before anything else)

```bash
flutter --version                 # needs Flutter >= 3.27 / Dart >= 3.6 (pubspec.yaml)
flutter pub get
flutter analyze                   # expect errors on the first run: 230 lib files and 37 test files were never compiled
flutter test                      # 738 test cases in 37 files, all UNRUN
```

- [ ] `flutter pub get` resolves (dependency versions in `pubspec.yaml` were chosen without resolving them; `geolocator ^13.0.1` and `excel ^4.0.6` are the two newest additions).
- [ ] `flutter analyze` is clean. Fix compile errors first, then warnings. Typical expected findings: type mismatches, framework API differences between Flutter versions, null-safety flow, deprecations.
- [ ] `flutter test` is green. Test failures may be bugs in the tests *or* in the code; the tests were written against the fakes in `test/support/`, never run.
- [ ] Re-run the three static tools (`docs/flutter_conventions.md` §9) after the fixes; they are cheap.

## 1. Supabase project

- [ ] Create a Supabase project (Postgres 15+). Region close to Syria's users.
- [ ] **Shortcut: one file.** `supabase/combined/dawak_full_schema.sql` is the nine migrations concatenated (17 tables, RLS, RPC functions, storage bucket). Paste it into the SQL editor of a new, empty project and run it once. Regenerate it after any migration change with `python3 tool/build_full_sql.py`. See `progress.md` for what was actually run against it; it has not been run on a real Supabase project.
- [ ] **Apply the nine migrations in order** (`supabase/migrations/*.sql`) with `supabase db push` (linked project) or by pasting them in the SQL editor in file order. They were only ever run on a local PostgreSQL 16 with a stub of the Supabase roles/`auth` schema.
- [ ] **Re-check the database on the real platform.** `supabase/tests/run.sh` creates its own throw-away database, loads a *stub* of Supabase's roles / `auth` / `storage` objects (`00_supabase_stub.sql`) and then the migrations, so it cannot be pointed at a real Supabase project as it is. It passes 59 / 59 on a local PostgreSQL 16 (plus `supabase/tests/concurrency` — 16 scenarios — and `supabase/tests/mutation` — 46 mutants, all detected) and is still the regression suite for any change to the migrations (needs a superuser connection). For the real platform, apply the migrations (previous step) and exercise the flows in §4 with real accounts; porting the SQL tests to run on `supabase start` (impersonating users through `request.jwt.claims`, as the stub's `auth.uid()` does) is a worthwhile follow-up.
- [ ] Validate `supabase/config.toml` against your CLI version (`supabase init` in a scratch folder and diff). It was written by hand and never parsed by the CLI.
- [ ] Auth settings (Dashboard → Authentication):
  - Email + password enabled; **"Confirm email" on** (the app has a verification screen).
  - Minimum password length 8 (same as the app's validator).
  - **Site URL and Redirect URLs** — see "Password recovery and e-mail links" below.
  - SMTP: configure a real SMTP provider before launch (the built-in mailer is rate-limited and meant for testing).
- [ ] API settings: only the `public` schema is exposed (`private` must never be listed); max rows 100.
- [ ] Storage: the licence bucket `pharmacy-documents` is created by migration 9 (private, 5 MiB, PDF / JPEG / PNG only); confirm in the dashboard that it is **private** and that its policies exist. `[storage] file_size_limit` in `config.toml` is only the local default.
- [ ] **Schedule the three maintenance jobs** (none is created by the migrations). Enable the `pg_cron` extension (Dashboard → Database → Extensions), then run once in the SQL editor as `postgres`:

  ```sql
  -- 1. End the 24-hour promise of accepted orders that were not collected.
  select cron.schedule('dawak-expire-reservations', '*/5 * * * *',
    $$ select private.expire_all_reservations() $$);

  -- 2. Keep "ask nearby" requests moving when the customer's app is closed:
  --    widen the radius (1 -> 3 -> 5 -> 10 km), expire requests after 60 minutes, delete requests older than 30 days.
  select cron.schedule('dawak-advance-availability-requests', '* * * * *',
    $$ select private.advance_all_availability_requests() $$);

  -- 3. Purge idempotency keys (the table grows by one row per order / sale / request / import call).
  select cron.schedule('dawak-purge-idempotency-keys', '17 3 * * *',
    $$ delete from public.idempotency_keys where created_at < now() - interval '7 days' $$);
  ```

  What happens without them: orders are still expired lazily when a pharmacist accepts, sells or opens the orders list, and every read of a request applies the widening and expiry rules itself, so nothing becomes wrong — but a customer's promise can stay "active" past 24 h until somebody in that pharmacy touches the system, requests of customers who closed the app are not widened, and old rows pile up. Seven days is far longer than any client retry window for idempotency keys.
- [ ] Confirm the jobs run: `select jobid, jobname, schedule from cron.job;` and, after a few minutes, `select * from cron.job_run_details order by start_time desc limit 10;`.
- [ ] **Push notifications are optional and not implemented.** The database creates a row in `notifications` for every event (including "a customer asked about a medicine" for pharmacies and "a pharmacy answered" for customers), and the app shows them in-app. Without push, a pharmacist sees a customer's question only when the app is open (the requests screen refreshes while it is open). To add push later: a Database Webhook on `notifications` inserts → an Edge Function → FCM/APNs, plus storing device tokens (no table exists for them yet).
- [ ] Seed the catalogue: `supabase/seed.sql` (11 categories, 25 sample medicines; idempotent). The sample medicines are **placeholders**: replace them with a reviewed catalogue before launch.
- [ ] **Create the first administrator** (there is deliberately no app screen for it): sign up in the app with the admin's e-mail, confirm the e-mail, then run `supabase/dev/bootstrap_first_admin.sql` (change the e-mail) in the SQL editor. Expect `UPDATE 1`. Keep your own log of who is an admin.
- [ ] Backups: enable daily backups / PITR on the Supabase plan you use.
- [ ] Get the project URL and the **anon** key (Settings → API). The `service_role` key must never be placed in the app, in this repository or in CI variables used for the app build.

### Password recovery and e-mail links (known gap)

The app requests the reset e-mail (`resetPasswordForEmail`) and the sign-up confirmation e-mail, but **no redirect URL or deep link is configured and there is no "choose a new password" screen**. The link in either e-mail opens whatever the Supabase *Site URL* points to; the session event `passwordRecovery` is mapped in `SupabaseApiClient` but no screen reacts to it. Before launch choose one:

1. Point the Site URL at a small hosted page that completes the reset with `supabase-js` (and tells the user to return to the app), or
2. Add deep-link handling (a custom scheme or app links on Android/iOS), set it as a redirect URL, and add a screen that calls `AuthRepository.updatePassword` after the `passwordRecovery` event.

Sign-up confirmation works without an in-app screen (the user confirms in the browser, returns to the app and signs in), but the same Site URL decision applies.

## 2. Platform projects (`android/` and `ios/` do not exist yet)

The repository contains only `lib/`, `test/`, `assets/`, `pubspec.yaml` and `analysis_options.yaml`.

```bash
flutter create . --project-name dawak --org <your.reverse.domain> --platforms=android,ios
```

Run it in the repository root; it adds the platform folders without touching `lib/` or `test/`. **Check afterwards that `lib/main.dart`, `pubspec.yaml` and `test/` are unchanged** (`flutter create` may add a sample `test/widget_test.dart` that references the template app: delete it).

- [ ] Application id, app name ("دواك" / "Dawak"), launcher icons, splash screen, version.
- [ ] **Android — INTERNET permission in the release manifest.** The template adds it only to the debug/profile manifests; add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml` or release builds cannot reach Supabase.
- [ ] **Android — `<queries>`** in the manifest so `url_launcher` can open `https` links (licence documents) and `tel:` (call the customer):

  ```xml
  <queries>
    <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
    <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>
  </queries>
  ```
- [ ] **Location permissions (the app uses the device GPS for search distances, "ask nearby" and the pharmacy's location).**
  - Android: in `android/app/src/main/AndroidManifest.xml` add `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>` and `<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>`.
  - iOS: in `ios/Runner/Info.plist` add `NSLocationWhenInUseUsageDescription` with a short text in Arabic and English explaining that the location is used to find nearby pharmacies and is never shown to pharmacies. The app never asks for background location.
  - Test on a real device: permission granted, denied once, denied permanently (the screen must offer the system settings), location services switched off, and a very slow fix (the app gives up after 15 s and keeps working without distances).
- [ ] Android: `file_picker` (licence upload and the Excel/CSV price list) uses the system document picker for the PDF / image types it asks for, so no storage permission should be necessary; verify on a real device on Android 10–14. Try a real `.xlsx` exported from a pharmacy program, a `.csv` saved by Excel (UTF-8 and Windows-1256 Arabic) and a file with more than 500 rows (it is sent in chunks).
- [ ] **iOS**: add `NSPhotoLibraryUsageDescription` to `Info.plist` if the picker offers the photo library (text in Arabic and English); add `LSApplicationQueriesSchemes` (`https`, `tel`) if you later switch to `canLaunchUrl`. The app calls `launchUrl` directly.
- [ ] iOS: set the bundle id, signing team, minimum iOS version required by the plugins (`ios/Podfile`), and run `pod install`.
- [ ] `printing` (receipt PDF: share / print) — test sharing and printing on a real Android and a real iPhone; on iPad `share_plus` / `Printing.sharePdf` need a share origin if you add tablet support.
- [ ] Release signing (Android keystore, iOS provisioning). Never commit the keystore.
- [ ] RTL: run on a device whose system language is English and one whose language is Arabic; the app's own language switch (profile / drawer) must override the system locale.

## 3. Build configuration

- [ ] Copy `.env.example` to `.env` (git-ignored) and fill in **only** `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- [ ] Run: `flutter run --dart-define-from-file=.env`; build: `flutter build apk --release --dart-define-from-file=.env` / `flutter build appbundle` / `flutter build ipa`. Without the defines the app shows a developer screen explaining what is missing.
- [ ] Fonts: Cairo 400/500/600/700 are bundled in `assets/fonts/` (SIL OFL; keep `OFL.txt`). Check Arabic and Latin digits render correctly on a device.

## 4. End-to-end checks on a real device against the real project

Walk through the flows that no automated test has exercised on a real backend:

- [ ] Customer: register → confirm e-mail → sign in → search a medicine (with and without allowing the location) → see pharmacies with price, distance and freshness → open a pharmacy → add to cart → place a reservation → see it in "My orders" → cancel one.
- [ ] Pharmacist: register a pharmacy with a licence file and a shop location → status "pending" → (admin approves) → status refresh within 30 s → build the list (add one medicine; import an Excel/CSV file: check the suggested catalogue matches, correct one, skip one, confirm) → "confirm all" → accept the customer's order → mark ready → complete with the reference → receipt appears in sales → print/share the receipt.
- [ ] **Ask nearby, two devices** (a customer in the pharmacy's 1 km, a pharmacist with the app open): customer taps "ask nearby" → the pharmacist sees the question without any customer identity → answers *available with price* → the customer sees the pharmacy with price, distance, directions and "reserve" → the pharmacy's list is updated (owner/manager answer) and the same customer can reserve. Then: an *unavailable* answer from every pharmacy in range widens the circle to 3 km by itself; with nobody answering the circle widens after 3 minutes; "search further" widens it at once; closing the request stops the notifications; a request of a customer who closed the app is still widened by the cron job (§1).
- [ ] Pharmacist: POS sale with a discount (owner/manager) and as a cashier (no discount); a product marked unavailable can still be sold ("the shelf is the truth"); idempotent retry (airplane mode during "complete sale", then retry: one sale only).
- [ ] Admin: approve / reject / suspend / reinstate a pharmacy (reasons required where specified); open the licence (10-minute signed link, external viewer); approve a pharmacist's medicine proposal; edit the catalogue; resolve / dismiss a report; suspend a pharmacist account and check that they are signed out or blocked; audit log shows each action with the actor's name for non-customer actors.
- [ ] Security spot checks with two accounts: a customer cannot see another customer's order, a pharmacist cannot read another pharmacy's sales (`not_found`), nobody but the owner can change pharmacy settings.
- [ ] Timing: an order whose 24-hour promise has ended (set a short `reservation_expires_at` in a test project) becomes `expired` through the cron job within 5 minutes; an unanswered request is widened every 3 minutes and expires after 60.
- [ ] Search performance with a realistic catalogue (the stub test used 30 000 rows: a rare token ≈ 3 ms, a very common 2-letter fragment ≈ 0.35 s).

## 5. Content and legal

- [ ] Privacy policy and terms of use are **placeholders** (`requirements.md` Q-06): have them reviewed by a lawyer and link them from the registration and help screens.
- [ ] Arabic copy review by a native Syrian reader (all 1090 translation keys exist in both languages; wording was never reviewed by a human).
- [ ] Store listing texts, screenshots, age rating, data-safety / privacy-label forms (the app stores e-mail, name, phone, pharmacy data, licence documents, the pharmacy's shop location and, for up to 30 days, the customer's approximate location rounded to ~100 m when asking nearby).
- [ ] Decide on support contact details shown in the help screen.

## 6. Known limitations to accept or fix before launch

Full list in `progress.md` ("Known issues"). The ones that affect launch decisions:

1. All Dart code is uncompiled until §0 is done.
2. Password recovery / e-mail link completion (§1).
3. Notifications are in-app only (no push, §1): pharmacies see customers' questions only while the app is open.
4. Returns / refunds (P-53) and employee management (P-71) are not in the MVP and not shown in the UI.
5. Managers may open the pharmacy settings screens but they are read-only for them (the database allows only owners to change them).
6. `create_pos_sale` prices lines on the server and ignores the client's expected price; a cashier's answer to a customer's question does not update the pharmacy's list (owner/manager answers do).
7. An archived medicine cannot be restored from the app.
8. Customers are not listed in the admin accounts screen, so audit entries made by customers have no actor name.
9. The availability is declared by pharmacies, not counted: a pharmacy can say "available" and be out of the item. The app shows freshness, hides listings older than 30 days and treats an order as the pharmacy's promise; train pharmacists to answer honestly and to use "confirm all".
10. The three `pg_cron` jobs (§1) are required in production.
