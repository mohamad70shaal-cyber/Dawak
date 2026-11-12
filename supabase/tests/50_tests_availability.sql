-- "Ask the pharmacies nearby": availability requests (docs/availability_design.md).
--
-- Fixture geometry (see tests.fx): pharmacy A (33.5100, 36.2800), pharmacy B (33.5150, 36.2800).
-- The standard customer spot is (33.5110, 36.2800): A is 0.11 km away, B 0.44 km.
-- Tests that need pharmacies at larger distances move them with tests.place_pharmacy().

-- Test-only: put a pharmacy at a given latitude (same longitude as the customer), as the superuser.
create function tests.place_pharmacy(p_pharmacy uuid, p_lat double precision) returns void
language plpgsql as $$
begin
  perform tests.reset();
  update public.pharmacies set latitude = p_lat, longitude = 36.2800 where id = p_pharmacy;
end
$$;

create function tests.ask(p_customer uuid, p_medicine uuid, p_key text,
                          p_lat double precision default 33.5110, p_lng double precision default 36.2800)
returns jsonb
language plpgsql as $$
declare
  v jsonb;
begin
  perform tests.act_as(p_customer);
  v := public.create_availability_request(p_medicine, p_lat, p_lng, p_key);
  return v;
end
$$;

-- Test-only clock: pretend the last widening happened p_minutes ago.
create function tests.age_request(p_request uuid, p_minutes integer) returns void
language plpgsql as $$
begin
  perform tests.reset();
  update public.availability_requests set last_expanded_at = now() - make_interval(mins => p_minutes) where id = p_request;
end
$$;

-- Test-only: read internals (request/target rows, notifications) whichever role the test is acting as.
create function tests.su_count(p_sql text) returns bigint
language plpgsql security definer as $$
declare
  v bigint;
begin
  execute 'select count(*) from (' || p_sql || ') q' into v;
  return v;
end
$$;

create function tests.su_text(p_sql text) returns text
language plpgsql security definer as $$
declare
  v text;
begin
  execute 'select (' || p_sql || ')::text' into v;
  return v;
end
$$;

create function tests.notif_count(p_user uuid, p_kind text) returns bigint
language sql security definer as $$
  select count(*) from public.notifications where user_id = p_user and kind = p_kind
$$;

-- ---------------------------------------------------------------------------
-- Geography helpers
-- ---------------------------------------------------------------------------
create function tests.t_req_00_geography_helpers() returns void
language plpgsql as $$
begin
  perform tests.ok(abs(private.distance_km(33.5100, 36.2800, 33.5200, 36.2800) - 1.112) < 0.01, 'one hundredth of a degree of latitude is ~1.11 km');
  perform tests.ok(abs(private.distance_km(33.5, 36.0, 33.5, 36.1) - 9.27) < 0.1, 'longitude degrees shrink with latitude (33.5°N: 0.1° ≈ 9.3 km)');
  perform tests.eq(private.distance_km(33.5, 36.2, 33.5, 36.2), 0::double precision, 'same point is zero');
  perform tests.eq(private.request_radius_km(1), 1::double precision, 'step 1 = 1 km');
  perform tests.eq(private.request_radius_km(2), 3::double precision, 'step 2 = 3 km');
  perform tests.eq(private.request_radius_km(3), 5::double precision, 'step 3 = 5 km');
  perform tests.eq(private.request_radius_km(4), 10::double precision, 'step 4 = 10 km');
  perform tests.raises('select private.check_location(NULL, 36)', 'invalid_input', 'null latitude');
  perform tests.raises('select private.check_location(33, NULL)', 'invalid_input', 'null longitude');
  perform tests.raises('select private.check_location(91, 36)', 'invalid_input', 'latitude above 90');
  perform tests.raises('select private.check_location(33, -181)', 'invalid_input', 'longitude below -180');
  perform tests.raises('select private.check_location(0, 0)', 'invalid_input', '(0,0) is the classic "no GPS fix" value');
  perform tests.raises('select private.check_location(''NaN''::double precision, 36)', 'invalid_input', 'NaN');
  perform tests.eq(private.listing_freshness(now() - interval '6 days'), 'recent', 'six days is recent');
  perform tests.eq(private.listing_freshness(now() - interval '8 days'), 'old', 'eight days is old');
end
$$;

-- ---------------------------------------------------------------------------
-- Creating a request
-- ---------------------------------------------------------------------------
create function tests.t_req_01_create_targets_and_notifications() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  v jsonb;
  v_id uuid;
  r record;
