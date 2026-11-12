-- Customer-facing reads (Arabic search, masking, visibility), dashboard figures and search performance.

-- Direct, test-only insert of a historical sale (clients can only create sales "now" through the RPCs).
create function tests.insert_sale(p_pharmacy uuid, p_at timestamptz, p_product uuid, p_qty integer, p_price numeric, p_name text)
returns uuid
language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
  v_no text := 'T-' || substr(v_id::text, 1, 8);
begin
  insert into public.sales (id, pharmacy_id, invoice_no, currency, subtotal, discount_amount, total, cashier_id, created_at)
  values (v_id, p_pharmacy, v_no, 'SYP', p_qty * p_price, 0, p_qty * p_price,
          (select m.user_id from public.pharmacy_members m where m.pharmacy_id = p_pharmacy and m.role = 'owner' limit 1), p_at);
  insert into public.sale_items (sale_id, line_no, product_id, product_name, quantity, unit_price)
  values (v_id, 1, p_product, p_name, p_qty, p_price);
  return v_id;
end
$$;

create function tests.t_pub_01_normalisation() returns void
language plpgsql as $$
begin
  perform tests.eq(private.normalize_search('بَنَادُول'), 'بنادول', 'tashkeel removed');
  perform tests.eq(private.normalize_search('أوميبرازول'), 'اوميبرازول', 'hamza above folded');
  perform tests.eq(private.normalize_search('إيبوبروفين'), 'ايبوبروفين', 'hamza below folded');
  perform tests.eq(private.normalize_search('آسبرين'), 'اسبرين', 'madda folded');
  perform tests.eq(private.normalize_search('كبسولة'), 'كبسوله', 'teh marbuta folded to heh');
  perform tests.eq(private.normalize_search('مستشفى'), 'مستشفي', 'alef maqsura folded to yeh');
  perform tests.eq(private.normalize_search('مؤشر'), 'موشر', 'waw with hamza folded');
  perform tests.eq(private.normalize_search('ـبـنـادول'), 'بنادول', 'tatweel removed');
  perform tests.eq(private.normalize_search('٥٠٠ ملغ'), '500 ملغ', 'Arabic-Indic digits to ASCII');
  perform tests.eq(private.normalize_search('۵۰۰'), '500', 'Persian digits to ASCII');
  perform tests.eq(private.normalize_search('PANADOL   Extra '), 'panadol extra', 'case and whitespace');
  perform tests.eq(private.normalize_search(null), '', 'null is empty');
  perform tests.eq(private.like_escape('50%_\x'), '50\%\_\\x', 'LIKE metacharacters escaped');
end
$$;

create function tests.t_pub_02_search_finds_arabic_and_latin_variants() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  m2 uuid := tests.uid(fx, 'm2');
  m3 uuid := tests.uid(fx, 'm3');
  v_pending uuid;
