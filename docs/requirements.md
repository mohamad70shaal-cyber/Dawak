# Dawak (دواك) — Requirements

Source of truth: the "Master Development Prompt" plus the concept image. This file records what is in scope, the decisions taken where the prompt left a choice, and what is explicitly deferred.

## 1. Product

Dawak is a Syrian pharmacy discovery, availability, reservation and pharmacy-management platform with three role experiences in one Flutter codebase and one Supabase project:

| Role | Can do |
|---|---|
| Customer | Search medicines, see the pharmacies that confirmed them (nearest first, with price and how recently confirmed), **ask the pharmacies nearby** and see who answered *available*, reserve for cash pickup, track orders |
| Pharmacist (owner / manager / cashier) | Keep the list of available medicines and prices (one by one or from an Excel/CSV file), answer customers' questions, run POS sales, handle reservations, see analytics |
| Admin | Approve/suspend pharmacies, manage catalog, review reports, view audit logs |

Dawak is a search and reservation tool. It does not diagnose, prescribe, recommend alternatives, or substitute medicines. It does not count stock: what customers see is what pharmacies declare (see `availability_design.md`).

## 2. Fixed platform decisions (from the prompt)

Flutter (Android + iOS), Dart null-safety, GetX (state, DI, navigation), Supabase Auth + PostgreSQL + RLS + Storage (documents only), PostgreSQL RPC for sensitive operations, Arabic-first RTL with English localization, no Google Maps SDK (the device GPS gives positions; directions are plain links), cash at pickup only, no delivery, no electronic payments, no service-role key in the app.

## 3. Decisions taken where the prompt left a choice