begin
  -- noisy coordinates are rounded to 3 decimals before they are stored
  v := tests.ask(c1, m1, 'req-key-0001', 33.51149, 36.28001);
  v_id := (v ->> 'id')::uuid;
  perform tests.eq(v ->> 'status', 'open', 'request is open');
  perform tests.eq((v ->> 'step')::int, 1, 'starts at step 1');
  perform tests.eq((v ->> 'radius_km')::numeric, 1::numeric, 'radius 1 km');
  perform tests.eq((v ->> 'radius_exhausted')::boolean, false, 'not at the largest radius');
  perform tests.eq((v ->> 'notified')::int, 2, 'both pharmacies are inside 1 km');
  perform tests.eq((v ->> 'answered')::int, 0, 'nobody answered yet');
  perform tests.eq(jsonb_array_length(v -> 'offers'), 0, 'no offers yet');
  perform tests.ok((v ->> 'seconds_left')::int between 3590 and 3600, 'lives 60 minutes (was ' || (v ->> 'seconds_left') || ')');
  perform tests.eq(v -> 'medicine' ->> 'name_ar', 'بنادول', 'medicine summary');
  perform tests.eq(tests.su_text(format('select latitude from public.availability_requests where id = %L', v_id))::double precision, 33.511::double precision, 'latitude rounded to ~100 m');
  perform tests.eq(tests.su_text(format('select longitude from public.availability_requests where id = %L', v_id))::double precision, 36.28::double precision, 'longitude rounded to ~100 m');
  perform tests.eq(tests.su_count(format('select 1 from public.availability_targets where request_id = %L and step = 1', v_id)), 2::bigint, 'two step-1 targets');
  perform tests.ok(tests.su_text(format('select distance_km from public.availability_targets where request_id = %L and pharmacy_id = %L', v_id, ph_a))::numeric between 0.10 and 0.12, 'stored distance A');
  perform tests.ok(tests.su_text(format('select distance_km from public.availability_targets where request_id = %L and pharmacy_id = %L', v_id, ph_b))::numeric between 0.43 and 0.46, 'stored distance B');

  -- both pharmacies were told; the notification says which medicine and nothing about the customer
  perform tests.eq(tests.notif_count(pa, 'availability_request'), 1::bigint, 'pharmacy A notified once');
  perform tests.eq(tests.notif_count(pb, 'availability_request'), 1::bigint, 'pharmacy B notified once');
  perform tests.eq(tests.su_text(format($q$select params ->> 'medicine' from public.notifications where user_id = %L and kind = 'availability_request'$q$, pa)), 'بنادول', 'notification names the medicine');
  perform tests.eq(tests.su_text(format($q$select entity_id from public.notifications where user_id = %L and kind = 'availability_request'$q$, pa))::uuid, v_id, 'notification points at the request');
  perform tests.ok(tests.su_text(format($q$select params from public.notifications where user_id = %L and kind = 'availability_request'$q$, pa)) !~ c1::text, 'notification does not leak the customer id');

  -- idempotent retry returns the same request and notifies nobody again
  perform tests.act_as(c1);
  perform tests.eq((public.create_availability_request(m1, 33.51149, 36.28001, 'req-key-0001') ->> 'id')::uuid, v_id, 'same key returns the same request');
  perform tests.eq(tests.notif_count(pa, 'availability_request'), 1::bigint, 'no second notification on retry');
  perform tests.raises(format('select public.create_availability_request(%L, 33.6, 36.28, %L)', m1, 'req-key-0001'), 'duplicate_request', 'same key, different request');
  perform tests.raises(format('select public.create_availability_request(%L, 33.5110, 36.2800, %L)', m1, 'short'), 'invalid_input', 'idempotency key too short');

  -- same medicine from nearly the same spot reuses the open request (new key, no new notifications)
  perform tests.eq((public.create_availability_request(m1, 33.5112, 36.2801, 'req-key-0002') ->> 'id')::uuid, v_id, 'duplicate ask within 15 min / 0.5 km reuses the request');
  perform tests.eq(tests.notif_count(pa, 'availability_request'), 1::bigint, 'still one notification');
  perform tests.eq(tests.su_count('select 1 from public.availability_requests'), 1::bigint, 'still one request row');
  -- ...but a spot more than 0.5 km away is a new question
  perform tests.ok((public.create_availability_request(m1, 33.5200, 36.2800, 'req-key-0003') ->> 'id')::uuid <> v_id, 'a different spot is a different request');

  -- inbox rows say nothing about the customer
  perform tests.act_as(pa);
  select * into r from public.list_pharmacy_availability_requests(ph_a) where request_id = v_id;
  perform tests.eq(r.medicine_id, m1, 'inbox shows the medicine');
  perform tests.ok(r.distance_km between 0.10 and 0.12, 'inbox shows the distance');
  perform tests.ok(r.answer is null, 'unanswered');
  perform tests.eq(r.listed_price, 1000.00, 'inbox shows the pharmacy''s own listed price for pre-filling');
  perform tests.eq(r.listed_available, true, 'and whether it is listed as available');
  perform tests.ok(to_jsonb(r)::text !~ (c1::text || '|33\.511|36\.28|customer'), 'no customer id, coordinates or customer field in the inbox row');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_req_02_create_validation_and_visibility_rules() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  admin uuid := tests.uid(fx, 'admin');
  m1 uuid := tests.uid(fx, 'm1');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  v_pending uuid;
  v jsonb;
begin
  perform tests.act_as(pa);
  v_pending := ((public.propose_medicine('دواء قيد المراجعة', 'Pending Drug', null, 'x', '5mg', 'أقراص', 'علبة')) ->> 'id')::uuid;

  perform tests.act_as(c1);
  perform tests.raises(format('select public.create_availability_request(%L, NULL, 36.28, %L)', m1, 'val-key-0001'), 'invalid_input', 'latitude required');
  perform tests.raises(format('select public.create_availability_request(%L, 33.5, NULL, %L)', m1, 'val-key-0002'), 'invalid_input', 'longitude required');
  perform tests.raises(format('select public.create_availability_request(%L, 120, 36.28, %L)', m1, 'val-key-0003'), 'invalid_input', 'latitude out of range');
  perform tests.raises(format('select public.create_availability_request(%L, 0, 0, %L)', m1, 'val-key-0004'), 'invalid_input', '(0,0) refused');
  perform tests.raises(format('select public.create_availability_request(%L, 33.5110, 36.28, %L)', gen_random_uuid(), 'val-key-0005'), 'not_found', 'unknown medicine');
  perform tests.raises(format('select public.create_availability_request(%L, 33.5110, 36.28, %L)', v_pending, 'val-key-0006'), 'not_found', 'pending medicine cannot be asked about');
  perform tests.raises(format('select public.create_availability_request(NULL, 33.5110, 36.28, %L)', 'val-key-0007'), 'invalid_input', 'a missing medicine is invalid input');
  perform tests.eq(tests.su_count('select 1 from public.availability_requests'), 0::bigint, 'nothing was stored by the failed attempts');

  -- only customers ask
  perform tests.act_as(pa);
  perform tests.raises(format('select public.create_availability_request(%L, 33.5110, 36.28, %L)', m1, 'val-key-0008'), 'forbidden', 'a pharmacist cannot ask');
  perform tests.act_as(admin);
  perform tests.raises(format('select public.create_availability_request(%L, 33.5110, 36.28, %L)', m1, 'val-key-0009'), 'forbidden', 'an admin cannot ask');
  perform tests.act_as_anon();
  perform tests.raises(format('select public.create_availability_request(%L, 33.5110, 36.28, %L)', m1, 'val-key-0010'), '42501', 'anonymous cannot ask');

  -- an unlisted or suspended pharmacy is not asked
  perform tests.reset();
  update public.pharmacies set is_listed = false where id = ph_b;
  v := tests.ask(c1, m1, 'val-key-0011');
  perform tests.eq((v ->> 'notified')::int, 1, 'unlisted pharmacy is skipped');
  perform tests.act_as(c1);
  perform public.close_availability_request((v ->> 'id')::uuid);
  perform tests.reset();
  update public.pharmacies set is_listed = true where id = ph_b;
  perform tests.act_as(admin);
  perform public.admin_review_pharmacy(ph_a, 'suspend', 'مخالفة');
  v := tests.ask(c1, m1, 'val-key-0012');
  perform tests.eq((v ->> 'notified')::int, 1, 'suspended pharmacy is skipped');
  perform tests.eq(tests.su_count(format('select 1 from public.availability_targets where request_id = %L and pharmacy_id = %L', v ->> 'id', ph_a)), 0::bigint, 'suspended pharmacy is not a target');
  perform tests.act_as(c1);
  perform public.close_availability_request((v ->> 'id')::uuid);

  -- a pharmacy without a location (legacy row) can never be targeted
  perform tests.reset();
  update public.pharmacies set approval_status = 'approved', status_reason = null, is_listed = true where id = ph_a;
  update public.pharmacies set latitude = null, longitude = null where id = ph_b;
  v := tests.ask(c1, m1, 'val-key-0013');
  perform tests.eq((v ->> 'notified')::int, 1, 'pharmacy without coordinates is skipped');
