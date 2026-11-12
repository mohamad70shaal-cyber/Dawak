# Dawak — Database Schema

Authoritative definition lives in `supabase/migrations/*.sql`. This document is the contract those migrations implement.

Conventions: UUID primary keys (`gen_random_uuid()`), `timestamptz` UTC, money `numeric(14,2)`, order quantities `integer` (the database holds **no stock quantities**, see `availability_design.md`), status columns are PostgreSQL enums (snake_case values), every table has RLS enabled.

Schemas: `public` (exposed tables + RPC), `private` (helpers, never exposed to PostgREST), `extensions` (pg_trgm, pgcrypto).

## 1. Enums

| Enum | Values |
|---|---|
| `user_role` | `customer`, `pharmacist`, `admin` |
| `account_status` | `active`, `suspended` |
| `approval_status` | `pending`, `approved`, `rejected`, `suspended` |
| `member_role` | `owner`, `manager`, `cashier` |
| `member_status` | `active`, `suspended`, `removed` |
| `catalog_status` | `pending`, `approved`, `rejected`, `archived` |
| `order_status` | `pending`, `accepted`, `ready_for_pickup`, `completed`, `rejected`, `cancelled`, `expired` |
| `request_status` | `open`, `closed`, `expired` |
| `request_answer` | `available`, `unavailable` |
| `report_status` | `open`, `in_review`, `resolved`, `dismissed` |
| `report_target` | `pharmacy`, `medicine`, `order`, `app`, `other` |
| `payment_method` | `cash` |

## 2. Tables

