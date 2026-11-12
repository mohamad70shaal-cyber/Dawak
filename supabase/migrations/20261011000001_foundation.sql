-- Dawak foundation: schemas, extensions, enums and pure (table-independent) helpers.

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- `private` holds helpers that must never be exposed through the API.
create schema if not exists private;

-- PostgreSQL grants EXECUTE on every new function to PUBLIC by default, and
-- `ALTER DEFAULT PRIVILEGES IN SCHEMA ... REVOKE` cannot remove that built-in default.
-- Revoking it globally (for the role running migrations) makes a forgotten GRANT fail closed.
alter default privileges revoke execute on functions from public;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('customer', 'pharmacist', 'admin');
create type public.account_status as enum ('active', 'suspended');
create type public.approval_status as enum ('pending', 'approved', 'rejected', 'suspended');
create type public.member_role as enum ('owner', 'manager', 'cashier');
create type public.member_status as enum ('active', 'suspended', 'removed');
create type public.catalog_status as enum ('pending', 'approved', 'rejected', 'archived');
create type public.order_status as enum (
  'pending', 'accepted', 'ready_for_pickup', 'completed', 'rejected', 'cancelled', 'expired'
);
-- Availability requests ("ask the pharmacies nearby"), see docs/availability_design.md.
create type public.request_status as enum ('open', 'closed', 'expired');
create type public.request_answer as enum ('available', 'unavailable');
create type public.report_status as enum ('open', 'in_review', 'resolved', 'dismissed');
create type public.report_target as enum ('pharmacy', 'medicine', 'order', 'app', 'other');
create type public.payment_method as enum ('cash');

-- ---------------------------------------------------------------------------
-- Server-side configuration (change via a new migration)
-- ---------------------------------------------------------------------------
create function private.cfg_int(p_key text) returns integer
language sql immutable parallel safe as $$
  select case p_key
    when 'reservation_hours'         then 24    -- how long a pharmacy promises to hold an accepted order
    when 'fresh_days'                then 7     -- listing confirmed within this many days is "recent"
    when 'listing_max_age_days'      then 30    -- listings not confirmed for longer are hidden from customers
    when 'max_pending_orders'        then 5
    when 'max_orders_per_hour'       then 10
    when 'max_customer_qty_per_item' then 10
    when 'max_order_lines'           then 20
    when 'max_pos_qty_per_item'      then 999
    when 'max_pos_lines'             then 100
    when 'request_ttl_minutes'       then 60    -- life of an availability request
    when 'request_wait_minutes'      then 3     -- silence before the radius is widened
    when 'request_max_step'          then 4     -- radius steps, see request_radius_km
    when 'max_open_requests'         then 3     -- open requests per customer
    when 'max_requests_per_hour'     then 10     -- requests created per customer per hour
    when 'max_request_targets'       then 25    -- pharmacies notified per request (nearest first)
    when 'request_dedupe_minutes'    then 15    -- same medicine, same spot: reuse the open request
    when 'max_import_items'          then 500   -- rows per bulk import call
    when 'max_match_names'           then 100   -- names per catalogue-matching call
  end
$$;

-- ---------------------------------------------------------------------------
-- Error signalling: business failures are P0001 with MESSAGE = machine code.
-- ---------------------------------------------------------------------------
create function private.fail(p_code text, p_detail jsonb default null) returns void
language plpgsql as $$
begin
  raise exception using
    errcode = 'P0001',
    message = p_code,
    detail = coalesce(p_detail::text, '');
end
$$;

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------
-- Normalised search text: lowercase, strip tashkeel/tatweel, fold alef/ya/ta-marbuta/hamza
-- variants and Persian kaf/ya, map Arabic-Indic and Persian digits to ASCII.
-- from: أ إ آ ٱ ى ة ؤ ئ ک ی  + ٠-٩ + ۰-۹   (10 + 10 + 10 = 30 characters)
-- to  : ا ا ا ا ي ه و ي ك ي  + 0-9 + 0-9
create function private.normalize_search(p_text text) returns text
language sql immutable parallel safe as $$
  select btrim(
    regexp_replace(
      translate(
        lower(regexp_replace(coalesce(p_text, ''), '[ً-ٰٟـ]', '', 'g')),
        'أإآٱىةؤئکی٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
        'اااايهويكي01234567890123456789'
      ),
      '\s+', ' ', 'g'
    )
  )
$$;