end
$$;

create function tests.t_req_03_caps_per_customer() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  m1 uuid := tests.uid(fx, 'm1');
  m2 uuid := tests.uid(fx, 'm2');
  m3 uuid := tests.uid(fx, 'm3');
  v_m4 uuid;
  v_first uuid;
  i integer;
begin
  insert into public.medicines (name_ar, name_en, active_ingredient, strength, dosage_form, package_description, catalog_status)
  values ('دواء رابع', 'Fourth Drug', 'x', '5mg', 'أقراص', 'علبة', 'approved') returning id into v_m4;

  v_first := (tests.ask(c1, m1, 'cap-key-0001') ->> 'id')::uuid;
  perform tests.ask(c1, m2, 'cap-key-0002');
  perform tests.ask(c1, m3, 'cap-key-0003');
  perform tests.raises(format('select public.create_availability_request(%L, 33.5110, 36.28, %L)', v_m4, 'cap-key-0004'), 'too_many_requests', 'a fourth open request is refused');
  perform tests.eq((public.create_availability_request(m1, 33.5110, 36.2800, 'cap-key-0005') ->> 'id')::uuid, v_first, 'asking again about an open one still works (reuse)');

  -- closing one frees a slot
  perform public.close_availability_request(v_first);
  perform tests.eq(public.create_availability_request(v_m4, 33.5110, 36.2800, 'cap-key-0006') ->> 'status', 'open', 'slot freed by closing');

  -- the caps are per customer
  perform tests.eq(tests.ask(c2, m1, 'cap-key-0007') ->> 'status', 'open', 'another customer is not affected');

  -- hourly rate limit: ten requests in the last hour, however they ended
  perform tests.reset();
  delete from public.availability_requests where customer_id = c2;
  for i in 1..10 loop
    insert into public.availability_requests (customer_id, medicine_id, latitude, longitude, status, expires_at, closed_at)
    values (c2, m1, 33.0 + i, 36.28, 'closed', now() + interval '1 hour', now());
  end loop;
  perform tests.act_as(c2);
  perform tests.raises(format('select public.create_availability_request(%L, 33.5110, 36.28, %L)', m2, 'cap-key-0008'), 'rate_limited', 'eleventh request within an hour');
  perform tests.reset();
  update public.availability_requests set created_at = now() - interval '2 hours' where customer_id = c2;
  perform tests.act_as(c2);
  perform tests.eq(public.create_availability_request(m2, 33.5110, 36.2800, 'cap-key-0009') ->> 'status', 'open', 'allowed again once they are older than an hour');
end
$$;

-- ---------------------------------------------------------------------------
-- Answering
-- ---------------------------------------------------------------------------
create function tests.t_req_04_answers_update_offers_and_the_pharmacy_list() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  m3 uuid := tests.uid(fx, 'm3');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  a1 uuid := tests.uid(fx, 'a1');
  b1 uuid := tests.uid(fx, 'b1');
  v jsonb;
  v_id uuid;