begin
  perform tests.act_as(c1);
  perform tests.eq((select id from public.search_medicines('بنادول')), m1, 'exact Arabic name');
  perform tests.eq((select id from public.search_medicines('بَنَادُول')), m1, 'with tashkeel');
  perform tests.eq((select id from public.search_medicines('panadol')), m1, 'Latin name');
  perform tests.eq((select id from public.search_medicines('PANADOL')), m1, 'upper case');
  perform tests.eq((select id from public.search_medicines('pana')), m1, 'partial Latin');
  perform tests.eq((select id from public.search_medicines('نادول')), m1, 'substring Arabic');
  perform tests.eq((select id from public.search_medicines('أوميبرازول')), m2, 'hamza spelling');
  perform tests.eq((select id from public.search_medicines('اوميبرازول')), m2, 'bare alef spelling');
  perform tests.eq((select id from public.search_medicines('paracetamol')), m1, 'active ingredient');
  perform tests.eq((select id from public.search_medicines('٥٠٠')), m1, 'Arabic-Indic digits match strength 500mg');
  perform tests.eq((select id from public.search_medicines('فيتامين ج')), m3, 'two tokens');
  perform tests.eq((select id from public.search_medicines('ج فيتامين')), m3, 'token order does not matter');
  perform tests.eq((select id from public.search_medicines('كبسوله')), m2, 'dosage form with teh marbuta folding');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('xyznotthere')$q$), 0::bigint, 'no match is empty');

  -- queries that must not behave like wildcards
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('%%')$q$), 0::bigint, 'percent is literal');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('__')$q$), 0::bigint, 'underscore is literal');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('\\')$q$), 0::bigint, 'backslash is literal');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('a')$q$), 0::bigint, 'one character is too short');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines(NULL)$q$), 0::bigint, 'null query');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('   ')$q$), 0::bigint, 'blank query');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('a'' or ''1''=''1')$q$), 0::bigint, 'quote injection is just text');

  -- filters and paging
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('دول', null, 'أقراص')$q$), 1::bigint, 'dosage-form filter');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('دول', null, 'شراب')$q$), 0::bigint, 'dosage-form filter excludes');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('ا', null, null, 1000)$q$), 0::bigint, 'short query stays empty even with big limit');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('mg', null, null, 1, 0)$q$), 1::bigint, 'limit 1');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('mg', null, null, 1, 99)$q$), 0::bigint, 'offset beyond end');
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('mg', null, null, -5, -5)$q$), 1::bigint, 'negative limit/offset are clamped');

  -- only approved medicines are searchable
  perform tests.reset();
  perform tests.act_as(tests.uid(fx, 'pa'));
  v_pending := ((public.propose_medicine('دواء قيد المراجعة', 'Pending Drug', null, 'x', '5mg', 'أقراص', 'علبة')) ->> 'id')::uuid;
  perform tests.act_as(c1);
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('قيد المراجعة')$q$), 0::bigint, 'pending medicines are hidden');
  perform tests.reset();
  update public.medicines set catalog_status = 'rejected' where id = m3;
  perform tests.act_as(c1);
  perform tests.eq(tests.count($q$select 1 from public.search_medicines('فيتامين')$q$), 0::bigint, 'rejected medicines are hidden');
  perform tests.act_as_anon();
  perform tests.raises($q$select * from public.search_medicines('بنادول')$q$, '42501', 'anonymous cannot search');
end
$$;

create function tests.t_pub_03_search_shows_confirmed_pharmacies() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  a1 uuid := tests.uid(fx, 'a1');
  r record;