create function private.like_escape(p_text text) returns text
language sql immutable parallel safe as $$
  select replace(replace(replace(p_text, '\', '\\'), '%', '\%'), '_', '\_')
$$;

-- Returns a normalised phone (ASCII digits, optional leading +, 7-15 digits) or NULL.
create function private.clean_phone(p_text text) returns text
language sql immutable parallel safe as $$
  select case when s.v ~ '^\+?[0-9]{7,15}$' then s.v else null end
  from (
    select regexp_replace(
             translate(coalesce(p_text, ''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'),
             '[\s\-\(\)\.]', '', 'g'
           ) as v
  ) s
$$;

-- Validates and trims a required/optional text input.
create function private.req_text(
  p_value text, p_field text, p_min integer, p_max integer, p_required boolean default true
) returns text
language plpgsql immutable as $$
declare
  v text := btrim(coalesce(p_value, ''));
begin
  if v = '' then
    if p_required then
      perform private.fail('invalid_input', jsonb_build_object('field', p_field, 'reason', 'required'));
    end if;
    return null;
  end if;
  if char_length(v) < p_min or char_length(v) > p_max then
    perform private.fail('invalid_input', jsonb_build_object('field', p_field, 'reason', 'length'));
  end if;
  return v;
end
$$;

-- ---------------------------------------------------------------------------
-- Domain helpers
-- ---------------------------------------------------------------------------
create function private.generate_order_ref() returns text
language sql volatile as $$
  select 'DWK-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
$$;

create function private.order_transition_allowed(p_from public.order_status, p_to public.order_status)
returns boolean
language sql immutable as $$
  select (p_from, p_to) in (
    ('pending'::public.order_status,          'accepted'::public.order_status),
    ('pending'::public.order_status,          'rejected'::public.order_status),
    ('pending'::public.order_status,          'cancelled'::public.order_status),
    ('accepted'::public.order_status,         'ready_for_pickup'::public.order_status),
    ('accepted'::public.order_status,         'cancelled'::public.order_status),
    ('accepted'::public.order_status,         'expired'::public.order_status),
    ('ready_for_pickup'::public.order_status, 'completed'::public.order_status),
    ('ready_for_pickup'::public.order_status, 'cancelled'::public.order_status),
    ('ready_for_pickup'::public.order_status, 'expired'::public.order_status),
    ('expired'::public.order_status,          'accepted'::public.order_status),
    ('expired'::public.order_status,          'cancelled'::public.order_status)
  )
$$;

-- How fresh a pharmacy's confirmation is: 'recent' (<= fresh_days) or 'old'.
create function private.listing_freshness(p_confirmed timestamptz) returns text
language sql stable as $$
  select case
    when p_confirmed >= now() - make_interval(days => private.cfg_int('fresh_days')) then 'recent'
    else 'old'
  end
$$;

-- ---------------------------------------------------------------------------
-- Geography (no PostGIS needed: great-circle distance on a sphere is plenty for "within N km")
-- ---------------------------------------------------------------------------
create function private.distance_km(
  p_lat1 double precision, p_lon1 double precision, p_lat2 double precision, p_lon2 double precision
) returns double precision
language sql immutable parallel safe as $$
  select 2 * 6371.0088 * asin(least(1.0, sqrt(
    power(sin(radians(p_lat2 - p_lat1) / 2), 2) +
    cos(radians(p_lat1)) * cos(radians(p_lat2)) * power(sin(radians(p_lon2 - p_lon1) / 2), 2)
  )))
$$;

-- Radius (km) of each widening step of an availability request.
create function private.request_radius_km(p_step integer) returns double precision
language sql immutable parallel safe as $$
  select case p_step when 1 then 1.0 when 2 then 3.0 when 3 then 5.0 when 4 then 10.0 end
$$;

-- Validates a coordinate pair (both present, inside the valid ranges, not the (0,0) placeholder).
create function private.check_location(p_lat double precision, p_lng double precision) returns void
language plpgsql immutable as $$
begin
  if p_lat is null or p_lng is null
     or p_lat <> p_lat or p_lng <> p_lng                       -- NaN
     or p_lat not between -90 and 90 or p_lng not between -180 and 180
     or (p_lat = 0 and p_lng = 0) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'location'));
  end if;
end
$$;

-- Start of a local calendar day as timestamptz.
create function private.local_day_start(p_day date, p_tz text) returns timestamptz
language sql immutable as $$
  select (p_day::timestamp) at time zone p_tz
$$;