begin
  v := tests.ask(c1, m1, 'ans-key-0001');
  v_id := (v ->> 'id')::uuid;

  -- A says available at a new price: the customer sees an offer, the list learns the price
  perform tests.act_as(pa);
  v := public.answer_availability_request(ph_a, v_id, true, 1200);
  perform tests.eq(v ->> 'answer', 'available', 'answer echoed');
  perform tests.eq((v ->> 'price')::numeric, 1200.00, 'price echoed');
  perform tests.eq((select price from public.pharmacy_products where id = a1), 1200.00, 'list price updated from the answer');
  perform tests.ok((select confirmed_at from public.pharmacy_products where id = a1) > now() - interval '1 minute', 'and confirmed now');
  perform tests.act_as(c1);
  v := public.get_availability_request(v_id);
  perform tests.eq((v ->> 'answered')::int, 1, 'one answer');
  perform tests.eq((v ->> 'unavailable')::int, 0, 'none unavailable');
  perform tests.eq(jsonb_array_length(v -> 'offers'), 1, 'one offer');
  perform tests.eq(v -> 'offers' -> 0 ->> 'pharmacy_id', ph_a::text, 'offer is A');
  perform tests.eq((v -> 'offers' -> 0 ->> 'price')::numeric, 1200.00, 'offer price');
  perform tests.ok((v -> 'offers' -> 0 ->> 'distance_km')::numeric between 0.10 and 0.12, 'offer distance');
  perform tests.eq(v -> 'offers' -> 0 ->> 'phone', '0933111111', 'phone shown when the pharmacy agreed');
  perform tests.eq(v -> 'offers' -> 0 ->> 'name', 'Pharmacy A', 'pharmacy name');
  perform tests.ok(v -> 'offers' -> 0 ->> 'latitude' is not null and v -> 'offers' -> 0 ->> 'longitude' is not null, 'coordinates for directions');
  perform tests.eq(v -> 'offers' -> 0 ->> 'product_id', a1::text, 'offer links the list row');
  perform tests.eq(tests.notif_count(c1, 'availability_found'), 1::bigint, 'customer told about the first offer');

  -- B also says available: sorted nearest first, but no second "found" notification
  perform tests.act_as(pb);
  perform public.answer_availability_request(ph_b, v_id, true, 1300);
  perform tests.act_as(c1);
  v := public.get_availability_request(v_id);
  perform tests.eq(jsonb_array_length(v -> 'offers'), 2, 'two offers');
  perform tests.eq(v -> 'offers' -> 0 ->> 'pharmacy_id', ph_a::text, 'nearest first');
  perform tests.eq(v -> 'offers' -> 1 ->> 'pharmacy_id', ph_b::text, 'then B');
  perform tests.eq(tests.notif_count(c1, 'availability_found'), 1::bigint, 'only the first offer notifies');

  -- B changes its mind: offer disappears, list row is marked unavailable, price is dropped
  perform tests.act_as(pb);
  v := public.answer_availability_request(ph_b, v_id, false);
  perform tests.eq(v ->> 'answer', 'unavailable', 'now unavailable');
  perform tests.ok(v ->> 'price' is null, 'no price when unavailable');
  perform tests.eq((select is_available from public.pharmacy_products where id = b1), false, 'list row marked unavailable');
  perform tests.act_as(c1);
  v := public.get_availability_request(v_id);
  perform tests.eq(jsonb_array_length(v -> 'offers'), 1, 'only A remains');
  perform tests.eq((v ->> 'unavailable')::int, 1, 'one unavailable');
  perform tests.eq((v ->> 'answered')::int, 2, 'two answered');
  perform tests.ok(v::text !~ 'Pharmacy B', 'customers never see pharmacies that said no');

  -- a medicine not on the list yet: an owner''s "available" creates the row, a later "unavailable" flips it
  v := tests.ask(c1, m3, 'ans-key-0002');
  v_id := (v ->> 'id')::uuid;
  perform tests.eq(tests.count(format('select 1 from public.pharmacy_products where pharmacy_id = %L and medicine_id = %L', ph_a, m3)), 0::bigint, 'not listed before');
  perform tests.act_as(pa);
  perform public.answer_availability_request(ph_a, v_id, true, 700);
  perform tests.eq((select price from public.pharmacy_products where pharmacy_id = ph_a and medicine_id = m3), 700.00, 'row created from the answer');
  perform tests.eq((select is_available from public.pharmacy_products where pharmacy_id = ph_a and medicine_id = m3), true, 'created as available');
  perform public.answer_availability_request(ph_a, v_id, false);
  perform tests.eq((select is_available from public.pharmacy_products where pharmacy_id = ph_a and medicine_id = m3), false, 'flipped to unavailable');
  -- ...and an "unavailable" for something never listed does not create rows
  perform tests.eq(tests.count(format('select 1 from public.pharmacy_products where pharmacy_id = %L and medicine_id = %L', ph_b, m3)), 0::bigint, 'B never listed m3');
  perform tests.act_as(pb);
  perform public.answer_availability_request(ph_b, v_id, false);
  perform tests.eq(tests.count(format('select 1 from public.pharmacy_products where pharmacy_id = %L and medicine_id = %L', ph_b, m3)), 0::bigint, 'unavailable does not create a list row');

  -- hidden phone numbers stay hidden in offers
  perform tests.reset();
  update public.pharmacies set show_phone_publicly = false where id = ph_a;
  perform tests.act_as(pa);
  perform public.answer_availability_request(ph_a, v_id, true, 710);
  perform tests.act_as(c1);
  v := public.get_availability_request(v_id);
  perform tests.ok(v -> 'offers' -> 0 -> 'phone' = 'null'::jsonb, 'hidden phone is null in offers');

  -- a pharmacy that is suspended afterwards drops out of the offers
  perform tests.act_as(tests.uid(fx, 'admin'));
  perform public.admin_review_pharmacy(ph_a, 'suspend', 'مخالفة');
  perform tests.act_as(c1);
  perform tests.eq(jsonb_array_length(public.get_availability_request(v_id) -> 'offers'), 0, 'suspended pharmacy offers vanish');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_req_05_answer_validation_and_roles() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  m1 uuid := tests.uid(fx, 'm1');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  a1 uuid := tests.uid(fx, 'a1');
  v_cashier uuid;
  v_id uuid;
  v jsonb;
begin
  -- B is far away (2.1 km): only A is a target of the first request
  perform tests.place_pharmacy(ph_b, 33.5300);
  v_cashier := tests.mk_cashier(ph_a, 'cashier@t.test');
  v_id := (tests.ask(c1, m1, 'val2-key-0001') ->> 'id')::uuid;

  perform tests.act_as(pa);
  perform tests.raises(format('select public.answer_availability_request(%L, %L, true)', ph_a, v_id), 'invalid_input', 'available needs a price');
  perform tests.raises(format('select public.answer_availability_request(%L, %L, true, 0)', ph_a, v_id), 'invalid_input', 'price zero');
  perform tests.raises(format('select public.answer_availability_request(%L, %L, true, -5)', ph_a, v_id), 'invalid_input', 'negative price');
  perform tests.raises(format('select public.answer_availability_request(%L, %L, true, 10.123)', ph_a, v_id), 'invalid_input', 'three decimals');
  perform tests.raises(format('select public.answer_availability_request(%L, %L, true, 1000000000000)', ph_a, v_id), 'invalid_input', 'absurd price');
  perform tests.raises(format('select public.answer_availability_request(%L, %L, NULL, 5)', ph_a, v_id), 'invalid_input', 'null answer');
  perform tests.ok(public.answer_availability_request(ph_a, v_id, false, 12345) ->> 'price' is null, 'a price sent with "unavailable" is ignored');
  perform tests.eq((select price from public.pharmacy_products where id = a1), 1000.00, 'failed attempts changed no price');

  -- someone else's pharmacy, a pharmacy that was not asked, a made-up request
  perform tests.act_as(pb);
  perform tests.raises(format('select public.answer_availability_request(%L, %L, false)', ph_a, v_id), 'forbidden', 'cannot answer for another pharmacy');
  perform tests.raises(format('select public.answer_availability_request(%L, %L, false)', ph_b, v_id), 'not_found', 'own pharmacy but it was not asked');
  perform tests.raises(format('select public.answer_availability_request(%L, %L, false)', ph_b, gen_random_uuid()), 'not_found', 'unknown request');
  perform tests.act_as(c1);
  perform tests.raises(format('select public.answer_availability_request(%L, %L, false)', ph_a, v_id), 'forbidden', 'a customer cannot answer');
  perform tests.act_as_anon();
  perform tests.raises(format('select public.answer_availability_request(%L, %L, false)', ph_a, v_id), '42501', 'anonymous cannot answer');

  -- a cashier may answer, but the pharmacy's price list is not theirs to change
  perform tests.act_as(v_cashier);
  v := public.answer_availability_request(ph_a, v_id, true, 1500);
  perform tests.eq(v ->> 'answer', 'available', 'cashier answered');
  perform tests.eq((select price from public.pharmacy_products where id = a1), 1000.00, 'cashier answers do not change the list price');
  perform tests.act_as(c1);
  perform tests.eq((public.get_availability_request(v_id) -> 'offers' -> 0 ->> 'price')::numeric, 1500.00, 'the offer shows what was answered');
  perform tests.act_as(v_cashier);
  perform tests.eq(public.count_pharmacy_availability_requests(ph_a), 0, 'cashier can use the inbox counter');

  -- closed / expired requests refuse answers
  perform tests.act_as(c1);
  perform public.close_availability_request(v_id);
  perform tests.act_as(pa);
  perform tests.raises(format('select public.answer_availability_request(%L, %L, false)', ph_a, v_id), 'request_closed', 'closed request');
  perform tests.reset();
  update public.availability_requests set status = 'open', closed_at = null, expires_at = now() - interval '1 minute' where id = v_id;
  perform tests.act_as(pa);
  perform tests.raises(format('select public.answer_availability_request(%L, %L, false)', ph_a, v_id), 'request_closed', 'expired request');

  -- another customer cannot be targeted by someone else's answer
  perform tests.act_as(c2);
  perform tests.raises(format('select public.get_availability_request(%L)', v_id), 'not_found', 'another customer cannot read it');