begin
  perform tests.act_as(c1);
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L)', m1)), 2::bigint, 'two pharmacies list m1');
  select * into r from public.get_medicine_pharmacies(m1) limit 1;
  perform tests.eq(r.pharmacy_id, ph_a, 'without a location: recent first, then cheapest');
  perform tests.eq(r.price, 1000.00, 'price');
  perform tests.eq(r.currency, 'SYP', 'currency');
  perform tests.eq(r.freshness, 'recent', 'just confirmed is recent');
  perform tests.ok(r.confirmed_at > now() - interval '1 minute', 'confirmed_at is exposed');
  perform tests.ok(r.distance_km is null, 'no distance without a customer location');
  perform tests.ok(r.latitude is not null and r.longitude is not null, 'pharmacy coordinates are exposed for directions');
  perform tests.ok(row_to_json(r)::text !~* 'stock|reserved|quantity|availability', 'no stock-like fields in the public payload');
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L, NULL, NULL, NULL, %L)', m1, 'damascus')), 2::bigint, 'city filter (case-insensitive)');
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L, NULL, NULL, NULL, %L)', m1, 'Aleppo')), 0::bigint, 'city filter excludes');

  -- with a location the nearest pharmacy comes first even though it is dearer
  perform tests.act_as(pa);
  perform public.update_pharmacy_product(a1, 5000, null);
  perform tests.act_as(c1);
  select * into r from public.get_medicine_pharmacies(m1, 33.5110, 36.2800) limit 1;
  perform tests.eq(r.pharmacy_id, ph_a, 'nearest first (A is 0.11 km away)');
  perform tests.ok(r.distance_km between 0.10 and 0.12, 'distance ~0.11 km (was ' || r.distance_km || ')');
  select * into r from public.get_medicine_pharmacies(m1, 33.5140, 36.2800) limit 1;
  perform tests.eq(r.pharmacy_id, ph_b, 'nearest first changes with the location (B is 0.11 km away)');
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L, 33.5110, 36.2800, 0.2)', m1)), 1::bigint, 'radius 0.2 km keeps only A');
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L, 33.5110, 36.2800, 5)', m1)), 2::bigint, 'radius 5 km keeps both');
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L, 33.8000, 36.2800, 5)', m1)), 0::bigint, 'nothing near a far-away customer');
  perform tests.raises(format('select * from public.get_medicine_pharmacies(%L, 33.5110, NULL)', m1), 'invalid_input', 'half a location is refused');
  perform tests.raises(format('select * from public.get_medicine_pharmacies(%L, 95, 36.2800)', m1), 'invalid_input', 'latitude out of range');
  perform tests.raises(format('select * from public.get_medicine_pharmacies(%L, NULL, NULL, 5)', m1), 'invalid_input', 'a radius needs a location');
  perform tests.raises(format('select * from public.get_medicine_pharmacies(%L, 33.5110, 36.2800, 500)', m1), 'invalid_input', 'radius above 50 km');

  -- unavailable rows disappear from results and from the count
  perform tests.act_as(pa);
  perform public.update_pharmacy_product(a1, null, false);
  perform tests.act_as(c1);
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L)', m1)), 1::bigint, 'unavailable row is hidden');
  perform tests.eq((select pharmacy_count from public.search_medicines('بنادول')), 1, 'search counts only available pharmacies');
  perform tests.act_as(pa);
  perform public.update_pharmacy_product(a1, null, true);

  -- freshness: older than 7 days is "old", older than 30 days is not shown at all
  perform tests.reset();
  update public.pharmacy_products set confirmed_at = now() - interval '8 days' where id = a1;
  perform tests.act_as(c1);
  perform tests.eq((select freshness from public.get_medicine_pharmacies(m1) where pharmacy_id = ph_a), 'old', 'older than a week is flagged old');
  select * into r from public.get_medicine_pharmacies(m1) limit 1;
  perform tests.eq(r.pharmacy_id, ph_b, 'without a location recent rows come before old ones');
  perform tests.reset();
  update public.pharmacy_products set confirmed_at = now() - interval '31 days' where id = a1;
  perform tests.act_as(c1);
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L)', m1)), 1::bigint, 'not confirmed for a month: hidden');
  perform tests.eq((select pharmacy_count from public.search_medicines('بنادول')), 1, 'and not counted');

  -- confirming the whole list brings it back
  perform tests.act_as(pa);
  perform public.confirm_listing(ph_a);
  perform tests.act_as(c1);
  perform tests.eq((select freshness from public.get_medicine_pharmacies(m1) where pharmacy_id = ph_a), 'recent', 'confirm_listing refreshes everything');
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L)', m1)), 2::bigint, 'visible again');
end
$$;

create function tests.t_pub_04_only_approved_listed_pharmacies_are_visible() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  c1 uuid := tests.uid(fx, 'c1');
  admin uuid := tests.uid(fx, 'admin');
  m1 uuid := tests.uid(fx, 'm1');
  ph_a uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  v jsonb;
