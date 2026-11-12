# Dawak — Flutter conventions (read before writing any screen)

This is the contract between the foundation (already written) and the feature areas. **Nothing here has been compiled**: the Flutter SDK cannot be installed in the build environment, so every Dart file is checked only by `tool/check_dart_syntax.py` (tree-sitter, syntax only) and `tool/static_checks.py` (imports, translations, routes, hygiene). Write code that a strict `flutter analyze` would accept: explicit types, no unused imports, `const` where possible, no `dynamic` leaks, trailing commas.

## 1. Layout

```
lib/
  app/            theme, routes (app_routes, route_policy, session_snapshot, auth_middleware, page_factory, app_pages), bindings/dependencies.dart, app.dart
  core/           config, errors (AppFailure), i18n, base (BaseController, Paged, ShellController/Nav), services (SessionService, LocaleService), utils, widgets
  data/           models, datasources (ApiClient, AuthGateway, FileStore + Supabase impls), repositories
  features/<area>/  area = auth | customer | pharmacist | admin
      <area>_pages.dart      -> `List<GetPage<dynamic>> <area>Pages()`  (uses appPage(...), never GetPage directly)
      i18n/<file>_ar.dart, <file>_en.dart
      controllers/  views/  widgets/ (area-private widgets)  services/ (area-private helpers)
test/
  support/        fake_api.dart (FakeApiClient, FakeAuthGateway, FakeFileStore), fixtures.dart (Fx), harness.dart (AppHarness)
  <area>/         controller tests
```

Dependencies point inward only: views → controllers → repositories → ApiClient. Views never touch repositories or `ApiClient`. Features never import another feature's files (shared things live in `core/` or `data/`). Imports are **relative** inside `lib/`; tests import `package:dawak/...`.

## 2. Controllers, bindings, pages

* Controllers extend `BaseController` (`core/base/base_controller.dart`). Constructor parameters are optional and default to `Get.find<...>()` so tests can inject fakes:
  ```dart
  class OrdersController extends BaseController {
    OrdersController({OrderRepository? orders, SessionService? session})
        : _orders = orders ?? Get.find<OrderRepository>(), _session = session ?? Get.find<SessionService>();
  ```
* Reads: `await load(() async {...}, isEmpty: () => list.isEmpty)` sets `status` (loading/ready/empty/error) and `failure`. Pull-to-refresh uses `silent: true`.
* Writes: `final r = await submit<T>(() => repo.something())` — returns null on failure (toast + `failure` set), ignores a second call while `submitting.value`. Buttons bind `loading: c.submitting.value`.
* Lists: `Paged<T>(fetch: (offset, limit) => ...)` + `PagedListView<T>`; call `paged.reload()` in `onInit`/`onReady`.
* Never show `e.toString()` or server text. Failures are shown through `failureText(AppFailure)` / `ErrorState`. Success messages: `AppToast.success('key'.tr)`.
* Server rejections (`product_unavailable`, `price_changed`, `invalid_transition`, `reservation_expired`, `request_closed`, `too_many_requests`, …) must leave the screen in a consistent state: re-fetch what is displayed, keep the user's input, and explain with the translated message. Do not assume success until the repository call returned.
* Bindings: `appPage(AppRoutes.x, () => const XPage(), binding: BindingsBuilder(() { Get.lazyPut(() => XController()); }))`. Same controller type on two routes that can be open at once → use `tag:`.
* Route parameters: `Get.parameters['id']`; arguments only for transient data (never for anything the page cannot rebuild from the id after a restart — fetch by id instead).
* Navigation: `Get.toNamed(AppRoutes.xOf(id))` (builders in `AppRoutes`); replace stacks with `Get.offAllNamed`/`Get.offNamedUntil`; go to a tab with `Nav.toTab(ShellTag.customer, 2)`. Tab-root screens are wrapped in `DoubleBackExit`.
* Guards run for every named navigation (`AuthMiddleware` → `RoutePolicy`). Do not add ad-hoc role checks in views except to hide controls; the database is the authority.
* Money: `Fmt.money(amount, currency)` (shows ل.س or $), always inside `LtrText`/`InfoRow(ltr: true)` when alone on a line. Currency comes from the pharmacy/order/sale row, never hard-coded. Quantities and prices are `int`/`double` from models; the server's totals are authoritative (a client preview may differ by rounding only).
* Idempotent creates (`create_order`, `create_pos_sale`, `create_availability_request`, bulk import): keep an `IdempotencyKeeper` (the ask-nearby key is built from the medicine and the 4-decimal position);  `keeper.keyFor(signature)` where signature = a stable string of pharmacy + lines + discount/notes; call `keeper.clear()` only after success. A retry of the same payload after a network error must reuse the key.