end
$$;

create function tests.t_req_06_inbox_privacy_and_counters() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  m1 uuid := tests.uid(fx, 'm1');
  m2 uuid := tests.uid(fx, 'm2');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  v1 uuid;
  v2 uuid;
  v_cashier uuid;
begin
  v_cashier := tests.mk_cashier(ph_a, 'cashier2@t.test');
  v1 := (tests.ask(c1, m1, 'inb-key-0001') ->> 'id')::uuid;
  v2 := (tests.ask(c2, m2, 'inb-key-0002') ->> 'id')::uuid;

  perform tests.act_as(pa);
  perform tests.eq(public.count_pharmacy_availability_requests(ph_a), 2, 'two open requests waiting');
  perform tests.eq(tests.count(format('select 1 from public.list_pharmacy_availability_requests(%L)', ph_a)), 2::bigint, 'two inbox rows');
  perform public.answer_availability_request(ph_a, v1, false);
  perform tests.eq(public.count_pharmacy_availability_requests(ph_a), 1, 'answering lowers the counter');
  perform tests.eq((select request_id from public.list_pharmacy_availability_requests(ph_a) limit 1), v2, 'unanswered requests come first');
  perform tests.eq(tests.count(format('select 1 from public.list_pharmacy_availability_requests(%L)', ph_a)), 2::bigint, 'answered ones stay visible while open');
  perform tests.eq((select answer from public.list_pharmacy_availability_requests(ph_a) where request_id = v1), 'unavailable', 'inbox shows my answer');

  -- closing removes the request from the open inbox but history keeps it for a week
  perform tests.act_as(c1);
  perform public.close_availability_request(v1);
  perform tests.act_as(pa);
  perform tests.eq(tests.count(format('select 1 from public.list_pharmacy_availability_requests(%L)', ph_a)), 1::bigint, 'closed request leaves the open inbox');
  perform tests.eq(tests.count(format('select 1 from public.list_pharmacy_availability_requests(%L, false)', ph_a)), 2::bigint, 'history shows it');
  perform tests.eq((select request_status from public.list_pharmacy_availability_requests(ph_a, false) where request_id = v1), 'closed', 'history carries the status');
  perform tests.reset();
  update public.availability_targets set notified_at = now() - interval '8 days' where request_id = v1;
  perform tests.act_as(pa);
  perform tests.eq(tests.count(format('select 1 from public.list_pharmacy_availability_requests(%L, false)', ph_a)), 1::bigint, 'history is limited to a week');

  -- paging and clamping
  perform tests.eq(tests.count(format('select 1 from public.list_pharmacy_availability_requests(%L, true, 1, 0)', ph_a)), 1::bigint, 'limit 1');
  perform tests.eq(tests.count(format('select 1 from public.list_pharmacy_availability_requests(%L, true, 1, 5)', ph_a)), 0::bigint, 'offset past the end');
  perform tests.eq(tests.count(format('select 1 from public.list_pharmacy_availability_requests(%L, true, -3, -3)', ph_a)), 1::bigint, 'negative values are clamped');

  -- every pharmacy member sees it; outsiders do not
  perform tests.act_as(v_cashier);
  perform tests.eq(public.count_pharmacy_availability_requests(ph_a), 1, 'cashier sees the counter');
  perform tests.eq(tests.count(format('select 1 from public.list_pharmacy_availability_requests(%L)', ph_a)), 1::bigint, 'cashier sees the inbox');
  perform tests.act_as(pb);
  perform tests.raises(format('select public.count_pharmacy_availability_requests(%L)', ph_a), 'forbidden', 'other pharmacy: counter');
  perform tests.raises(format('select * from public.list_pharmacy_availability_requests(%L)', ph_a), 'forbidden', 'other pharmacy: inbox');
  perform tests.act_as(c1);
  perform tests.raises(format('select * from public.list_pharmacy_availability_requests(%L)', ph_a), 'forbidden', 'customer: inbox');
  perform tests.raises(format('select public.count_pharmacy_availability_requests(%L)', ph_a), 'forbidden', 'customer: counter');
  perform tests.act_as_anon();
  perform tests.raises(format('select * from public.list_pharmacy_availability_requests(%L)', ph_a), '42501', 'anonymous: inbox');

  -- the dashboard reports the same open count
  perform tests.act_as(pa);
  perform tests.eq((public.pharmacy_dashboard(ph_a) ->> 'open_requests_count')::int, 1, 'dashboard open_requests_count');

  -- a customer reads only their own requests
  perform tests.act_as(c1);
  perform tests.eq(tests.count('select 1 from public.list_my_availability_requests()'), 1::bigint, 'c1 sees only own requests');
  perform tests.eq((select status from public.list_my_availability_requests()), 'closed', 'status in the list');
  perform tests.act_as(c2);
  perform tests.eq(tests.count('select 1 from public.list_my_availability_requests()'), 1::bigint, 'c2 sees only own requests');
  perform tests.eq((select id from public.list_my_availability_requests()), v2, 'and it is theirs');
  perform tests.raises(format('select public.get_availability_request(%L)', v1), 'not_found', 'cannot read another customer''s request');
  perform tests.raises(format('select public.expand_availability_request(%L)', v1), 'not_found', 'cannot expand another customer''s request');
  perform tests.raises(format('select public.close_availability_request(%L)', v1), 'not_found', 'cannot close another customer''s request');
  perform tests.act_as(pa);
  perform tests.eq(tests.count('select 1 from public.list_my_availability_requests()'), 0::bigint, 'a pharmacist has no customer requests of their own');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