begin
  perform tests.act_as(c1);
  perform tests.eq(tests.count('select 1 from public.list_public_pharmacies()'), 2::bigint, 'two pharmacies in the directory');
  perform tests.eq(tests.count($q$select 1 from public.list_public_pharmacies('pharmacy a')$q$), 1::bigint, 'name search');
  perform tests.eq(tests.count($q$select 1 from public.list_public_pharmacies(NULL, 'aleppo')$q$), 0::bigint, 'city filter');
  v := public.get_public_pharmacy(ph_a);
  perform tests.eq(v ->> 'name', 'Pharmacy A', 'public profile');
  perform tests.ok(v::text !~* 'licen|owner|status_reason|approval', 'no internal fields in public profile');
  perform tests.eq((v ->> 'latitude')::double precision, 33.5100::double precision, 'profile carries the latitude');
  perform tests.eq((v ->> 'longitude')::double precision, 36.2800::double precision, 'profile carries the longitude');
  perform tests.eq((select id from public.list_public_pharmacies(NULL, NULL, 20, 0, 33.5140, 36.2800) limit 1), ph_b, 'directory sorted by distance when located');
  perform tests.ok((select distance_km from public.list_public_pharmacies(NULL, NULL, 20, 0, 33.5140, 36.2800) limit 1) between 0.10 and 0.12, 'directory distance');
  perform tests.eq(tests.count(format('select 1 from public.get_public_pharmacy_products(%L)', ph_a)), 2::bigint, 'pharmacy catalogue');
  perform tests.ok((select bool_and(freshness = 'recent') from public.get_public_pharmacy_products(ph_a)), 'catalogue rows carry freshness');
  perform tests.eq(tests.count(format($q$select 1 from public.get_public_pharmacy_products(%L, 'omeprazole')$q$, ph_a)), 1::bigint, 'catalogue search');

  -- suspension hides a pharmacy everywhere
  perform tests.act_as(admin);
  perform public.admin_review_pharmacy(ph_b, 'suspend', 'مخالفة');
  perform tests.act_as(c1);
  perform tests.eq(tests.count('select 1 from public.list_public_pharmacies()'), 1::bigint, 'suspended pharmacy leaves the directory');
  perform tests.eq(tests.count(format('select 1 from public.get_medicine_pharmacies(%L)', m1)), 1::bigint, 'and the medicine results');
  perform tests.raises(format('select public.get_public_pharmacy(%L)', ph_b), 'not_found', 'profile hidden');
  perform tests.raises(format('select * from public.get_public_pharmacy_products(%L)', ph_b), 'not_found', 'catalogue hidden');

  perform tests.act_as(admin);
  perform public.admin_review_pharmacy(ph_b, 'reinstate', null);
  perform tests.act_as(c1);
  perform tests.eq(tests.count('select 1 from public.list_public_pharmacies()'), 2::bigint, 'reinstated pharmacy is back');

  -- a pharmacy that unlists itself disappears too
  perform tests.reset();
  update public.pharmacies set is_listed = false where id = ph_a;
  perform tests.act_as(c1);
  perform tests.eq(tests.count('select 1 from public.list_public_pharmacies()'), 1::bigint, 'unlisted pharmacy is not in the directory');
  perform tests.raises(format('select public.get_public_pharmacy(%L)', ph_a), 'not_found', 'unlisted profile hidden');

  -- the phone number is shown only when the pharmacy agreed
  perform tests.reset();
  update public.pharmacies set is_listed = true, show_phone_publicly = false where id = ph_a;
  perform tests.act_as(c1);
  perform tests.ok((select phone from public.get_medicine_pharmacies(m1) where pharmacy_id = ph_a) is null, 'hidden phone is null in results');
  perform tests.ok((select phone from public.list_public_pharmacies() where id = ph_a) is null, 'hidden phone is null in directory');
  perform tests.ok(public.get_public_pharmacy(ph_a) ->> 'phone' is null, 'hidden phone is null in profile');
  perform tests.reset();
  update public.pharmacies set show_phone_publicly = true where id = ph_a;
  perform tests.act_as(c1);
  perform tests.eq((select phone from public.list_public_pharmacies() where id = ph_a), '0933111111', 'shown phone');

  perform tests.act_as_anon();
  perform tests.raises('select * from public.list_public_pharmacies()', '42501', 'anonymous cannot list pharmacies');