| Table | Purpose | Key columns / constraints |
|---|---|---|
| `profiles` | One row per auth user (created by trigger, role forced to `customer`) | `id → auth.users` (cascade), `display_name`, `phone`, `role`, `account_status`, `suspended_reason`, `locale` |
| `pharmacies` | Pharmacy + application state | `owner_id → profiles` (unique: one per owner), `name`, `phone`, `show_phone_publicly`, `address_line`, `neighborhood`, `city`, `directions`, `opening_hours jsonb`, `currency` (`SYP`/`USD`), `timezone`, `latitude`/`longitude` (the shop's position, both or neither, range-checked; set from the device GPS or a pasted map link), `approval_status`, `status_reason` (why it was rejected or suspended; shown to the owner), `reviewed_by/at`, `is_listed`, `license_document_path`; CHECK `is_listed ⇒ approval_status='approved'` |
| `pharmacy_members` | Who may act for a pharmacy | PK `(pharmacy_id,user_id)`, `role`, `status` |
| `medicine_categories` | Catalog categories | `name_ar`, `name_en`, `sort_order`, `is_active` |
| `medicines` | Shared catalog (one row per distinct product) | `name_ar`, `name_en`, `brand_name`, `active_ingredient`, `strength`, `dosage_form`, `package_description`, `category_id`, `catalog_status`, `proposed_by`, `reviewed_by`; generated `search_text` (normalised) and `dedupe_key` (unique) |
| `pharmacy_products` | What a pharmacy **says** it has — one row per catalog medicine, **no quantities** | UNIQUE `(pharmacy_id, medicine_id)`, `price > 0`, `is_available`, `confirmed_at` (last time a pharmacist confirmed *this* price/availability: an edit, a request answer, an import or "confirm all"), `created_at`, `updated_at` |
| `orders` | Customer reservation | `public_ref` (unique, random, non-sequential `DWK-XXXXXXXXXX`), `customer_id`, `pharmacy_id`, `status`, `currency`, `subtotal`, `pharmacy_name` / `pharmacy_address` / `pharmacy_phone` (snapshot of the pharmacy at order time, because customers cannot read `pharmacies` and the order must stay understandable if the pharmacy is renamed or suspended), `customer_name` (snapshot), `contact_phone`, `customer_notes`, `reject_reason`, `cancel_reason`, `cancelled_by_role` (`customer` \| `pharmacy`), one timestamp per state (`accepted_at`, `ready_at`, `completed_at`, `rejected_at`, `cancelled_at`, `expired_at`), `reservation_expires_at` (end of the pharmacy's 24-hour **promise** to keep the order) |
| `order_items` | Snapshot lines | `quantity > 0`, `unit_price`, generated `line_total`, name/strength/form snapshots |
| `availability_requests` | A customer's "ask the pharmacies nearby" question | `customer_id`, `medicine_id`, `latitude`/`longitude` (customer's position **rounded to 3 decimals**, never shown to pharmacies), `step` 1..4 (radius 1 / 3 / 5 / 10 km), `status`, `created_at`, `expires_at` (60 min), `last_expanded_at`, `closed_at` — **no client grants, RPC only** |
| `availability_targets` | One row per (request, notified pharmacy); the pharmacy's answer lives on the same row | PK `(request_id, pharmacy_id)`, `step`, `distance_km`, `notified_at`, `answer`, `price`, `answered_by`, `answered_at`; CHECK: no answer ⇒ no price/time, `available` ⇒ price + time, `unavailable` ⇒ time and **no** price — **no client grants, RPC only** |
| `sales` | Immutable invoices | `invoice_no` unique per pharmacy, `order_id` unique when present, `payment_method='cash'`, `currency`, `subtotal`, `discount_amount`, `total`; CHECK `total = subtotal − discount_amount`, `discount_amount ≤ subtotal` |
| `sale_items` | Immutable invoice lines | snapshots, `quantity > 0`, `line_total = quantity × unit_price` |
| `audit_logs` | Append-only audit trail | `actor_id`, `action`, `entity_type`, `entity_id`, `pharmacy_id`, `details jsonb` |
| `user_reports` | Issue reports | `reporter_id`, `target_type`, `target_id`, `category`, `description`, `status`, `resolution_note` |
| `notifications` | In-app notifications | `user_id`, `kind`, `params jsonb`, `entity_type`, `entity_id`, `read_at` |
| `idempotency_keys` | Retry safety | PK `(user_id, scope, key)`, `response jsonb` — no client access |
| `pharmacy_invoice_counters` | Per-pharmacy invoice sequence | `pharmacy_id`, `last_number` — no client access |

`device_tokens` is **not created** (push deferred, D-13).

## 3. Relationships and deletion behaviour

- `profiles.id → auth.users(id)` ON DELETE CASCADE.
- `pharmacies.owner_id → profiles` RESTRICT; `pharmacy_members → pharmacies` CASCADE / `→ profiles` CASCADE.
- `pharmacy_products → pharmacies` RESTRICT, `→ medicines` RESTRICT. Products are **never hard-deleted**; `is_available=false` takes them off the customer lists.
- `orders → profiles` RESTRICT, `→ pharmacies` RESTRICT. `order_items → orders` CASCADE, `→ pharmacy_products` RESTRICT.
- `sales → pharmacies` RESTRICT, `→ orders` RESTRICT. `sale_items → sales` RESTRICT (history is immutable), `→ pharmacy_products` RESTRICT.
- `availability_requests → profiles` CASCADE, `→ medicines` RESTRICT; `availability_targets → availability_requests` CASCADE, `→ pharmacies` CASCADE.
- `sales`, `sale_items`, `audit_logs`: UPDATE/DELETE/TRUNCATE blocked by trigger and by missing grants.

## 4. Search design

`private.normalize_search(text)` (IMMUTABLE): lowercases, strips tashkeel and tatweel, folds `أإآٱ→ا`, `ى→ي`, `ة→ه`, `ؤ→و`, `ئ→ي`, maps Arabic-Indic and Persian digits to ASCII, collapses whitespace. `medicines.search_text` is a stored generated column over name_ar, name_en, brand_name, active_ingredient, strength, dosage_form. A GIN `gin_trgm_ops` index serves `LIKE '%token%'`. The original display columns are never modified. Search requires every query token to match (AND), ranks prefix matches first, then trigram similarity.

## 5. Availability model (no stock)

Nothing in the database counts units. Customers learn what is available from three layers (full design: `availability_design.md`):

1. **The pharmacy's list** — `pharmacy_products(is_available, price, confirmed_at)`.
2. **Search / pharmacy pages** — only rows that are available **and** confirmed within `listing_max_age_days` (30) are shown; `private.listing_freshness(confirmed_at)` returns `recent` (≤ `fresh_days` = 7) or `old`. `get_medicine_pharmacies` sorts nearest first when given the customer's position (haversine, `private.distance_km`), otherwise recent first then cheapest.
3. **Ask nearby** — `availability_requests` / `availability_targets` and the RPCs below.

Server-side configuration lives in `private.cfg_int` (change via a new migration): `reservation_hours` 24, `fresh_days` 7, `listing_max_age_days` 30, `max_pending_orders` 5, `max_orders_per_hour` 10, `max_customer_qty_per_item` 10, `max_order_lines` 20, `max_pos_qty_per_item` 999, `max_pos_lines` 100, `request_ttl_minutes` 60, `request_wait_minutes` 3, `request_max_step` 4, `max_open_requests` 3, `max_requests_per_hour` 10, `max_request_targets` 25, `request_dedupe_minutes` 15, `max_import_items` 500, `max_match_names` 100.

### Availability request life cycle

```
create (step 1 = 1 km, notifies up to 25 nearest approved+listed pharmacies)
  ├─ a pharmacy answers available(price) / unavailable  — can be changed while open; owner/manager answers also update the list
  ├─ widen to the next step (3 → 5 → 10 km) when nobody said "available" and
  │     (a) the radius has no pharmacy (empty radii are skipped), or (b) everybody asked said "unavailable",
  │     or (c) 3 minutes passed since the last step — or when the customer taps "search further"
  ├─ close (customer)  → closed
  └─ 60 minutes pass   → expired
```

`private.advance_request` applies the widening and expiry rules; it runs on every read of a request and from the sweeper `private.advance_all_availability_requests()` (schedule with `pg_cron` every minute; it also deletes requests older than 30 days).

## 6. Order state machine

```
pending ──accept──▶ accepted ──ready──▶ ready_for_pickup ──complete──▶ completed
   │                   │                     │
   ├─reject──▶ rejected│                     │
   ├─cancel──▶ cancelled◀──cancel────────────┘ (customer: pending/accepted/ready/expired;
   │                   │                            pharmacy: accepted/ready, with a reason)
   │                   └──expire──▶ expired ◀──expire── ready_for_pickup
   │                                  │
   │                                  ├──reactivate (pharmacy, new 24 h promise)──▶ accepted
   │                                  └──cancel (customer)──▶ cancelled
```

Accepting an order is the pharmacy's **promise** to prepare it for 24 hours (`reservation_expires_at`); nothing is decremented or reserved anywhere, so several customers may hold orders for the same medicine and the pharmacy answers for what is on its shelf.

Allowed pairs live in `private.order_transition_allowed(from,to)` and are enforced by a BEFORE UPDATE trigger on `orders` in addition to the RPC checks. Terminal states: `completed`, `rejected`, `cancelled`.

## 7. Trusted operations (RPC, `SECURITY DEFINER`, `search_path=''`)

All are `EXECUTE`-granted to `authenticated` only (revoked from `public`/`anon`). The built-in PUBLIC execute default is revoked for the migration role (`alter default privileges revoke execute on functions from public`), and helpers in `private` are never granted except the three used by RLS policies (`is_admin`, `is_member`, `normalize_search`). Each re-derives the caller from `auth.uid()` and checks role, account status, pharmacy membership and pharmacy approval.

| Group | Functions |
|---|---|
| Pharmacy onboarding | `register_pharmacy`, `resubmit_pharmacy`, `update_my_pharmacy` |
| Admin | `admin_review_pharmacy` (approve/reject/suspend/reinstate), `admin_set_account_status`, `admin_review_medicine`, `admin_resolve_report`, `admin_metrics` |
| Catalog | `propose_medicine` (dedupe, returns existing id) |
| Pharmacy list | `add_pharmacy_product`, `update_pharmacy_product` (any call confirms the row), `confirm_listing` (refreshes `confirmed_at` of every available product), `bulk_upsert_pharmacy_products` (≤ 500 rows, idempotent), `match_medicine_names` (≤ 100 names → up to 3 trigram *word similarity* suggestions each, threshold 0.4; owner/manager only) |
| POS | `create_pos_sale` (idempotent; "the shelf is the truth": any product of the pharmacy can be sold, only a product of another pharmacy is refused, as `product_unavailable`; the server always prices from the list and ignores `expected_unit_price`, see `progress.md` known issue 5), `get_sale` |
| Orders | `create_order` (idempotent, rate-limited), `cancel_order`, `accept_order`, `reject_order`, `mark_order_ready`, `pharmacy_cancel_order`, `complete_order`, `reactivate_order`, `find_order_by_ref`, `expire_reservations(pharmacy_id)` (members sweep their own pharmacy when the orders screen opens) |
| Ask nearby (customer) | `create_availability_request` (idempotent, rate-limited, a repeat of the same medicine within 500 m and 15 minutes returns the open request instead of creating another), `get_availability_request`, `list_my_availability_requests`, `expand_availability_request`, `close_availability_request` |
| Ask nearby (pharmacy) | `count_pharmacy_availability_requests`, `list_pharmacy_availability_requests` (never shows who asked or from where), `answer_availability_request` |
| Public read | `search_medicines`, `get_medicine_pharmacies` (optional position and radius), `list_public_pharmacies`, `get_public_pharmacy`, `get_public_pharmacy_products` |
| Analytics | `pharmacy_dashboard` |

### Error convention

Business failures raise `P0001` with `MESSAGE = <machine_code>` and `DETAIL = json context`. The app maps codes to Arabic/English strings and never displays raw database text. Codes: `not_authenticated`, `account_suspended`, `forbidden`, `pharmacy_not_active`, `invalid_input`, `price_changed`, `product_unavailable`, `invalid_transition`, `reservation_expired`, `reference_mismatch`, `rate_limited` (hourly caps), `too_many_pending` (5 pending orders), `too_many_requests` (3 open nearby requests), `request_closed`, `duplicate_request` (an idempotency key reused with a different payload), `not_found`, `internal_error`, `append_only`. Authorization failures that would reveal whether a record exists (another pharmacy's receipt or order, someone else's order) return `not_found`, not `forbidden`. Calls by `anon` fail earlier with SQLSTATE `42501` (no EXECUTE privilege).

### Concurrency rules

- No product rows are locked any more (there is no counter to protect). Order state changes lock the **order row** (`FOR UPDATE`); POS sales lock nothing except the pharmacy's invoice counter row (`INSERT … ON CONFLICT DO UPDATE`).
- Every state change re-reads status after taking the lock.
- `create_order` first locks the customer's profile row (`FOR NO KEY UPDATE`) so the pending/hourly caps cannot be beaten by parallel requests (found by the concurrency suite); `create_availability_request` does the same for the open-request and hourly caps.
- Request state changes (`answer`, `expand`, `close`, the sweeper) lock the request row first; the sweeper and the batch expiry use `FOR UPDATE SKIP LOCKED`, so a row another transaction is working on is left for the next sweep.
- Completion is idempotent: the unique constraint on `sales.order_id` plus the `completed` status make a repeat call return the existing sale.

## 8. Indexes (summary)

Trigram on `medicines.search_text`; `pharmacy_products(pharmacy_id, is_available)`, `(medicine_id, confirmed_at desc) WHERE is_available`; `pharmacies(latitude, longitude) WHERE approved AND listed AND latitude IS NOT NULL`; `orders(customer_id, created_at desc)`, `(pharmacy_id, status, created_at desc)`, `(status, reservation_expires_at)`; `sales(pharmacy_id, created_at desc)`; `sale_items(sale_id)`, `(product_id)`; `availability_requests(customer_id, created_at desc)`, `(expires_at) WHERE status='open'`; `availability_targets(pharmacy_id, notified_at desc)`; `notifications(user_id, created_at desc)`; FK columns not covered above.

## 9. Retention

Sales, sale items and audit logs are kept indefinitely (legal/accounting). Availability requests are deleted after 30 days by the sweeper. Idempotency keys older than 7 days may be purged by a scheduled job (documented in the release checklist).

## 10. Scheduled jobs (`pg_cron`, documented but **not created** by the migrations)

| Job | Function | Every |
|---|---|---|
| Expire the 24-hour promises | `private.expire_all_reservations()` | 5 minutes |
| Widen / expire availability requests, delete old ones | `private.advance_all_availability_requests()` | 1 minute |
| Purge old idempotency keys | `delete from public.idempotency_keys where created_at < now() - interval '7 days'` | daily |

Between sweeps nothing wrong can happen: `complete_order`/`mark_order_ready` check `reservation_expires_at` themselves, acceptance, POS sales and the orders screen sweep their own pharmacy first, and every read of an availability request applies the widening and expiry rules itself (the sweeper only keeps requests moving when the customer's app is closed).
