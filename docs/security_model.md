# Dawak — Security Model

Principle: **the client is untrusted.** The Flutter app holds only the Supabase URL and anon key. Authorization is enforced by PostgreSQL (RLS, column privileges, trusted functions). Route guards and hidden menus are convenience only.

## 1. Identities and roles

| Concept | Source of truth |
|---|---|
| Who is calling | `auth.uid()` from the verified JWT |
| Role | `profiles.role` (`customer` default) — changed only by trusted functions or by an operator with database access |
| Account state | `profiles.account_status` — `suspended` accounts are rejected by every RPC and every policy helper |
| Pharmacy authority | `pharmacy_members` row, `status='active'`, **and** `pharmacies.approval_status='approved'` for operational RPCs |
| Admin | `profiles.role='admin'` and `account_status='active'` |

Sign-up always creates a `customer` profile (trigger ignores any client-supplied role). `register_pharmacy` promotes `customer → pharmacist` and creates a **pending**, **unlisted** pharmacy; it cannot create an admin and cannot approve anything. A pharmacist with no approved pharmacy can do nothing operational.

### Pharmacy member permissions

| Capability | owner | manager | cashier |
|---|---|---|---|
| View the pharmacy's list (price, available, confirmed when) | ✔ | ✔ | ✔ |
| Add / edit price / mark available or unavailable / import a file / "confirm all" / list-unlist | ✔ | ✔ | ✖ |
| See customers' nearby questions and answer them | ✔ | ✔ | ✔ (the answer does **not** change the list) |
| An answer also updates the pharmacy's list | ✔ | ✔ | ✖ |
| POS sale | ✔ | ✔ | ✔ |
| POS discount | ✔ | ✔ | ✖ |
| Accept / reject / ready / complete / cancel orders | ✔ | ✔ | ✔ |
| View all sales and the dashboard | ✔ | ✔ | own sales only |
| Edit pharmacy profile and shop location | ✔ | ✖ | ✖ |

## 2. Defence layers

1. **Grants:** `REVOKE ALL` on every table from `anon`/`authenticated`, then grant the minimum (SELECT where a policy exists, specific UPDATE columns, specific INSERT columns). Supabase's default grants are therefore overridden.
2. **RLS:** enabled on every table. Tables without client writes have no INSERT/UPDATE/DELETE policy (default deny).
3. **Trusted functions:** every mutation with business meaning is a `SECURITY DEFINER` function with `search_path=''`, schema-qualified references, caller re-derivation, input validation, and `EXECUTE` revoked from `public`/`anon`. PostgreSQL grants EXECUTE to PUBLIC on every new function by default and `ALTER DEFAULT PRIVILEGES IN SCHEMA` cannot remove that; the migrations therefore revoke it globally for the migration role and sweep `private` again in the last migration. (The first version of the migrations got this wrong; the security test `t_sec_01` caught it.)
4. **Triggers (defence in depth):** role/status columns on `profiles` cannot be changed by `anon`/`authenticated`; order transitions validated; append-only tables reject UPDATE/DELETE; `pharmacies` approval fields cannot be changed by client roles.
5. **Constraints:** positive prices and quantities, `total = subtotal − discount`, unique invoice/ref/order-sale pairs, a pharmacy location is both coordinates or neither, an availability answer has the right shape (`available` ⇒ price, `unavailable` ⇒ no price).

## 3. Access matrix (client roles)

| Table | customer | pharmacy member | admin |
|---|---|---|---|
| `profiles` | own row; update `display_name`, `phone`, `locale` only | own row | non-customer rows (read) |
| `pharmacies` | **none directly** (use public RPC; masked) | own pharmacy (read) | all (read) |
| `pharmacy_members` | none | own memberships (read) | all (read) |
| `medicine_categories` | active (read) | active (read) | all (read/write) |
| `medicines` | approved (read) | approved + own proposals (read) | all (read/write) |
| `pharmacy_products` | **none directly** (public RPCs return only available, recently confirmed rows with price) | own pharmacy (read) | none |
| `orders`, `order_items` | own (read) | that pharmacy's (read) | **none** |
| `availability_requests`, `availability_targets` | **none** (RPC only: `create/get/list/expand/close_availability_request`) | **none** (RPC only: inbox shows the medicine and the distance, never who asked or from where; `answer_availability_request`) | none |
| `sales`, `sale_items` | none | owner/manager: all; cashier: own (read) | none |
| `audit_logs` | none | none | read |
| `user_reports` | insert + read own | insert + read own | read all |
| `notifications` | own (read; update `read_at`) | own | own |
| `idempotency_keys`, `pharmacy_invoice_counters` | none | none | none |