-- ---------------------------------------------------------------------------
-- Widening the radius
-- ---------------------------------------------------------------------------
create function tests.t_req_07_expansion_when_everybody_says_unavailable() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  v jsonb;
  v_id uuid;
begin
  perform tests.place_pharmacy(ph_b, 33.5300);            -- 2.1 km away: inside 3 km only
  v := tests.ask(c1, m1, 'exp-key-0001');
  v_id := (v ->> 'id')::uuid;
  perform tests.eq((v ->> 'notified')::int, 1, 'only A is inside 1 km');
  perform tests.eq(tests.notif_count(pb, 'availability_request'), 0::bigint, 'B was not bothered yet');

  -- polling with no answer changes nothing
  perform tests.act_as(c1);
  v := public.get_availability_request(v_id);
  perform tests.eq((v ->> 'step')::int, 1, 'still step 1');

  -- A says "unavailable": the next poll widens to 3 km and asks B
  perform tests.act_as(pa);
  perform public.answer_availability_request(ph_a, v_id, false);
  perform tests.act_as(c1);
  v := public.get_availability_request(v_id);
  perform tests.eq((v ->> 'step')::int, 2, 'widened to step 2');
  perform tests.eq((v ->> 'radius_km')::numeric, 3::numeric, 'radius 3 km');
  perform tests.eq((v ->> 'notified')::int, 2, 'B was added');
  perform tests.eq((v ->> 'answered')::int, 1, 'one answer so far');
  perform tests.eq(tests.notif_count(pb, 'availability_request'), 1::bigint, 'B notified once');
  perform tests.eq(tests.notif_count(pa, 'availability_request'), 1::bigint, 'A is not notified again');
  perform tests.eq(tests.su_text(format('select step from public.availability_targets where request_id = %L and pharmacy_id = %L', v_id, ph_b))::int, 2, 'B is a step-2 target');
  perform tests.ok(tests.su_text(format('select distance_km from public.availability_targets where request_id = %L and pharmacy_id = %L', v_id, ph_b))::numeric between 2.0 and 2.2, 'B distance ~2.1 km');
  perform tests.eq((public.get_availability_request(v_id) ->> 'step')::int, 2, 'polling again does not widen further (B has not answered)');

  -- B says "unavailable" as well: step 3 and 4 add nobody, the request ends up at the largest radius
  perform tests.act_as(pb);
  perform public.answer_availability_request(ph_b, v_id, false);
  perform tests.act_as(c1);
  v := public.get_availability_request(v_id);
  perform tests.eq((v ->> 'step')::int, 4, 'nobody left: widened to the maximum');
  perform tests.eq((v ->> 'radius_km')::numeric, 10::numeric, 'radius 10 km');
  perform tests.eq((v ->> 'radius_exhausted')::boolean, true, 'radius exhausted');
  perform tests.eq((v ->> 'notified')::int, 2, 'still the same two pharmacies');
  perform tests.eq(v ->> 'status', 'open', 'still open until it expires');
  perform tests.eq(jsonb_array_length(v -> 'offers'), 0, 'no offers');
  perform tests.raises(format('select public.expand_availability_request(%L)', v_id), 'invalid_transition', 'cannot go beyond 10 km');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_req_08_expansion_after_three_minutes_of_silence() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  v jsonb;
  v_id uuid;
begin
  perform tests.place_pharmacy(ph_b, 33.5500);            -- 4.4 km away: inside 5 km only
  v := tests.ask(c1, m1, 'sil-key-0001');
  v_id := (v ->> 'id')::uuid;
  perform tests.eq((v ->> 'notified')::int, 1, 'A only');

  -- two minutes of silence is not enough
  perform tests.age_request(v_id, 2);
  perform tests.act_as(c1);
  perform tests.eq((public.get_availability_request(v_id) ->> 'step')::int, 1, 'two minutes: no change');

  -- three minutes: step 2 (3 km, nobody new), a poll does not jump further on its own
  perform tests.age_request(v_id, 4);
  perform tests.act_as(c1);
  v := public.get_availability_request(v_id);
  perform tests.eq((v ->> 'step')::int, 2, 'silence widened the radius by exactly one step');
  perform tests.eq((v ->> 'notified')::int, 1, 'nobody new inside 3 km');
  perform tests.eq((public.get_availability_request(v_id) ->> 'step')::int, 2, 'the wait restarts after each widening');

  -- next silence: step 3 (5 km) reaches B
  perform tests.age_request(v_id, 4);
  perform tests.act_as(c1);
  v := public.get_availability_request(v_id);
  perform tests.eq((v ->> 'step')::int, 3, 'step 3');
  perform tests.eq((v ->> 'notified')::int, 2, 'B is asked at 5 km');
  perform tests.eq(tests.notif_count(tests.uid(fx, 'pb'), 'availability_request'), 1::bigint, 'B notified');

  -- an "available" answer stops the automatic widening for good
  perform tests.act_as(pa);
  perform public.answer_availability_request(ph_a, v_id, true, 1000);
  perform tests.age_request(v_id, 30);
  perform tests.act_as(c1);
  perform tests.eq((public.get_availability_request(v_id) ->> 'step')::int, 3, 'someone is available: no more widening');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_req_09_empty_radius_skips_ahead_and_manual_expand() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  m1 uuid := tests.uid(fx, 'm1');
  m2 uuid := tests.uid(fx, 'm2');
  m3 uuid := tests.uid(fx, 'm3');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  v jsonb;
  v_id uuid;
