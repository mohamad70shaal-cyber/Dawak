# Dawak — Navigation Matrix

## 1. Guards

| Guard | Applies to | Rule | Redirect |
|---|---|---|---|
| `GuestOnlyGuard` | `/welcome`, `/login`, `/register`, `/password-reset`, `/verify-email`, `/pharmacist/login`, `/pharmacist/register`, `/admin/login` | session present | role home (`/customer/home`, pharmacist home by pharmacy state, `/admin/dashboard`) |
| `AuthGuard` | everything not `Pub`/`Guest` | no session | `/welcome` |
| `ActiveAccountGuard` | all authenticated routes | `profiles.account_status = suspended` | `/account-suspended` |
| `RoleGuard(role)` | `/customer/*` → customer, `/pharmacist/*` → pharmacist, `/admin/*` → admin | role mismatch | `/access-denied` |
| `PharmacyStateGuard` | pharmacist routes | no pharmacy → `/pharmacist/pharmacy/register`; `pending` → `/pharmacist/status/pending`; `rejected` → `/pharmacist/status/rejected`; `suspended` → `/pharmacist/status/suspended`; `approved` → allow operational routes | as listed |

Guards are navigation convenience. Every protected action is re-authorized in PostgreSQL (`security_model.md`).

**Session expiry:** `AuthService` listens to Supabase `onAuthStateChange`. On `signedOut` or failed refresh it clears controllers and calls `Get.offAllNamed('/welcome')` with an "session expired" message. A 401/`not_authenticated` from any RPC triggers the same path.

**Deep links:** guards run for every named route, so a deep link to an order or product page passes through `AuthGuard → ActiveAccountGuard → RoleGuard → PharmacyStateGuard`. After login the original target is resumed only if it is allowed for the role.

**Back behaviour:** tab roots exit the app (Android) after a confirm toast; pushed routes pop; checkout result replaces the stack (`offNamedUntil` to the shell) so back never re-submits an order.

## 2. Tabs

| Shell | Tab (index) | Root route | State preserved |
|---|---|---|---|
| Customer | Home (0), Search (1), My Orders (2), Profile (3) | `/customer/home`, `/customer/search`, `/customer/orders`, `/customer/profile` | `IndexedStack`; controllers are `permanent: false` but tab-scoped, search query and scroll kept |
| Pharmacist | Dashboard (0), POS (1), Orders (2), Medicine list (3), Settings (4) — cashiers have no Dashboard tab, so their indices shift (`PharmacistTabs.forSession`) | `/pharmacist/dashboard`, `/pharmacist/pos`, `/pharmacist/orders`, `/pharmacist/products`, `/pharmacist/settings` | `IndexedStack`; POS cart kept when switching tabs |

Opening a tab root route (e.g. from a notification) selects that tab in the existing shell instead of stacking a second shell.

## 3. Route table

(See `screen_registry.md` for controllers and data. Column *Back* = where the system back button goes.)