end
$$;

-- ---------------------------------------------------------------------------
-- Dashboard
-- ---------------------------------------------------------------------------
create function tests.t_dash_01_figures_and_access() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  a2 uuid := tests.uid(fx, 'a2');
  v_cashier uuid := tests.mk_cashier(ph, 'cashier@t.test');
  d jsonb;
  o jsonb;
begin
  perform tests.act_as(pa);
  perform public.create_pos_sale(ph, tests.items(a1::text, '3'), 0, 'dash-key-001');          -- 3000
  perform public.create_pos_sale(ph, tests.items(a1::text, '1', a2::text, '2'), 100, 'dash-key-002'); -- 6001 - 100 = 5901
  d := public.pharmacy_dashboard(ph);
  perform tests.eq((d -> 'today' ->> 'total')::numeric, 8901.00, 'today total (discounts included)');
  perform tests.eq((d -> 'today' ->> 'count')::int, 2, 'today count');
  perform tests.eq((d -> 'week' ->> 'total')::numeric, 8901.00, 'week total');
  perform tests.eq((d -> 'month' ->> 'total')::numeric, 8901.00, 'month total');
  perform tests.eq((d -> 'last_10_days' ->> 'count')::int, 2, 'last 10 days count');
  perform tests.eq(d ->> 'currency', 'SYP', 'currency');
  perform tests.eq(d ->> 'timezone', 'Asia/Damascus', 'timezone');
  perform tests.eq(jsonb_array_length(d -> 'daily_series'), 10, 'ten day series by default');
  perform tests.eq((d -> 'daily_series' -> 9 ->> 'total')::numeric, 8901.00, 'last bucket is today');
  perform tests.eq((d -> 'daily_series' -> 0 ->> 'total')::numeric, 0::numeric, 'empty days are zero, not missing');
  perform tests.eq(d -> 'best_sellers' -> 0 ->> 'product_id', a1::text, 'best seller by quantity');
  perform tests.eq((d -> 'best_sellers' -> 0 ->> 'quantity')::int, 4, 'best seller quantity');
  -- listing summary replaces the low-stock block
  perform tests.eq((d -> 'listing' ->> 'available')::int, 2, 'two available products');
  perform tests.eq((d -> 'listing' ->> 'unavailable')::int, 0, 'none unavailable');
  perform tests.eq((d -> 'listing' ->> 'stale')::int, 0, 'none stale');
  perform tests.ok(not (d ? 'low_stock') and not (d ? 'out_of_stock_count'), 'no stock figures any more');
  perform public.update_pharmacy_product(a2, null, false);
  d := public.pharmacy_dashboard(ph);
  perform tests.eq((d -> 'listing' ->> 'available')::int, 1, 'one available after marking a2 unavailable');
  perform tests.eq((d -> 'listing' ->> 'unavailable')::int, 1, 'one unavailable');
  perform tests.reset();
  update public.pharmacy_products set confirmed_at = now() - interval '8 days' where id = a1;
  perform tests.act_as(pa);
  d := public.pharmacy_dashboard(ph);
  perform tests.eq((d -> 'listing' ->> 'stale')::int, 1, 'a product not confirmed for 8 days is stale');
  perform tests.eq((d ->> 'open_requests_count')::int, 0, 'no open availability requests');

  -- orders that never complete never count as revenue
  o := tests.place_order(c1, ph, tests.items(a1::text, '2'));
  perform tests.act_as(pa);
  d := public.pharmacy_dashboard(ph);
  perform tests.eq((d ->> 'pending_orders_count')::int, 1, 'pending order counted');
  perform tests.eq((d -> 'today' ->> 'total')::numeric, 8901.00, 'pending order is not revenue');
  perform public.reject_order((o ->> 'id')::uuid, 'غير متوفر');
  o := tests.place_order(c1, ph, tests.items(a1::text, '2'));
  perform tests.act_as(pa);
  perform public.accept_order((o ->> 'id')::uuid);
  perform tests.act_as(c1);
  perform public.cancel_order((o ->> 'id')::uuid, null);
  perform tests.act_as(pa);
  d := public.pharmacy_dashboard(ph);
  perform tests.eq((d -> 'today' ->> 'total')::numeric, 8901.00, 'rejected / cancelled orders are not revenue');
  perform tests.eq((d ->> 'pending_orders_count')::int, 0, 'nothing pending');
  perform tests.eq(jsonb_array_length(d -> 'recent_orders'), 2, 'recent orders listed');

  -- explicit ranges
  perform tests.eq((public.pharmacy_dashboard(ph, current_date - 3, current_date) -> 'range' ->> 'count')::int, 2, 'explicit range');
  perform tests.eq(jsonb_array_length(public.pharmacy_dashboard(ph, current_date - 3, current_date) -> 'daily_series'), 4, 'series length follows range');
  perform tests.raises(format('select public.pharmacy_dashboard(%L, %L, %L)', ph, current_date, current_date - 1), 'invalid_input', 'from after to');
  perform tests.raises(format('select public.pharmacy_dashboard(%L, %L, %L)', ph, current_date - 400, current_date), 'invalid_input', 'range above one year');

  -- only owners/managers see money
  perform tests.act_as(v_cashier);
  perform tests.raises(format('select public.pharmacy_dashboard(%L)', ph), 'forbidden', 'cashier cannot see the dashboard');
  perform tests.act_as(pb);
  perform tests.raises(format('select public.pharmacy_dashboard(%L)', ph), 'forbidden', 'other pharmacy');
  perform tests.act_as(c1);
  perform tests.raises(format('select public.pharmacy_dashboard(%L)', ph), 'forbidden', 'customer');
  perform tests.act_as_anon();
  perform tests.raises(format('select public.pharmacy_dashboard(%L)', ph), '42501', 'anonymous');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_dash_02_day_boundaries_use_the_pharmacy_timezone() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  d jsonb;