| ID | Decision | Reason / impact |
|---|---|---|
| D-01 | **Auth identifier is email + password** (Supabase Auth). Phone number is a profile contact field, not a login method. | Password reset and verification work out of the box. The concept image shows phone-number login; Supabase phone auth needs a paid SMS provider and is unreliable for Syrian numbers, and "phone → synthetic email" would break recovery. **Confirmed by the product owner on 2026-10-11.** |
| D-02 | **Currency policy:** each pharmacy declares one currency, `SYP` or `USD`, fixed at registration and immutable after approval. Products, orders and sales inherit it. No FX conversion; a cart is single-pharmacy so currencies never mix. | The prompt forbids silently assuming USD. The concept image shows `$` placeholders. **Confirmed by the product owner on 2026-10-11** (Syrian pound by default, USD optional per pharmacy). |
| D-03 | Money is `numeric(14,2)`; all totals are computed in PostgreSQL. | No floats. |
| D-04 | Timestamps are `timestamptz` (UTC). Day boundaries for analytics use the pharmacy's `timezone` (default `Asia/Damascus`). | Syria is UTC+3 year-round. |
| D-05 | "This week" starts on Saturday; "last 10 days" = today plus the previous 9 calendar days; "this month" = calendar month to date. | Assumption, parameterised in the dashboard RPC. **Q-03.** |
| D-06 | **No stock is stored or reserved.** (Replaces the original "stock is reserved on acceptance", changed 2026-10-30.) The pharmacy lists *available / unavailable* and a price per medicine; accepting an order is the pharmacy's **promise** to prepare it for 24 hours. Creating an order checks only that the product is still available and the price unchanged (`product_unavailable`, `price_changed`). | Pharmacies do not trust an app with their real stock and counts drift from the shelf. Consequence: several customers may hold orders for the same item; the pharmacy answers for what is on its shelf and rejects what it cannot serve. The POS records the sale of any product of the pharmacy ("the shelf is the truth"). |
| D-07 | Orders are **all-or-nothing** (no partial fulfillment, no `confirmed_quantity`). | Prompt: "where supported". |
| D-08 | Reservation lifetime is **24 h** from acceptance (server config). Pending orders do not expire in the MVP. | Config in `private.cfg_int`. |
| D-09 | Every listing carries `confirmed_at`. Customers see a pharmacy as available only if it was confirmed within **30 days**; within **7 days** it is shown as *recent*, otherwise as *old* (with the date). A pharmacist can re-confirm the whole list in one tap. Orderable quantity per medicine is capped (max 10). | Avoid claiming stale availability. |
| D-10 | Cancellation policy: customer may cancel `pending`, `accepted`, `ready_for_pickup`; pharmacy may cancel `accepted`, `ready_for_pickup` with a mandatory reason; pharmacy may reject `pending`. Expired orders can be reactivated by the pharmacy, which starts a new 24 h promise. | Prompt: "if policy permits". |
| D-11 | One pharmacy per owner account in the MVP (unique index). Membership model already supports `owner`/`manager`/`cashier`. | Keeps the app single-pharmacy; schema is ready for more. |
| D-12 | Discounts: fixed amount only, ≤ subtotal, owner/manager only. Cashiers cannot discount. | "Supported discounts with authorization." |
| D-13 | Notifications are **in-app only** (a `notifications` table written by trusted functions). No push / `device_tokens` table in the MVP. | Push needs FCM/APNs setup outside this repo. Consequence: a pharmacy sees a customer's question only while its app is open; push is the first post-MVP improvement (`release_checklist.md` §1). |
| D-14 | Pending-order and realtime updates use pull-to-refresh plus 30 s polling; Supabase Realtime is deferred. | Simpler and safer for MVP. |
| D-15 | Admin cannot read customer profiles or orders. Admin metrics are aggregates; reports expose only what the reporter wrote. | Data minimisation. |
| D-16 | **Three layers of availability** (decided 2026-10-30): (1) the pharmacy's own list; (2) customer search shows only confirmed pharmacies, nearest first when the customer's location is known; (3) **"ask the pharmacies nearby"** for the moment the customer needs a certain answer. | Hybrid chosen by the product owner. Details and rationale: `availability_design.md`. |
| D-17 | "Ask nearby": the pharmacies within **1 km** are notified (nearest 25 at most); a pharmacist answers *available (price)* or *unavailable*; the radius widens automatically **1 → 3 → 5 → 10 km** when the current circle has no pharmacy, every pharmacy answered *unavailable*, or **3 minutes** passed without an answer, and by hand with "search further". A request lives **60 minutes**; at most 3 open requests and 10 per hour per customer. | Server-side (`private.cfg_int`), applied on every read and by a minute-by-minute job. |
| D-18 | **Location privacy.** The device position is used only to sort and to ask; it is rounded to 3 decimals (~100 m) on the server, never shown to pharmacies (the pharmacist sees the medicine and the distance, never who asked or from where), and kept at most 30 days. The pharmacy's own location is public (customers need directions). | Data minimisation; legal text must say so (`progress.md` known issue 13). |
| D-19 | Pharmacy locations come from the device GPS (set in the registration wizard or in settings) or from a pasted map link / `lat, lng`. Directions are `https://www.google.com/maps/dir/` links opened outside the app. | No map SDK, no API key. |
| D-20 | **Excel/CSV import.** A pharmacist can upload the price list exported from the pharmacy program (`.xlsx`, `.csv`, UTF-8 or Windows-1256); names are matched to the shared catalogue on the server (trigram word similarity, up to 3 suggestions per name); the pharmacist reviews and confirms; up to 500 rows per call, larger files are sent in chunks. | The fastest way to fill the list for a pharmacy with hundreds of items. |
| D-21 | A cashier's answer to a customer's question is recorded on the request but does **not** change the pharmacy's list; owner and manager answers do. | Cashiers cannot change prices or settings (D-12). |

## 4. Functional scope

Full screen lists are in `screen_registry.md`. Summary:

- **Customer (C-01 … C-31):** onboarding, auth, home, medicine search with filters, medicine details with "ask nearby pharmacies", pharmacies that confirmed the medicine (nearest first), pharmacy details and contact, **live results and history of nearby requests**, single-pharmacy cart, order review/submit/result, order list/details/tracking/cancel, profile, notifications, help/report, legal.
- **Pharmacist (P-01 … P-74):** auth, pharmacy registration wizard with licence upload and shop location, pending/rejected/suspended states, dashboard, the medicine list (add, edit price / availability, Excel/CSV import with review, "confirm all"), **customers' requests inbox and answers**, POS with PDF receipt, sales history, reservation handling with reference verification, settings including the shop location.
- **Admin (A-01 …):** login, dashboard/metrics, pharmacy approvals, suspension/reinstatement, catalog + category management, medicine proposals, user reports, account status, audit log viewer, access-denied.

