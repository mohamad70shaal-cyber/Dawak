-- Dawak tables. RLS and grants are applied in a later migration.

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 80),
  phone text check (phone is null or phone ~ '^\+?[0-9]{7,15}$'),
  role public.user_role not null default 'customer',
  account_status public.account_status not null default 'active',
  suspended_reason text check (suspended_reason is null or char_length(suspended_reason) <= 300),
  locale text not null default 'ar' check (locale in ('ar', 'en')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pharmacies (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete restrict,
  name text not null check (char_length(btrim(name)) between 2 and 120),
  phone text not null check (phone ~ '^\+?[0-9]{7,15}$'),
  show_phone_publicly boolean not null default true,
  address_line text not null check (char_length(btrim(address_line)) between 3 and 250),
  neighborhood text not null default '' check (char_length(neighborhood) <= 100),
  city text not null check (char_length(btrim(city)) between 2 and 100),
  directions text check (directions is null or char_length(directions) <= 500),
  -- Where the shop is (device GPS at the shop, or a pasted map link). Needed for "nearest first" and for
  -- availability requests; the pharmacy's location is public information (customers see it on the map link).
  latitude double precision check (latitude is null or latitude between -90 and 90),
  longitude double precision check (longitude is null or longitude between -180 and 180),
  opening_hours jsonb not null default '{}'::jsonb check (jsonb_typeof(opening_hours) = 'object'),
  currency text not null default 'SYP' check (currency in ('SYP', 'USD')),
  timezone text not null default 'Asia/Damascus' check (timezone in ('Asia/Damascus')),
  approval_status public.approval_status not null default 'pending',
  status_reason text check (status_reason is null or char_length(status_reason) <= 500),
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  submitted_at timestamptz not null default now(),
  is_listed boolean not null default false,
  license_document_path text check (license_document_path is null or char_length(license_document_path) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pharmacies_location_pair check ((latitude is null) = (longitude is null)),
  constraint pharmacies_listed_requires_approval check (not is_listed or approval_status = 'approved'),
  constraint pharmacies_reason_required check (
    approval_status not in ('rejected', 'suspended') or coalesce(btrim(status_reason), '') <> ''
  )
);
-- MVP: one pharmacy per owner account.
create unique index pharmacies_one_per_owner on public.pharmacies (owner_id);
create index pharmacies_public_idx on public.pharmacies (city) where approval_status = 'approved' and is_listed;
create index pharmacies_status_idx on public.pharmacies (approval_status, submitted_at);
create index pharmacies_geo_idx on public.pharmacies (latitude, longitude)
  where approval_status = 'approved' and is_listed and latitude is not null;

create table public.pharmacy_members (
  pharmacy_id uuid not null references public.pharmacies (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.member_role not null,
  status public.member_status not null default 'active',
  created_at timestamptz not null default now(),
  primary key (pharmacy_id, user_id)
);
create index pharmacy_members_user_idx on public.pharmacy_members (user_id) where status = 'active';

-- ---------------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------------
create table public.medicine_categories (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null check (char_length(btrim(name_ar)) between 1 and 80),
  name_en text check (name_en is null or char_length(name_en) <= 80),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index medicine_categories_name_ar_uq on public.medicine_categories (private.normalize_search(name_ar));

create table public.medicines (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.medicine_categories (id) on delete set null,
  name_ar text check (name_ar is null or char_length(name_ar) <= 160),
  name_en text check (name_en is null or char_length(name_en) <= 160),
  brand_name text check (brand_name is null or char_length(brand_name) <= 160),
  active_ingredient text check (active_ingredient is null or char_length(active_ingredient) <= 200),
  strength text check (strength is null or char_length(strength) <= 60),
  dosage_form text check (dosage_form is null or char_length(dosage_form) <= 60),
  package_description text check (package_description is null or char_length(package_description) <= 200),
  catalog_status public.catalog_status not null default 'pending',
  proposed_by uuid references public.profiles (id) on delete set null,
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  search_text text generated always as (
    private.normalize_search(
      coalesce(name_ar, '') || ' ' || coalesce(name_en, '') || ' ' || coalesce(brand_name, '') || ' ' ||
      coalesce(active_ingredient, '') || ' ' || coalesce(strength, '') || ' ' || coalesce(dosage_form, '')
    )
  ) stored,
  dedupe_key text generated always as (
    private.normalize_search(
      coalesce(name_ar, '') || '|' || coalesce(name_en, '') || '|' || coalesce(brand_name, '') || '|' ||
      coalesce(strength, '') || '|' || coalesce(dosage_form, '') || '|' || coalesce(package_description, '')
    )
  ) stored,
  constraint medicines_has_name check (coalesce(btrim(name_ar), '') <> '' or coalesce(btrim(name_en), '') <> '')
);
-- No duplicate live catalogue entries (rejected/archived rows may be re-proposed).
create unique index medicines_dedupe_uq on public.medicines (dedupe_key)
  where catalog_status in ('pending', 'approved');
create index medicines_search_trgm on public.medicines using gin (search_text extensions.gin_trgm_ops);
create index medicines_status_idx on public.medicines (catalog_status);
create index medicines_category_idx on public.medicines (category_id);

-- ---------------------------------------------------------------------------
-- Pharmacy list (what a pharmacy says it has; there are NO quantities)
-- ---------------------------------------------------------------------------
create table public.pharmacy_products (
  id uuid primary key default gen_random_uuid(),
  pharmacy_id uuid not null references public.pharmacies (id) on delete restrict,
  medicine_id uuid not null references public.medicines (id) on delete restrict,
  price numeric(14, 2) not null check (price > 0),
  is_available boolean not null default true,
  -- Last time a pharmacist confirmed this price / availability (explicit edit, request answer or bulk confirm).
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pharmacy_products_unique unique (pharmacy_id, medicine_id)
);
create index pharmacy_products_pharmacy_idx on public.pharmacy_products (pharmacy_id, is_available);
create index pharmacy_products_medicine_idx on public.pharmacy_products (medicine_id, confirmed_at desc)
  where is_available;

-- ---------------------------------------------------------------------------
-- Orders and reservations
-- ---------------------------------------------------------------------------
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  public_ref text not null unique,
  customer_id uuid not null references public.profiles (id) on delete restrict,
  pharmacy_id uuid not null references public.pharmacies (id) on delete restrict,
  status public.order_status not null default 'pending',
  currency text not null check (currency in ('SYP', 'USD')),
  subtotal numeric(14, 2) not null check (subtotal >= 0),
  -- Snapshot of the pharmacy at order time: customers cannot read `pharmacies`, and the order must stay
  -- understandable (where to go, whom to call) even if the pharmacy is suspended or renamed later.
  pharmacy_name text not null default '',
  pharmacy_address text,
  pharmacy_phone text,
  customer_name text not null default '' check (char_length(customer_name) <= 80),
  contact_phone text check (contact_phone is null or contact_phone ~ '^\+?[0-9]{7,15}$'),
  customer_notes text check (customer_notes is null or char_length(customer_notes) <= 300),
  reject_reason text check (reject_reason is null or char_length(reject_reason) <= 300),
  cancel_reason text check (cancel_reason is null or char_length(cancel_reason) <= 300),
  cancelled_by_role text check (cancelled_by_role is null or cancelled_by_role in ('customer', 'pharmacy')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  ready_at timestamptz,
  completed_at timestamptz,
  rejected_at timestamptz,
  cancelled_at timestamptz,
  expired_at timestamptz,
  reservation_expires_at timestamptz,
  constraint orders_reject_reason_required check (status <> 'rejected' or coalesce(btrim(reject_reason), '') <> '')
);
create index orders_customer_idx on public.orders (customer_id, created_at desc);
create index orders_pharmacy_status_idx on public.orders (pharmacy_id, status, created_at desc);
create index orders_expiry_idx on public.orders (status, reservation_expires_at)
  where status in ('accepted', 'ready_for_pickup');

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  line_no integer not null,
  product_id uuid not null references public.pharmacy_products (id) on delete restrict,
  medicine_id uuid not null references public.medicines (id) on delete restrict,
  medicine_name text not null,
  strength text,
  dosage_form text,
  quantity integer not null check (quantity > 0),
  unit_price numeric(14, 2) not null check (unit_price >= 0),
  line_total numeric(14, 2) generated always as (quantity * unit_price) stored,
  constraint order_items_unique_product unique (order_id, product_id)
);
create index order_items_product_idx on public.order_items (product_id);

-- ---------------------------------------------------------------------------
-- Sales (immutable)
-- ---------------------------------------------------------------------------
create table public.pharmacy_invoice_counters (
  pharmacy_id uuid primary key references public.pharmacies (id) on delete restrict,
  last_number integer not null default 0
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  pharmacy_id uuid not null references public.pharmacies (id) on delete restrict,
  invoice_no text not null,
  order_id uuid unique references public.orders (id) on delete restrict,
  payment_method public.payment_method not null default 'cash',
  currency text not null check (currency in ('SYP', 'USD')),
  subtotal numeric(14, 2) not null check (subtotal >= 0),
  discount_amount numeric(14, 2) not null default 0 check (discount_amount >= 0),
  total numeric(14, 2) not null check (total >= 0),
  cashier_id uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint sales_invoice_unique unique (pharmacy_id, invoice_no),
  constraint sales_total_consistent check (total = subtotal - discount_amount),
  constraint sales_discount_le_subtotal check (discount_amount <= subtotal)
);
create index sales_pharmacy_created_idx on public.sales (pharmacy_id, created_at desc);
create index sales_cashier_idx on public.sales (cashier_id);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id) on delete restrict,
  line_no integer not null,
  product_id uuid not null references public.pharmacy_products (id) on delete restrict,
  product_name text not null,
  strength text,
  quantity integer not null check (quantity > 0),
  unit_price numeric(14, 2) not null check (unit_price >= 0),
  line_total numeric(14, 2) generated always as (quantity * unit_price) stored
);
create index sale_items_sale_idx on public.sale_items (sale_id);
create index sale_items_product_idx on public.sale_items (product_id);

-- ---------------------------------------------------------------------------
-- Availability requests ("is this medicine available near me?"), see docs/availability_design.md
-- Clients have NO access to these tables; everything goes through the RPC functions.
-- ---------------------------------------------------------------------------
create table public.availability_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete cascade,
  medicine_id uuid not null references public.medicines (id) on delete restrict,
  -- The customer's position, rounded to 3 decimals (~100 m) by the RPC. Never shown to pharmacies.
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  step integer not null default 1 check (step between 1 and 4),
  status public.request_status not null default 'open',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_expanded_at timestamptz not null default now(),
  closed_at timestamptz
);
create index availability_requests_customer_idx on public.availability_requests (customer_id, created_at desc);
create index availability_requests_open_idx on public.availability_requests (expires_at) where status = 'open';