| Route | Guards | Params | Back | Refresh on return |
|---|---|---|---|---|
| `/splash` | — | — | exit | — |
| `/onboarding` | — | — | exit | — |
| `/welcome` | GuestOnly | — | exit | — |
| `/login`, `/register`, `/password-reset`, `/verify-email` | GuestOnly | — | `/welcome` | — |
| `/pharmacist/login`, `/pharmacist/register`, `/admin/login` | GuestOnly | — | `/welcome` | — |
| `/legal/privacy`, `/legal/terms` | — | — | previous | — |
| `/access-denied`, `/not-found`, `/account-suspended` | — | — | role home / sign out | — |
| `/customer/home` … `/customer/profile` | Auth, Active, Role(customer) | — | exit | orders tab refreshes after checkout/cancel |
| `/customer/search/results`, `/customer/search/filters` | same | `q`, filters | search | — |
| `/customer/medicine/:id`, `/customer/medicine/:id/pharmacies` | same | `id` | results | — |
| `/customer/pharmacy/:id`, `…/contact` | same | `id`, optional `medicineId` | previous | — |
| `/customer/cart`, `/customer/checkout/review`, `/customer/checkout/result` | same | — | previous (result: shell) | cart cleared on confirmed success |
| `/customer/orders/:id`, `…/tracking`, `…/cancel` | same | `id` | orders | list + detail refetched after cancel |
| `/customer/requests`, `/customer/requests/:id` (ask-nearby history and results) | same | `id` | profile / medicine | list refetched after expand/close; results poll every 5 s while the request is open |
| `/customer/profile/edit`, `/customer/notifications`, `/customer/help` | same | — | profile / home | profile refetched after save |
| `/pharmacist/pharmacy/register` (+ `/info`, `/address`, `/hours`) | Auth, Active, Role(pharmacist) | — | previous step | — |
| `/pharmacist/status/pending`, `/rejected`, `/suspended` | Auth, Active, Role(pharmacist) | — | logout confirm | pending polls every 30 s |
| `/pharmacist/dashboard`, `/pos`, `/orders`, `/products`, `/settings` | Auth, Active, Role(pharmacist), PharmacyState(approved) | — | exit | dashboard refetched after POS sale / order completion |
| `/pharmacist/products/add`, `/propose`, `/import`, `/:id`, `/:id/edit` (static paths are declared before `/:id`) | same | `id` | products | products list refetched after save / import / "confirm all" |
| `/pharmacist/requests`, `/pharmacist/requests/:id` (customers' availability questions) | same | `id` | previous | inbox polls while open; refetched after an answer |
| `/pharmacist/pos/checkout`, `/pharmacist/pos/completed/:saleId` | same | `saleId` | pos (completed: new-sale resets) | dashboard + products refetched |
| `/pharmacist/sales`, `/pharmacist/sales/:id` | same | `id` | sales | — |
| `/pharmacist/orders/find`, `/pharmacist/orders/:id`, `…/handover` | same | `id` | orders | orders list + dashboard refetched after state change |
| `/pharmacist/settings/profile`, `/contact`, `/hours`, `/location`, `/security` | same | — | settings | pharmacy refetched after save |
| `/pharmacist/notifications` | same | — | previous | badge refreshed |
| `/admin/dashboard` | Auth, Active, Role(admin) | — | exit | — |
| `/admin/pharmacies`, `/admin/pharmacies/pending`, `/admin/pharmacies/:id` | same | `id` | previous | list + dashboard refetched after decision |
| `/admin/medicines`, `/admin/medicines/new`, `/admin/medicines/:id`, `/admin/categories` | same | `id` | previous | list refetched after save |
| `/admin/reports`, `/admin/reports/:id`, `/admin/users`, `/admin/audit-logs` | same | `id` | previous | list refetched after action |

## 4. End-to-end workflows (each has an automated test)

**F1 — Customer reservation:** Home → Search → Results → Medicine details → Pharmacy results → Pharmacy details → Cart → Review → (server `create_order`) → Result → Order details → My orders. Asserts: cart cleared only after success; duplicate tap sends the same idempotency key; different-pharmacy add prompts "replace cart?" instead of mixing.

**F2 — Pharmacist list and sale:** Login → Dashboard → Medicine list → Add one medicine (price) → Edit price / mark unavailable → Import an Excel/CSV list (names matched to the catalogue on the server, review, confirm) → "Confirm all" → POS (add, change qty, discount as owner) → Checkout → (server `create_pos_sale`) → Receipt → Sales history. Asserts: receipt shown only after confirmed success; the list and the dashboard are refreshed; a product that is no longer in the pharmacy's list is dropped from the basket with an explanation; there are no quantities anywhere.

**F3 — Order lifecycle (promise, not stock):** Customer creates order → pharmacist Orders (new) → Accept (the pharmacy promises to keep it for 24 hours) → Ready → Find by reference → Handover with reference confirmation → Complete (sale created) → customer sees `completed`. Variants: reject with reason; cancel an accepted order; expiry after 24 h then reactivate (a new 24 h promise); completion after expiry blocked.

**F4 — Admin approval:** Pharmacist registers + uploads licence → pending screen → Admin Pending list → Application details → Approve → pharmacist app unlocks (poll) → pharmacy appears in public search; Reject variant shows reason and resubmission path; Suspend removes from public search.

**F5 — Auth and separation:** unauthenticated access to every protected route redirects; customer cannot open `/pharmacist/*` or `/admin/*`; pharmacist cannot open `/admin/*`; suspended and rejected accounts land on their status screens; expired session redirects to welcome.

**F6 — Failure and retry:** offline/timeouts show retry; retry reuses idempotency key; no success message before server confirmation; raw SQL errors never displayed.

**F7 — Ask the pharmacies nearby (customer + pharmacist):** Medicine details → "Ask nearby" (first time: explanation sheet; asks for the location, or the customer's position can be refreshed) → request created (pharmacies within 1 km notified) → results screen polls every 5 s → pharmacist inbox shows the question (never who asked or where from) → answer *available (price)* / *unavailable* → customer sees the pharmacy with price, distance, directions link and "reserve" (when the pharmacy's list has the product) → server widens 1 → 3 → 5 → 10 km (empty circle, everybody said no, 3 minutes of silence) or the customer taps "search further" → close, or the request expires after 60 minutes. Asserts: the radius shown only grows; a refused expand re-reads the screen; polling stops when closed/expired; a failed poll sets "offline" and keeps the last answer on screen; closing asks for confirmation.

## 5. Required automated tests (navigation)

1. Route audit (registry ↔ `AppPages` ↔ `AppRoutes`).
2. Every named route resolves to a page without throwing (with fake repositories).
3. Every bottom-navigation item selects the right tab and preserves state.
4. Back navigation per table above.
5. Unauthenticated, wrong-role, suspended, rejected, pending, expired-session guards.
6. Button wiring audit: every `onPressed`/`onTap` in screen files is non-null (lint-style test scanning `lib/features/**/views`).
7. Form validation and submission failures per form.
8. Retry after network error per list screen.
9. Completed actions refresh related screens (controllers' `refreshRelated` hooks).
10. Workflows F1–F7 with in-memory fake repositories; server logic is covered separately by the SQL tests.