## 5. Explicitly deferred (documented, not silently omitted)

| Item | Prompt ref | Why / impact |
|---|---|---|
| Returns / refunds | E-53, "return/refund if included" | Not included in MVP. Sales are immutable; analytics count every completed sale. |
| Employee management UI | P-71, "if enabled" | Schema supports roles; inviting existing accounts safely needs an email-lookup RPC that would enable account enumeration. |
| Push notifications / `device_tokens` | table 15, C-26 | In-app notification centre only (D-13). |
| Supabase Realtime | — | Polling (D-14). |
| Account deletion / anonymisation | — | `orders.customer_id` is `ON DELETE RESTRICT`; deletion is a post-MVP process. |
| Pending-order expiry | — | D-08. |
| Push notifications for customers' questions | — | D-13: pharmacies see questions only while the app is open. |
| Medicine alternatives / substitutes in answers | — | The app never recommends substitutes (§1). |
| Phone-number login | concept image | D-01. |

## 6. Non-functional requirements

- **Security first** — see `security_model.md`. RLS on every exposed table; writes go through RPC; no client-trusted prices, totals, roles, or states.
- **RTL / Arabic** — Arabic default locale; English supported through GetX translation maps (`core/i18n`, one file per area and language); no hardcoded strings; bundled Arabic font (Cairo, SIL OFL) — font files must be added to `assets/fonts/` (see release checklist).
- **Accessibility** — 48 px touch targets, text scaling, state never conveyed by colour alone, contrast ≥ 4.5:1 for text.
- **Performance** — search is paginated (default 20, max 50), uses a trigram index over a normalised Arabic/Latin search column.
- **Resilience** — every network call has timeout, typed error, retry; sensitive writes carry idempotency keys.

## 7. Verification strategy and its limits

| Layer | Verified in the authoring sandbox? |
|---|---|
| SQL migrations, constraints, RLS, RPC, concurrency | **Yes** — run against a local PostgreSQL 16 with a Supabase-compatible stub (`supabase/tests/00_supabase_stub.sql`): 59 tests, 16 concurrency scenarios, 46 mutants all detected (`progress.md`) |
| Behaviour on real Supabase (GoTrue, PostgREST, Storage) | **No** — stub only emulates `auth.uid()`, roles and default grants. Re-run `supabase db reset && supabase test db` on a real project. |
| Dart/Flutter code | **No** — the Flutter SDK cannot be downloaded in the sandbox (network allowlist). `flutter pub get / analyze / test` have **not** been run; only three static tools (syntax, cross-references, translations/routes) were. Code is written conservatively but is unverified until those commands pass on a developer machine. |
| GPS permission flow, `.xlsx` parsing, Arabic CSV encodings on devices | **No** — need a real device (`release_checklist.md` §2 and §4). |

## 8. Open questions for the product owner

- ~~Q-01~~ **Resolved 2026-10-11:** login is by email + password.
- ~~Q-02~~ **Resolved 2026-10-11:** SYP by default, USD optional per pharmacy.
- **Q-03** Confirm week start day and the 24-hour order promise.
- **Q-07** Confirm the availability parameters: 7 days "recent", 30 days hidden, nearby radii 1/3/5/10 km, 3-minute wait before widening, 60-minute request life (all in `private.cfg_int`, changed by a migration).
- **Q-08** Is it acceptable to keep a customer's approximate location (rounded to ~100 m) for up to 30 days with the request (D-18)?
- **Q-04** Source of the verified medicine catalogue (the dev seed is sample data only).
- **Q-05** Licence/document requirements for pharmacy approval (current: one licence file, PDF/JPG/PNG ≤ 5 MB).
- **Q-06** Legal text (privacy policy, terms) must be supplied by counsel; the app ships placeholder structure only.