-- One row per (request, notified pharmacy); the pharmacy's answer is stored on the same row.
create table public.availability_targets (
  request_id uuid not null references public.availability_requests (id) on delete cascade,
  pharmacy_id uuid not null references public.pharmacies (id) on delete cascade,
  step integer not null check (step between 1 and 4),
  distance_km numeric(7, 2) not null check (distance_km >= 0),
  notified_at timestamptz not null default now(),
  answer public.request_answer,
  price numeric(14, 2) check (price is null or price > 0),
  answered_by uuid references public.profiles (id) on delete set null,
  answered_at timestamptz,
  primary key (request_id, pharmacy_id),
  constraint availability_targets_answer_shape check (
    (answer is null and price is null and answered_at is null)
    or (answer = 'available' and price is not null and answered_at is not null)
    or (answer = 'unavailable' and price is null and answered_at is not null)
  )
);
create index availability_targets_pharmacy_idx on public.availability_targets (pharmacy_id, notified_at desc);

-- ---------------------------------------------------------------------------
-- Platform
-- ---------------------------------------------------------------------------
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles (id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  pharmacy_id uuid references public.pharmacies (id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_created_idx on public.audit_logs (created_at desc);
create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id);

create table public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  target_type public.report_target not null,
  target_id uuid,
  category text not null check (char_length(btrim(category)) between 2 and 60),
  description text not null check (char_length(btrim(description)) between 5 and 1000),
  status public.report_status not null default 'open',
  resolution_note text check (resolution_note is null or char_length(resolution_note) <= 500),
  resolved_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index user_reports_status_idx on public.user_reports (status, created_at desc);
create index user_reports_reporter_idx on public.user_reports (reporter_id);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null,
  entity_type text,
  entity_id uuid,
  params jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

create table public.idempotency_keys (
  user_id uuid not null references public.profiles (id) on delete cascade,
  scope text not null,
  key text not null,
  request_hash text not null,
  response jsonb,
  created_at timestamptz not null default now(),
  primary key (user_id, scope, key)
);
create index idempotency_keys_created_idx on public.idempotency_keys (created_at);