## 3. UI rules

* Colours only from `AppColors` / `context.palette` / theme (no `Color(0x…)`, no `Colors.*` — `static_checks.py` fails them). Use `AppDims` for radii/padding. Light **and** dark must both look right: never hard-code white/black text.
* State is never conveyed by colour alone: use `StatusChip`/`OrderStatusChip`/`FreshnessChip`/`RequestStatusChip`/`ApprovalChip` (icon + text), `NoticeBanner` (icon + text), `AppToast` (icon + text).
* Every loading screen supports four states through `AsyncStateView` (loading / error+retry / empty / content). Forms: inline validation with `Validators.*`, disabled + spinner while submitting, error banner/toast on failure.
* Touch targets ≥ 48 dp; `Semantics` labels on icon-only buttons (`tooltip:` on `IconButton`). Text must survive 1.4× text scale (use `Flexible`/`Expanded`, `maxLines` + ellipsis, scrollable pages).
* RTL: use `EdgeInsetsDirectional`, `AlignmentDirectional`, `TextAlign.start/end`; never `left`/`right`. Phone numbers, e-mail, codes, amounts: `LtrText`. Back/forward icons: `Icons.arrow_back_rounded` mirrors automatically; use `Icons.chevron_right_rounded` only inside widgets that mirror (ListTile trailing does not — use `Icons.arrow_forward_ios_rounded` sparingly with `matchTextDirection: true`).
* Every button must do something real. No dead `onPressed`. Features that are out of scope (returns/refunds P-53, employee management P-71) are **not shown**.
* **There are no stock quantities anywhere** (see `availability_design.md`). Customers see a pharmacy as *available* with a price and how recently it was confirmed (`FreshnessChip`: `recent` ≤ 7 days, `old` ≤ 30 days); never write "X units left". Never present availability as a guarantee: reserving is a request that the pharmacy answers, and the pharmacy's acceptance is its promise to keep the order for 24 hours.
* Location: always through `LocationService`/`CustomerLocation` (never `Geolocator` directly, never throws, 5-minute cache). A denied or unavailable location is a normal state: the screen keeps working without distances and shows `LocationNotice` with a way to retry or open the system settings. Directions and maps are plain links (`MapLinks`), no map SDK.
* Destructive actions (cancel, reject, suspend, disable, discard) → `confirmDialog` / `reasonDialog` that states the consequence.
* Pull-to-refresh on lists; after a mutation refresh the visible data from the server.

## 4. Shared API (what already exists)

**Base/services**: `BaseController` (`status`, `failure`, `submitting`, `load`, `submit`), `failureText(f)`, `Paged<T>` (the latest reload wins), `ShellController(tabCount)` + `ShellTag` (`customer`, `pharmacist`, `admin`), `Nav.toTab`, `OffAll`/`defaultOffAll`, `BaseController.reportToSession(failure)` (lets a background poll report a failure to the session guard without a toast), `SessionService` (`snapshot`, `state` Rx, `profile`, `pharmacy`, `role`, `memberRole`, `email`, `signedIn`, `homeRoute`, `refresh()`, `signOut()`, `discardSession()`, `routeAfterLogin()`; the pharmacist pending screen is refreshed automatically every 30 s), `LocaleService` (`isArabic`, `locale`, `setLocale`, `toggle`, `onboardingDone`), `LocationService` + `LocationGateway` (`GeolocatorGateway` in production, `FakeLocationGateway` in tests; failures `location_off`, `location_denied`, `location_denied_forever`, `location_timeout`, `location_unavailable`).