begin
  -- nobody inside 1 km or 3 km: the server skips straight to the first radius that has a pharmacy
  perform tests.place_pharmacy(ph_a, 33.5500);            -- 4.4 km
  perform tests.place_pharmacy(ph_b, 33.7000);            -- 21 km: never reachable
  v := tests.ask(c1, m1, 'skip-key-0001');
  v_id := (v ->> 'id')::uuid;
  perform tests.eq((v ->> 'step')::int, 3, 'empty radii are skipped');
  perform tests.eq((v ->> 'radius_km')::numeric, 5::numeric, 'radius 5 km');
  perform tests.eq((v ->> 'notified')::int, 1, 'only A is asked');
  perform tests.eq(tests.su_text(format('select step from public.availability_targets where request_id = %L', v_id))::int, 3, 'target remembers the step it was added in');

  -- when no pharmacy exists anywhere in range the request goes to the maximum radius and waits
  v := tests.ask(c2, m1, 'skip-key-0002', 34.5000, 36.2800);
  perform tests.eq((v ->> 'step')::int, 4, 'ran out of radii');
  perform tests.eq((v ->> 'notified')::int, 0, 'no pharmacy anywhere nearby');
  perform tests.eq((v ->> 'radius_exhausted')::boolean, true, 'so the app can say "no pharmacies in range"');

  -- manual "search further"
  perform tests.place_pharmacy(ph_a, 33.5100);
  perform tests.place_pharmacy(ph_b, 33.5300);
  v := tests.ask(c1, m2, 'skip-key-0003');
  v_id := (v ->> 'id')::uuid;
  perform tests.eq((v ->> 'notified')::int, 1, 'A only at first');
  perform tests.act_as(c1);
  v := public.expand_availability_request(v_id);
  perform tests.eq((v ->> 'step')::int, 2, 'manual expansion widens one step');
  perform tests.eq((v ->> 'notified')::int, 2, 'and asks B');
  v := public.expand_availability_request(v_id);
  perform tests.eq((v ->> 'step')::int, 3, 'again');
  v := public.expand_availability_request(v_id);
  perform tests.eq((v ->> 'step')::int, 4, 'and again');
  perform tests.raises(format('select public.expand_availability_request(%L)', v_id), 'invalid_transition', 'beyond the maximum');

  -- an available answer does not forbid the customer from looking further
  v := tests.ask(c1, m3, 'skip-key-0004');
  v_id := (v ->> 'id')::uuid;
  perform tests.act_as(pa);
  perform public.answer_availability_request(ph_a, v_id, true, 1000);
  perform tests.act_as(c1);
  perform tests.eq((public.expand_availability_request(v_id) ->> 'step')::int, 2, 'the customer may still search further');

  -- closed requests cannot be widened
  perform public.close_availability_request(v_id);
  perform tests.raises(format('select public.expand_availability_request(%L)', v_id), 'request_closed', 'closed');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_req_10_target_cap_and_nearest_first() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  i integer;
  v jsonb;
  v_id uuid;
begin
  -- 30 more pharmacies around the customer, 0.1 km apart from each other going north (0.2 .. 3.1 km away)
  perform tests.reset();
  for i in 1..30 loop
    insert into public.pharmacies (owner_id, name, phone, address_line, city, latitude, longitude, approval_status, is_listed)
    values (tests.create_user('extra' || i || '@t.test', 'Extra owner ' || i), 'Extra ' || i, '0944000000', 'Street ' || i, 'Damascus',
            33.5110 + i * 0.001, 36.2800, 'approved', true);
  end loop;
  v := tests.ask(c1, m1, 'capx-key-0001');
  v_id := (v ->> 'id')::uuid;
  -- inside 1 km: A (0.11), B (0.44) and Extra 1..8 (0.11 .. 0.89 km)  → 10, well under the cap
  perform tests.eq((v ->> 'notified')::int, 10, 'ten pharmacies inside 1 km');

  v := public.expand_availability_request(v_id);          -- 3 km: everything up to Extra 27 (3.0 km) → capped at 25
  perform tests.eq((v ->> 'notified')::int, 25, 'never more than 25 pharmacies are asked');
  perform tests.eq(tests.su_count(format('select 1 from public.availability_targets where request_id = %L', v_id)), 25::bigint, 'target rows capped');
  perform tests.eq(tests.su_count(format($q$select 1 from public.availability_targets t join public.pharmacies p on p.id = t.pharmacy_id
                                            where t.request_id = %L and p.name = 'Extra 26'$q$, v_id)), 0::bigint, 'a far pharmacy inside 3 km is left out once the cap is reached');
  perform tests.eq(tests.su_count(format($q$select 1 from public.availability_targets t join public.pharmacies p on p.id = t.pharmacy_id
                                            where t.request_id = %L and p.name = 'Extra 20'$q$, v_id)), 1::bigint, 'nearer ones are kept');
  perform tests.eq(tests.su_count(format('select 1 from public.availability_targets where request_id = %L and pharmacy_id = %L', v_id, ph_a)), 1::bigint, 'the nearest are kept');
  v := public.expand_availability_request(v_id);
  perform tests.eq((v ->> 'notified')::int, 25, 'still capped at larger radii');
  perform tests.eq(tests.su_count(format('select 1 from public.availability_targets where request_id = %L', v_id)), 25::bigint, 'still 25 rows');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

-- ---------------------------------------------------------------------------
-- Expiry, closing, the cron sweeper
-- ---------------------------------------------------------------------------
create function tests.t_req_11_expiry_close_and_sweeper() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  m2 uuid := tests.uid(fx, 'm2');
  m3 uuid := tests.uid(fx, 'm3');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  v jsonb;
  v1 uuid;
  v2 uuid;
  v3 uuid;
  v_old uuid;