Privacy: customers never see `owner_id`, licence path or any quantity (none exists). A customer's position is rounded to ~100 m by the RPC, stored only with the request, never returned to pharmacies, and deleted with the request after 30 days; a pharmacy's own location is public by design. Pharmacies see the customer's display-name **snapshot** and the optional contact phone **the customer typed for that order**, never the profile. Admins never see customers' orders or profiles (D-15).

## 4. Threats and mitigations

| Threat | Mitigation |
|---|---|
| Client sets `role='admin'` at sign-up | Trigger forces `customer`; no UPDATE grant on `role`; guard trigger |
| Pharmacist approves own pharmacy | No UPDATE grant on approval columns; `admin_review_pharmacy` requires admin |
| Pharmacy A reads Pharmacy B's list | Policies join through active membership; tested |
| Tampered price/total from client | Server reads price from `pharmacy_products`; totals computed in SQL; in `create_order` an `expected_unit_price` that differs is refused as `price_changed`; `create_pos_sale` ignores it and always prices from the list |
| Selling something the pharmacy does not have | Not a database matter any more: no stock is stored (D-06). The pharmacy accepts or rejects each order; unavailable or foreign products are refused at creation (`product_unavailable`) |
| Double-submit order / double-charge sale | `idempotency_keys`; unique `sales(order_id)`; completed-state shortcut |
| Expiry racing with acceptance/cancel | Expiry uses `FOR UPDATE SKIP LOCKED`; every state change re-reads the status under the order's row lock; concurrency scenario s10 |
| Completing an order after the 24-hour promise ended | `complete_order` rejects after `reservation_expires_at`; `reactivate_order` (pharmacy action) starts a new promise |
| Customer touches another's order | RPC checks `customer_id = auth.uid()` under lock; RLS read-only |
| Order spam / abuse | Max 5 pending orders, max 10 orders per hour per customer (`rate_limited`); creation is serialised per customer by a row lock so parallel requests cannot exceed the caps (found and fixed via concurrency test s9) |
| Spam / harassment through "ask nearby" | Customers only; at most 3 open requests (`too_many_requests`) and 10 per hour (`rate_limited`) per customer, both serialised by a per-customer row lock (concurrency s12); a repeat of the same medicine within 500 m and 15 minutes reuses the open request instead of notifying again (s11); at most 25 pharmacies notified per request; requests expire after 60 minutes |
| Idempotency key replayed with a different payload | `duplicate_request` (the stored response is only replayed for an identical payload) |
| A pharmacy answers a question it was not asked, or after it closed | `answer_availability_request` requires an `availability_targets` row for that pharmacy and an open request (`not_found` / `request_closed`); mutation-tested |
| Locating a customer from the inbox | Inbox exposes the medicine and the distance only (no customer id, no coordinates); coordinates are stored rounded to 3 decimals |
| Existence oracle (guessing receipt/order ids) | Not-a-member / not-the-owner returns `not_found`, identical to a missing record |
| Enumeration of order refs | Refs are random (40 bits) and `find_order_by_ref` is scoped to the caller's pharmacy |
| SQL injection | RPC parameters only; no dynamic SQL; LIKE tokens escaped |
| Leaking DB errors | App maps machine codes; unknown errors become a generic message; logs redact tokens |
| Suspended user keeps working | `private.assert_active_user()` on every RPC; session restore re-checks status |
| Service-role key in app | Not used anywhere; `.env.example` has URL and anon key only; CI check greps for `service_role` |
| Malicious licence upload | Storage bucket private, 5 MB limit, MIME allowlist (PDF/JPEG/PNG), path must start with the uploader's user id; admin read policy |
| History tampering | Append-only triggers; no DELETE/UPDATE grants |

## 5. Storage