**Widgets** (`core/widgets/`): `AppButton(label, onPressed, variant, icon, loading, expand)`, `AppTextField(label, controller, ltr, obscure, validator, keyboardType, maxLength, maxLines, prefixIcon, …)`, `SearchField(onChanged, onSubmitted, hint)`, `AsyncStateView(status, failure, onRetry, builder, empty)` / `.of(controller, …)`, `EmptyState`, `ErrorState`, `PagedListView<T>`, `StatusChip`, `OrderStatusChip`, `FreshnessChip`, `RequestStatusChip`, `ApprovalChip`, `NoticeBanner`, `AppCard`, `SectionCard`, `StatCard`, `InfoRow`, `BottomActionBar`, `QuantityStepper`, `BarChart`, `BrandLogo`, `LtrText`, `DoubleBackExit`, dialogs (`confirmDialog`, `reasonDialog`, `choiceSheet`), `AppToast` (`success/error/info`).

**Utils**: `Validators` (`required, email, password, confirmPassword(()=>…), phone, optionalPhone, length(min,max), price, integer(min,max), parseDecimal, parseInt`), `Fmt` (`money, number, dateTime, date, time, distance, ago, remaining`), `GeoParse` (pasted map link or `lat, lng` text → `GeoPoint`), `MapLinks` (`directions`, `place`), `cleanPhone`, `normalizeSearch`, `Debouncer`, `IdempotencyKeeper`, `newIdempotencyKey`.