begin
  -- 21:30 UTC on 9 March 2026 is 00:30 on 10 March in Damascus (UTC+3)
  perform tests.insert_sale(ph, timestamptz '2026-03-09 21:30:00+00', a1, 1, 1000, 'بنادول');
  -- 20:59 UTC is still 9 March in Damascus
  perform tests.insert_sale(ph, timestamptz '2026-03-09 20:59:00+00', a1, 2, 1000, 'بنادول');
  perform tests.act_as(pa);
  d := public.pharmacy_dashboard(ph, date '2026-03-10', date '2026-03-10');
  perform tests.eq((d -> 'range' ->> 'total')::numeric, 1000.00, '10 March contains only the 00:30 local sale');
  d := public.pharmacy_dashboard(ph, date '2026-03-09', date '2026-03-09');
  perform tests.eq((d -> 'range' ->> 'total')::numeric, 2000.00, '9 March contains the 23:59 local sale');
  d := public.pharmacy_dashboard(ph, date '2026-03-09', date '2026-03-10');
  perform tests.eq(d -> 'daily_series' -> 0 ->> 'day', '2026-03-09', 'series day 1');
  perform tests.eq((d -> 'daily_series' -> 0 ->> 'count')::int, 1, 'bucketed by local day (9th)');
  perform tests.eq((d -> 'daily_series' -> 1 ->> 'count')::int, 1, 'bucketed by local day (10th)');
  perform tests.eq((d -> 'range' ->> 'total')::numeric, 3000.00, 'whole range');
  perform tests.eq((d -> 'best_sellers' -> 0 ->> 'quantity')::int, 3, 'best sellers use the same boundaries');
end
$$;