begin
  perform tests.place_pharmacy(ph_b, 33.5300);
  v1 := (tests.ask(c1, m1, 'swp-key-0001') ->> 'id')::uuid;
  v2 := (tests.ask(c1, m2, 'swp-key-0002') ->> 'id')::uuid;
  v3 := (tests.ask(c1, m3, 'swp-key-0003') ->> 'id')::uuid;

  -- expiry shows up in reads even before anybody sweeps
  perform tests.reset();
  update public.availability_requests set expires_at = now() - interval '1 second' where id = v1;
  perform tests.act_as(c1);
  v := public.get_availability_request(v1);
  perform tests.eq(v ->> 'status', 'expired', 'past expires_at reads as expired');
  perform tests.eq((v ->> 'seconds_left')::int, 0, 'no time left');
  perform tests.eq(tests.su_text(format('select status from public.availability_requests where id = %L', v1)), 'expired', 'and the row was updated by the read');
  perform tests.eq(public.expand_availability_request(v1) ->> 'status', 'expired', 'expanding an expired request just reports it');
  perform tests.eq((select status from public.list_my_availability_requests() where id = v1), 'expired', 'list shows expired');
  perform tests.act_as(pa);
  perform tests.eq(public.count_pharmacy_availability_requests(ph_a), 2, 'expired requests leave the pharmacy counter');

  -- closing is final and idempotent; it never reopens
  perform tests.act_as(c1);
  v := public.close_availability_request(v2);
  perform tests.eq(v ->> 'status', 'closed', 'closed');
  perform tests.eq(public.close_availability_request(v2) ->> 'status', 'closed', 'closing twice is harmless');
  perform tests.eq(public.get_availability_request(v2) ->> 'status', 'closed', 'polling a closed request keeps it closed');
  perform tests.eq(public.close_availability_request(v1) ->> 'status', 'expired', 'closing an expired request leaves it expired');
  perform tests.eq(tests.su_count(format('select 1 from public.availability_targets where request_id = %L', v2)), 1::bigint, 'closing does not erase the targets (history)');

  -- the cron sweeper expands silent requests and expires old ones without any customer polling
  perform tests.age_request(v3, 4);
  perform tests.reset();
  insert into public.availability_requests (customer_id, medicine_id, latitude, longitude, status, created_at, expires_at, closed_at)
  values (c1, m1, 33.9, 36.9, 'closed', now() - interval '31 days', now() - interval '31 days', now() - interval '31 days')
  returning id into v_old;
  perform tests.ok(private.advance_all_availability_requests() >= 1, 'sweeper touched the open request');
  perform tests.eq((select step from public.availability_requests where id = v3), 2, 'sweeper widened the silent request');
  perform tests.eq(tests.count(format('select 1 from public.availability_requests where id = %L', v_old)), 0::bigint, 'requests older than 30 days are deleted');
  perform tests.eq(tests.count(format('select 1 from public.availability_requests where id = %L', v1)), 1::bigint, 'recent finished requests stay');
  perform tests.reset();
  update public.availability_requests set expires_at = now() - interval '1 minute' where id = v3;
  perform private.advance_all_availability_requests();
  perform tests.eq((select status::text from public.availability_requests where id = v3), 'expired', 'sweeper expires due requests');
  perform tests.eq(private.advance_all_availability_requests(), 0, 'nothing open is left to sweep');
  perform tests.check_invariants();
end
$$;

create function tests.t_req_12_direct_access_is_closed() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  ph_a uuid := tests.uid(fx, 'ph_a');
  v_id uuid;
begin
  v_id := (tests.ask(c1, m1, 'dir-key-0001') ->> 'id')::uuid;

  -- the tables are invisible to every client role: access only through the RPCs
  perform tests.act_as(c1);
  perform tests.raises('select * from public.availability_requests', '42501', 'customer cannot select requests');
  perform tests.raises('select * from public.availability_targets', '42501', 'customer cannot select targets');
  perform tests.raises(format('update public.availability_requests set status = ''closed'' where id = %L', v_id), '42501', 'customer cannot update requests');
  perform tests.raises(format('delete from public.availability_requests where id = %L', v_id), '42501', 'customer cannot delete requests');
  perform tests.act_as(pa);
  perform tests.raises('select * from public.availability_targets', '42501', 'pharmacist cannot select targets');
  perform tests.raises(format('update public.availability_targets set answer = ''available'' where request_id = %L', v_id), '42501', 'pharmacist cannot write answers directly');
  perform tests.raises('insert into public.pharmacy_products (pharmacy_id, medicine_id, price) values (gen_random_uuid(), gen_random_uuid(), 1)', '42501', 'list writes are RPC-only');
  perform tests.act_as_anon();
  perform tests.raises('select * from public.availability_requests', '42501', 'anonymous cannot select requests');
  perform tests.raises('select public.get_availability_request(gen_random_uuid())', '42501', 'anonymous cannot call the RPC');

  -- the private helpers are not callable from the API
  perform tests.act_as(c1);
  perform tests.raises(format('select private.advance_request(%L)', v_id), '42501', 'private.advance_request is not exposed');
  perform tests.raises('select private.advance_all_availability_requests()', '42501', 'sweeper is not exposed');
  perform tests.raises('select * from private.pharmacies_within(33.5, 36.2, 5)', '42501', 'geo helper is not exposed');

  -- the answer shape check: an answer must carry a price iff it is "available"
  perform tests.reset();
  perform tests.raises(format('update public.availability_targets set answer = ''available'', price = null, answered_at = now(), answered_by = %L where request_id = %L and pharmacy_id = %L', pa, v_id, ph_a), '23514', '"available" without a price violates the table check');
  perform tests.raises(format('update public.availability_targets set answer = ''unavailable'', price = 5, answered_at = now(), answered_by = %L where request_id = %L and pharmacy_id = %L', pa, v_id, ph_a), '23514', '"unavailable" with a price violates the table check');

  -- deleting the customer removes their requests (no orphans), deleting a pharmacy is blocked by history
  perform tests.eq(tests.count(format('select 1 from public.availability_targets where request_id = %L', v_id)), 2::bigint, 'targets exist');
  delete from public.availability_requests where id = v_id;
  perform tests.eq(tests.count(format('select 1 from public.availability_targets where request_id = %L', v_id)), 0::bigint, 'targets cascade with the request');
end
$$;