**Repositories** (all registered permanently in `registerCoreDependencies`; fetch with `Get.find<T>()`):
```
AuthRepository       signIn signUp signOut resetPassword resendConfirmation updatePassword myProfile updateProfile({displayName,phone,locale}) myPharmacy
PharmacyRepository   register(PharmacyDraft) resubmit(id, draft) updateMine(id,{name,phone,addressLine,neighborhood,city,directions,hours,showPhonePublicly,isListed,location}) listPublic({query,city,near,limit,offset}) getPublic(id) adminList({status,text,limit,offset}) adminGet(id) adminReview(id, decision approve|reject|suspend|reinstate, {reason})
MedicineRepository   categories search(q,{categoryId,dosageForm,limit,offset}) getById offers(medicineId,{city,near,radiusKm,limit,offset}) (only pharmacies confirmed within 30 days; nearest first with `near`) pharmacyCatalogue(pharmacyId,{query,categoryId,limit,offset}) propose(MedicineDraft)->(id,status,existed) adminList({status,text,limit,offset}) adminCreate(draft,{status='approved'}) adminUpdate(id,draft) (StateError when no row was updated) adminReview(id, approve|reject|archive) saveCategory({id,nameAr,nameEn,sortOrder,isActive}) (StateError when no row was updated)
ListingRepository    products(pharmacyId,{text,filter all|available|unavailable|stale,categoryId,limit,offset}) product(id) sellable(pharmacyId,{text,limit,offset}) addProduct({pharmacyId,medicineId,price}) updateProduct(id,{price,isAvailable}) confirmListing(pharmacyId) bulkUpsert(pharmacyId, List<ListingEntry>, {onProgress}) (chunks of 500) matchNames(names,{onProgress}) (chunks of 100, up to 3 suggestions per name)
AvailabilityRepository create({medicineId, from: GeoPoint, idempotencyKey}) get(id) expand(id) close(id) mine({limit,offset}) openCount(pharmacyId) inbox(pharmacyId,{onlyOpen,limit,offset}) answer({pharmacyId, requestId, available, price})
SalesRepository      createPosSale({pharmacyId, items: List<OrderLineInput>, discount, idempotencyKey}) getSale(id) history(pharmacyId,{from,to,invoiceQuery,limit,offset})
OrderRepository      create({pharmacyId,items,idempotencyKey,notes,contactPhone}) myOrders({activeOnly,limit,offset}) getOrder(id) cancelByCustomer(id,{reason}) pharmacyOrders(pharmacyId,{statuses,limit,offset}) expireReservations(pharmacyId) accept reject(id,reason) reactivate markReady cancelByPharmacy(id,reason) complete(id, reference)->Sale findByRef(pharmacyId, ref)->Order?
DashboardRepository  load(pharmacyId,{from,to}) -> DashboardData
NotificationRepository list unreadCount markRead(id)
SupportRepository    submitReport({targetType,targetId,category,description}) myReports
AdminRepository      metrics() reports({statuses,limit,offset}) report(id) resolveReport(id,status in_review|resolved|dismissed,{note}) accounts({text,role,limit,offset}) setAccountStatus(userId,{suspended,reason}) auditLog({actions,limit,offset}) names(ids)->Map<id,display_name>
FileStore (Get.find<FileStore>())  uploadLicense({userId,fileName,bytes,contentType}) -> path;  signedLicenseUrl(path)
```
Models are in `data/models/` (`Order`, `OrderItem`, `OrderLineInput`, `Sale`, `SaleItem`, `SaleSummary`, `Medicine`, `MedicineDraft`, `MedicineCategory`, `PharmacyProduct` (`isAvailable`, `confirmedAt`, `freshness()`, `isStale()`), `MedicineOffer`, `PublicProduct`, `NameMatch`, `ImportResult`, `GeoPoint`, `AvailabilityRequest` (`phase`-relevant getters `hasOffers`, `allSaidNo`, `nobodyInRange`, `canSearchFurther`, `nextRadiusKm`, `radiiKm` = 1/3/5/10), `AvailabilityOffer`, `AvailabilityRequestSummary`, `InboxRequest`, `PublicPharmacy`, `Pharmacy`, `PharmacyDraft`, `OpeningHours`, `DayHours` (day 0 = Saturday), `DashboardData`, `AppNotification`, `UserReport`, `AuditLogEntry`, `AccountSummary`, `PharmacyApplication`, `AdminMetrics`, enums). Read the model file before using a field; do not invent fields. If a repository method you need is missing, add it to the repository (keep it thin: one RPC/table call, map to a model) and mention it in your final report.

**Admin area helpers** (`features/admin/services/`): `adminConfirm` / `adminReason` (injectable `AdminConfirmFn` / `AdminReasonFn` dialog hooks, so tests answer dialogs without a widget tree) and `AdminRefresh.pharmaciesChanged / medicinesChanged / reportsChanged` (refresh the open list and the dashboard metrics when they are registered). Per-record controllers are registered with `tag: id` (the medicine editor uses tag `'new'` for creation). Admin accounts can read non-customer profiles only; customers never appear in the accounts list (privacy).

## 5. Database contract (do not guess)