create function tests.t_dash_03_week_starts_on_saturday_and_month_boundaries() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  v_today date := (now() at time zone 'Asia/Damascus')::date;
  v_week_start date := v_today - ((extract(dow from v_today)::integer + 1) % 7);
  v_month_start date := date_trunc('month', v_today)::date;
  d jsonb;
begin
  perform tests.ok(extract(dow from v_week_start) = 6, 'computed week start is a Saturday');
  -- one minute before the week starts / one minute after
  perform tests.insert_sale(ph, private.local_day_start(v_week_start, 'Asia/Damascus') - interval '1 minute', a1, 1, 100, 'قبل الأسبوع');
  perform tests.insert_sale(ph, private.local_day_start(v_week_start, 'Asia/Damascus') + interval '1 minute', a1, 1, 10, 'بداية الأسبوع');
  perform tests.act_as(pa);
  d := public.pharmacy_dashboard(ph);
  perform tests.eq((d -> 'week' ->> 'total')::numeric, 10.00, 'week total excludes the previous Friday night');
  perform tests.eq((d -> 'last_10_days' ->> 'total')::numeric, 110.00, 'last 10 days includes both');

  perform tests.reset();
  perform tests.insert_sale(ph, private.local_day_start(v_month_start, 'Asia/Damascus') - interval '1 minute', a1, 1, 1000, 'الشهر السابق');
  perform tests.act_as(pa);
  d := public.pharmacy_dashboard(ph);
  perform tests.ok((d -> 'month' ->> 'total')::numeric <= 110.00, 'month total excludes last month''s final minute');
  d := public.pharmacy_dashboard(ph, v_today - 40, v_today);
  perform tests.ok((d -> 'range' ->> 'total')::numeric >= 1110.00, 'a range reaching back includes it');
end
$$;

-- ---------------------------------------------------------------------------
-- Performance: trigram index must serve substring search on a realistic catalogue
-- ---------------------------------------------------------------------------
create function tests.t_perf_01_search_uses_trigram_index_at_30k_rows() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  c1 uuid := tests.uid(fx, 'c1');
  r record;
  v_plan text := '';
  v_t0 timestamptz;
  v_ms numeric;
  v_n bigint;
begin
  insert into public.medicines (name_ar, name_en, brand_name, active_ingredient, strength, dosage_form, package_description, catalog_status)
  select 'دواء ' || md5(g::text), 'Drug ' || md5((g * 7)::text), 'Brand' || g, 'ingredient' || (g % 500),
         ((g % 20) * 25 + 25)::text || 'mg', 'أقراص', 'علبة ' || g, 'approved'
  from generate_series(1, 30000) g;
  analyze public.medicines;
  perform tests.ok((select count(*) from public.medicines) >= 30000, 'catalogue populated');

  for r in execute $e$explain select id from public.medicines where search_text like '%d41d8c%'$e$ loop
    v_plan := v_plan || r."QUERY PLAN" || E'\n';
  end loop;
  perform tests.ok(v_plan like '%medicines_search_trgm%', 'trigram index is used for substring search; plan was: ' || v_plan);

  perform tests.act_as(c1);
  v_t0 := clock_timestamp();
  select count(*) into v_n from public.search_medicines('d41d8c');
  v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
  raise notice 'search_medicines(rare token) over 30k rows: % ms, % rows', round(v_ms, 1), v_n;
  perform tests.ok(v_ms < 1000, 'rare-token search under 1s (was ' || round(v_ms, 1) || ' ms)');

  v_t0 := clock_timestamp();
  select count(*) into v_n from public.search_medicines('mg');
  v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
  raise notice 'search_medicines(common token "mg") over 30k rows: % ms, % rows', round(v_ms, 1), v_n;
  perform tests.eq(v_n, 20::bigint, 'common token is capped by the default page size');
  perform tests.ok(v_ms < 2000, 'common-token search under 2s (was ' || round(v_ms, 1) || ' ms)');
end
$$;
