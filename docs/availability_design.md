# Dawak — Availability model (replaces stock tracking)

Decision of 2026-10-26 (product owner): pharmacists cannot realistically upload and maintain ~3 500 products with quantities, so **quantities are gone**. Customers learn what is available from three layers, all free to run.

## 1. What changed in the data model

| Before | After |
|---|---|
| `pharmacy_products.stock_qty / reserved_qty / low_stock_threshold / last_inventory_update / is_active` | `is_available boolean`, `confirmed_at timestamptz` (when the pharmacist last confirmed *this* price/availability) |
| `inventory_movements`, `stock_reservations`, `movement_type`, `reservation_status` | removed |
| Reservation = stock held for 24 h | Reservation = the pharmacy's **promise** to prepare the order for 24 h (`orders.reservation_expires_at`); nothing is decremented anywhere |
| POS decrements stock and fails with `insufficient_stock` | POS only records the sale; it sells any product of that pharmacy (the shelf is the truth) |
| Dashboard low-stock / out-of-stock | listing summary (available / unavailable / not confirmed for 7 days) + open availability requests |
| `pharmacies` had no coordinates | `latitude`, `longitude` (required at registration, set once from the device GPS or a pasted map link) |

Removed error codes: `insufficient_stock`, `stock_below_reserved`. New codes: `request_closed`, `too_many_requests`.

## 2. The three layers

**Layer 1 — a list without quantities.** A pharmacy marks a medicine *available* with a *price*. Ways to fill the list: (a) import an Excel/CSV file from the pharmacy program (names are matched to the catalogue on the server with trigram *word similarity*, the pharmacist reviews uncertain rows), (b) add one by one from the catalogue, (c) **every "available" answer to a customer request is saved to the list automatically** (and every "unavailable" answer marks an existing row unavailable), so the list grows from real use.

**Layer 2 — search shows what is confirmed.** `get_medicine_pharmacies` returns pharmacies whose row is available and confirmed within the last 30 days, nearest first when the customer's location is known (otherwise recent-first, then cheapest). Each row carries `confirmed_at` and `freshness` (`recent` ≤ 7 days, `old` otherwise); the app shows "confirmed 3 days ago" and, for `old`, suggests asking.

**Layer 3 — ask the pharmacies nearby.** The customer taps "اسأل الصيدليات القريبة":

1. `create_availability_request(medicine, lat, lng)` — the server finds approved, listed pharmacies within **1 km**, creates one *target* row per pharmacy and notifies their active members. The customer's coordinates are rounded to 3 decimals (~100 m); pharmacies never see them, only the distance, and never see who asked.
2. A pharmacist opens the request (inbox in the pharmacist app) and taps **متوفر** (price pre-filled from the list) or **غير متوفر**. Answers can be changed while the request is open.
3. The customer's screen polls `get_availability_request`: it lists the pharmacies that said *available* with price, distance, address, phone and "open in maps / directions".
4. **Radius expansion** 1 → 3 → 5 → 10 km, evaluated by the server (`private.advance_request`), when nobody answered *available* and either (a) the current radius has no pharmacy, (b) every notified pharmacy answered *unavailable*, or (c) 3 minutes passed since the last step. The customer can also tap "ابحث أبعد". Expansion runs when the customer's screen polls and in the `pg_cron` sweeper, so it keeps going when the app is closed.
5. A request lives **60 minutes** (so quoted prices stay meaningful), then expires. Limits: 3 open requests and 10 requests per hour per customer; at most 25 notified pharmacies per request; a repeat request for the same medicine from nearly the same spot within 15 minutes returns the existing one (no duplicate notifications).

## 3. Privacy and abuse

* Customers never read `pharmacies`/`pharmacy_products`; the request tables have **no client grants** (RPC only).
* Pharmacists see: medicine, distance, time left, their own answer. No customer id, name or coordinates.
* Customers see only the pharmacies that answered *available*.
* Rate limits above; every RPC re-checks role, pharmacy approval and membership.

## 4. Notifications

In-app notifications (`availability_request` → pharmacy members, `availability_found` → the customer when the first pharmacy says available) and polling while the app is open. **Push (FCM) is a separate, optional module** (see `release_checklist.md`): without it a pharmacist whose app is closed sees the request only when he opens the app.

## 5. Known limits of this design

* A pharmacy's opening hours are not considered: a closed pharmacy simply answers later (the request lives 60 min).
* "Available" is the pharmacist's word at the time of answering; the product may sell out. The app shows the answer time and the customer can call before going.
* POS can sell only items that exist in the pharmacy's list (no free-text items).
* Price memory: a price typed in an answer replaces the listed price for that medicine.