The authoritative list is `docs/database_schema.md` and `supabase/migrations/`. Key facts: customers cannot read `pharmacies`/`pharmacy_products`/`availability_*` (only masked RPCs; orders carry a snapshot `pharmacy_name/address/phone`; pharmacies never see who asked a nearby question or from where); the database stores no quantities; orders: pending → accepted (the pharmacy's promise to hold it for 24 h) → ready_for_pickup → completed (creates the sale); rejected / cancelled / expired; `reactivate_order` is a *pharmacy* action on expired orders (a new 24 h promise); cashiers see only their own sales, cannot discount, cannot change prices/settings, and their answers to customers' questions do not update the list (owner/manager answers do); week starts Saturday; currency SYP (default) or USD per pharmacy; `get_sale` returns `not_found` for sales you may not see; machine error codes map to `err_<code>` translations.

## 6. Translations

* Keys live in `features/<area>/i18n/*_ar.dart` + `*_en.dart` as `const Map<String, String>`. **Prefix per area**: customer `c_`, pharmacist `p_`, admin `a_`, auth `auth_`; core keys (no prefix) are in `core/i18n/core_*.dart` — reuse them (`save`, `cancel`, `retry`, `order_status_*`, `avail_*`, `err_*`, `val_*`, `notif_*`, `unit_*`, …) instead of duplicating. A key is defined once, in both languages, with the same `@placeholders`. Placeholders: `'c_total_items'.trParams({'n': '3'})` with `'… @n …'`.
* Use literal keys at use sites: `'c_cart_empty'.tr` (the checker only sees literals and `'prefix_${x}'.tr`). Arabic is the primary language: write natural Syrian-friendly Modern Standard Arabic; English must be real English, not a transliteration.
* Aggregator `core/i18n/app_translations.dart` already imports: customer → `customer_ar/en.dart` (`customerAr`/`customerEn`), pharmacist → `pharmacist_ar/en.dart` (`pharmacistAr`/`pharmacistEn`) and `pharmacist_ops_ar/en.dart` (`pharmacistOpsAr`/`pharmacistOpsEn`), admin → `admin_ar/en.dart` (`adminAr`/`adminEn`). Overwrite only the file(s) your brief assigns.

## 7. Tests (write them, they will be run later by someone with the SDK)

* Controller tests use `AppHarness.create()` (fakes registered like production, translations loaded) and `FakeApiClient.rpcs['accept_order'] = (p) => Fx.orderRow(...)` handlers; assert on `api.rpcLog`, state and navigation. Use `testWidgets` only when a `Form` must be mounted (see `test/auth/auth_controllers_test.dart` for the pattern) or for widget-state tests.
* Cover: happy path, each server error code the screen can get (state left consistent, translated failure), validation, double-submit guard, idempotency-key reuse (POS and checkout), role-dependent behaviour.
* Header comment of each test file: `// UNRUN: written without the Flutter SDK; verify with flutter test.`
* Put fixtures you need in the test file or extend `test/support/fixtures.dart` with additive helpers only.

## 8. Definition of done for a feature area

1. Every route of the area in `docs/screen_registry.md` has a page in `<area>_pages.dart` (static paths before parameterised ones) and the screens described there (states, validation, empty/error, navigation, buttons all wired).
2. Translations ar + en complete; `python3 tool/static_checks.py` shows **no failure attributable to your area**; `tool/check_dart_syntax.py` reports 0 syntax errors.
3. Controller tests written for every controller with logic.
4. Final report lists: files created, repository methods added, decisions/assumptions, anything not done — and states plainly that nothing was compiled or run.

## 9. Static tools (they stand in for a compiler that was not available; they do not replace it)

Run from the repository root; the Python environment needs `pip install tree-sitter tree-sitter-dart`.

| Tool | Finds | Does not find |
|---|---|---|
| `python3 tool/check_dart_syntax.py` | Dart syntax errors in `lib/` and `test/` | anything semantic |
| `python3 tool/static_checks.py` | translation keys used but missing, defined twice, empty, wrongly prefixed, missing in one language or with different placeholders; routes without a page, static routes declared after dynamic ones, routes missing from `screen_registry.md`; unresolvable or absolute imports inside `lib/`; mentions of the service-role key; `Colors.*` / `Color(0x…)` literals; empty or `null` button handlers; `TODO`/`FIXME`; `print()`; `Get.find<T>` for a type nobody registers | wrong translation *values*, keys built from other expressions than `'prefix_${x}'`, and the rules not listed here (directional insets, no cross-feature imports) which are reviewed by reading |
| `python3 tool/xref_checks.py [--verbose]` | (1) a project class or function used without being imported, (2) project imports nothing uses, (3) `x.member` on an explicitly typed project class that has no such member, (4) unknown / missing named arguments or a wrong positional count on project constructors and methods, (5) the same named argument written twice in one call | types of expressions it cannot infer (`var`, generics, framework classes), null safety, overrides, deprecations, framework API drift |

A clean run of all three is **not** a compiled build. `flutter analyze` and `flutter test` remain the authority and were never executed (see `progress.md`).