Bucket `pharmacy-documents` (private). Object path: `<user_id>/<filename>`. Policies: owner may INSERT/SELECT in own folder; admin may SELECT all; nobody may UPDATE/DELETE from the client (resubmission uploads a new file). Size and MIME restrictions are set on the bucket; the client also pre-validates.

## 6. Operator procedures

- **First admin:** sign up in the app, then run `supabase/dev/bootstrap_first_admin.sql` (with your e-mail) in the SQL editor as `postgres`. Only database operators can do this; clients cannot.
- **Revoking an admin:** set `role='customer'`; sessions expire at JWT expiry (recommend 1 h).
- **Account recovery:** standard Supabase password reset email; admins can suspend via `admin_set_account_status`.
- **Secrets:** service-role key lives only in the Supabase dashboard / CI secret store, never in the repo, app, or assets.
- **Scheduled jobs (pg_cron, run as `postgres`, SQL in `release_checklist.md` §1):** `private.expire_all_reservations()` every 5 minutes; `private.advance_all_availability_requests()` every minute; `delete from public.idempotency_keys where created_at < now() - interval '7 days'` daily.

## 7. Security tests (SQL, run on every change)

`supabase/tests/run.sh` (**59 tests**, last run 2026-10-30: 59 passed, 0 failed): `t_sec_*` security, `t_lst_*` pharmacy list / import / matching, `t_pos_*` POS, `t_ord_*` order lifecycle, `t_pub_*`/`t_dash_*`/`t_perf_*` public reads, analytics and search performance, `t_req_*` availability requests (and a few single tests in the security file). Highlights: RLS enabled and anon/authenticated grants minimal; sign-up cannot create an admin; profile role/status cannot be escalated; a new pharmacy is pending, unlisted and unprivileged; pharmacist cannot approve own pharmacy; Pharmacy A cannot read or touch B's data; customers cannot see others' orders or requests; admins cannot read orders, sales or requests; anonymous callers are denied everywhere; sales and audit logs are append-only (including TRUNCATE); invalid order transitions fail in RPCs **and** in the trigger; totals are computed server-side; negative or fractional quantities fail; search hides suspended, unlisted, unavailable and stale (> 30 days) listings and sorts nearest first; request radii, widening rules, caps and rounding of coordinates; storage policies confine licence files to their owner and admins.

`supabase/tests/concurrency/run_concurrency.py` (**16 scenarios** of real parallel sessions, run 3 iterations each on 2026-10-30, all passed): s1–s10 orders and sales — parallel acceptances never contend, repeated acceptance, repeated handover, cancel vs handover, 15 parallel walk-in sales, opposite line order (deadlock check), the same idempotency key in parallel, parallel order creation vs the pending cap, expiry sweep vs cancel/accept; s11–s16 ask nearby — the same request key in parallel, different requests vs the open cap, two pharmacies answering together while the customer polls and widens, answer vs close, parallel manual widening (exactly one step each, the fourth refused), the sweeper racing with polling and answers. After every iteration the invariants are checked: at most one sale per order, unique gap-free invoice numbers, sale totals equal their items, no request over the target cap, no target outside the radius of its step.

`supabase/tests/mutation/mutation_check.py` deliberately breaks **46** rules in a copy of the migrations (e.g. `complete_order` without the reference check, RLS `using (true)` on orders, search ignoring the 30-day cut-off or the distance order, targets ignoring the radius, no widening after three minutes of silence, coordinates stored unrounded, any customer reading another's request, a pharmacy that was not asked answering, private helpers executable by everyone) and requires at least one test to fail for each. Last run 2026-10-30: baseline green, 46 run, 46 killed, 0 survivors.

## 8. Known limitations

- Stub-based tests do not exercise GoTrue, PostgREST or Storage. Re-run on a real Supabase project before release.
- No CAPTCHA / email-rate limiting beyond Supabase Auth defaults — configure in the dashboard.
- Licence document review is manual.
- Availability is declared by pharmacies and cannot be verified by the platform; a dishonest or careless pharmacy can say "available" for something it does not have. Freshness labels, the 30-day cut-off, customer reports (admin review) and suspension are the mitigations.
- Distances reach pharmacies (a ring around the pharmacy, not a position) and, with the shop location, customers; the position of the customer is never returned.
- No device attestation / jailbreak detection.
