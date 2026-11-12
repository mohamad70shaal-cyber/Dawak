-- The pharmacy list (no quantities) and point-of-sale tests.

create function tests.t_lst_00_no_quantities_anywhere() returns void
language plpgsql as $$
begin
  perform tests.eq(tests.count($q$
    select 1 from information_schema.columns
    where table_schema = 'public'
      and column_name in ('stock_qty', 'reserved_qty', 'low_stock_threshold', 'last_inventory_update')
  $q$), 0::bigint, 'no quantity column exists');
  perform tests.eq(tests.count($q$
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name in ('inventory_movements', 'stock_reservations')
  $q$), 0::bigint, 'stock tables are gone');
  perform tests.eq(tests.count($q$
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('adjust_stock', 'set_stock', 'confirm_inventory')
  $q$), 0::bigint, 'stock RPCs are gone');
end
$$;

create function tests.t_lst_01_add_product_validation() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  m1 uuid := tests.uid(fx, 'm1');
  m3 uuid := tests.uid(fx, 'm3');
  v_pending uuid;
  v_prod jsonb;
begin
  perform tests.act_as(pa);
  perform tests.raises(format('select public.add_pharmacy_product(%L,%L,-1)', ph, m3), 'invalid_input', 'negative price');
  perform tests.raises(format('select public.add_pharmacy_product(%L,%L,0)', ph, m3), 'invalid_input', 'zero price');
  perform tests.raises(format('select public.add_pharmacy_product(%L,%L,10.001)', ph, m3), 'invalid_input', 'price with 3 decimals');
  perform tests.raises(format('select public.add_pharmacy_product(%L,%L,NULL)', ph, m3), 'invalid_input', 'null price');
  perform tests.raises(format('select public.add_pharmacy_product(%L,%L,10)', ph, m1), 'invalid_input', 'duplicate medicine in same pharmacy');
  perform tests.raises(format('select public.add_pharmacy_product(%L,%L,10)', ph, gen_random_uuid()), 'not_found', 'unknown medicine');

  v_pending := ((public.propose_medicine('دواء مقترح', 'Proposed', 'Prop', 'x', '5mg', 'أقراص', 'علبة 10')) ->> 'id')::uuid;
  perform tests.raises(format('select public.add_pharmacy_product(%L,%L,10)', ph, v_pending), 'not_found', 'pending medicine cannot be listed');

  v_prod := public.add_pharmacy_product(ph, m3, 1500);
  perform tests.eq((v_prod ->> 'is_available')::boolean, true, 'new row is available');
  perform tests.ok((v_prod ->> 'confirmed_at')::timestamptz > now() - interval '1 minute', 'new row is confirmed now');
  perform tests.eq((v_prod ->> 'price')::numeric, 1500::numeric, 'price stored');
  perform tests.reset();
  perform tests.eq(tests.count($q$select 1 from public.audit_logs where action = 'product_added'$q$), 4::bigint, 'additions audited (3 fixtures + this one)');
  perform tests.check_invariants();
end
$$;

create function tests.t_lst_02_update_product_and_roles() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  cashier uuid := tests.mk_cashier(ph, 'cashier@t.test');
  v jsonb;
begin
  update public.pharmacy_products set confirmed_at = now() - interval '20 days' where id = a1;
  perform tests.act_as(pa);
  v := public.update_pharmacy_product(a1, 1200.75, null);
  perform tests.eq((v ->> 'price')::numeric, 1200.75, 'price updated');
  perform tests.eq((v ->> 'is_available')::boolean, true, 'availability untouched by a price edit');
  perform tests.ok((v ->> 'confirmed_at')::timestamptz > now() - interval '1 minute', 'an edit confirms the row');
  v := public.update_pharmacy_product(a1, null, false);
  perform tests.eq((v ->> 'is_available')::boolean, false, 'marked unavailable');
  perform tests.eq((v ->> 'price')::numeric, 1200.75, 'NULL means unchanged');
  perform tests.raises(format('select public.update_pharmacy_product(%L,-5,NULL)', a1), 'invalid_input', 'negative price');
  perform tests.raises(format('select public.update_pharmacy_product(%L,0,NULL)', a1), 'invalid_input', 'zero price');
  perform tests.raises(format('select public.update_pharmacy_product(%L,1.234,NULL)', a1), 'invalid_input', 'three decimals');

  -- cashiers sell but do not manage the list
  perform tests.act_as(cashier);
  perform tests.raises(format('select public.update_pharmacy_product(%L,1,NULL)', a1), 'forbidden', 'cashier cannot edit product');
  perform tests.raises(format('select public.confirm_listing(%L)', ph), 'forbidden', 'cashier cannot confirm the list');
  perform tests.raises(format('select public.add_pharmacy_product(%L,%L,5)', ph, tests.uid(fx, 'm3')), 'forbidden', 'cashier cannot add');

  -- other pharmacy / customers
  perform tests.act_as(pb);
  perform tests.raises(format('select public.update_pharmacy_product(%L,1,NULL)', a1), 'forbidden', 'other pharmacy cannot edit product');
  perform tests.act_as(c1);
  perform tests.raises(format('select public.update_pharmacy_product(%L,1,NULL)', a1), 'forbidden', 'customer cannot edit product');
  perform tests.raises(format('select public.update_pharmacy_product(%L,1,NULL)', gen_random_uuid()), 'not_found', 'unknown product');

  perform tests.reset();
  perform tests.eq(tests.count($q$select 1 from public.audit_logs where action = 'product_updated'$q$), 2::bigint, 'both real changes audited');
  perform tests.check_invariants();
end
$$;

create function tests.t_lst_03_confirm_listing_refreshes_confirmed_at() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  a2 uuid := tests.uid(fx, 'a2');
  b1 uuid := tests.uid(fx, 'b1');
  v jsonb;
begin
  update public.pharmacy_products set confirmed_at = now() - interval '10 days' where id in (a1, a2, b1);
  update public.pharmacy_products set is_available = false where id = a2;
  perform tests.eq(private.listing_freshness(now() - interval '10 days'), 'old', 'ten days is old');
  perform tests.eq(private.listing_freshness(now() - interval '6 days'), 'recent', 'six days is recent');
  perform tests.eq(private.listing_freshness(now()), 'recent', 'now is recent');

  perform tests.act_as(pa);
  v := public.confirm_listing(ph);
  perform tests.eq((v ->> 'confirmed')::int, 1, 'only available rows are confirmed');
  perform tests.reset();
  perform tests.ok((select confirmed_at > now() - interval '1 minute' from public.pharmacy_products where id = a1), 'available row confirmed');
  perform tests.ok((select confirmed_at < now() - interval '9 days' from public.pharmacy_products where id = a2), 'unavailable row not touched');
  perform tests.ok((select confirmed_at < now() - interval '9 days' from public.pharmacy_products where id = b1), 'other pharmacy not touched');
  perform tests.eq(tests.count($q$select 1 from public.audit_logs where action = 'listing_confirmed'$q$), 1::bigint, 'confirmation audited');
end
$$;

create function tests.t_lst_04_bulk_upsert() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  m1 uuid := tests.uid(fx, 'm1');
  m2 uuid := tests.uid(fx, 'm2');
  m3 uuid := tests.uid(fx, 'm3');
  v_pending uuid;
  v jsonb;
  v_items jsonb;
  cashier uuid := tests.mk_cashier(ph, 'cashier@t.test');
begin
  perform tests.act_as(pa);
  v_pending := ((public.propose_medicine('دواء قيد المراجعة', 'Pending drug', null, null, '5mg', 'أقراص', 'علبة', null)) ->> 'id')::uuid;
  -- a1 (m1) and a2 (m2) exist; make m1 unavailable first so the import must revive it.
  perform public.update_pharmacy_product(a1, null, false);

  v_items := jsonb_build_array(
    jsonb_build_object('medicine_id', m1, 'price', 1300),          -- existing, becomes available again with the new price
    jsonb_build_object('medicine_id', m3, 'price', 900.5),         -- new
    jsonb_build_object('medicine_id', m3, 'price', 950),           -- duplicate in the same call: the last one wins
    jsonb_build_object('medicine_id', v_pending, 'price', 10),     -- not an approved catalogue entry: skipped
    jsonb_build_object('medicine_id', m2, 'price', 0),             -- invalid price: skipped
    jsonb_build_object('medicine_id', m2, 'price', 10.123),        -- invalid price: skipped
    jsonb_build_object('medicine_id', gen_random_uuid(), 'price', 10),  -- unknown medicine: skipped
    jsonb_build_object('medicine_id', m2, 'price', null)           -- missing price: skipped
  );
  v := public.bulk_upsert_pharmacy_products(ph, v_items);
  perform tests.eq((v ->> 'inserted')::int, 1, 'one new row (m3)');
  perform tests.eq((v ->> 'updated')::int, 1, 'one existing row (m1)');
  perform tests.eq((v ->> 'skipped')::int, 6, 'six rows skipped (8 rows, 2 valid products, one duplicate collapsed)');

  perform tests.reset();
  perform tests.eq((select price from public.pharmacy_products where pharmacy_id = ph and medicine_id = m3), 950.00, 'last duplicate wins');
  perform tests.eq((select price from public.pharmacy_products where id = a1), 1300.00, 'existing price replaced');
  perform tests.eq((select is_available from public.pharmacy_products where id = a1), true, 'existing row revived');
  perform tests.eq((select price from public.pharmacy_products where pharmacy_id = ph and medicine_id = tests.uid(fx, 'm2')), 2500.50, 'skipped rows changed nothing');
  perform tests.eq(tests.count(format('select 1 from public.pharmacy_products where pharmacy_id = %L and medicine_id = %L', ph, v_pending)), 0::bigint, 'pending medicine not listed');
  perform tests.eq(tests.count($q$select 1 from public.audit_logs where action = 'products_imported'$q$), 1::bigint, 'import audited once');

  -- Re-running the same file is harmless (everything is an update now).
  perform tests.act_as(pa);
  v := public.bulk_upsert_pharmacy_products(ph, jsonb_build_array(jsonb_build_object('medicine_id', m3, 'price', 950)));
  perform tests.eq((v ->> 'inserted')::int, 0, 'nothing inserted twice');
  perform tests.eq((v ->> 'updated')::int, 1, 'counted as an update');

  -- shape and size limits
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, %L::jsonb)', ph, '[]'), 'invalid_input', 'empty import');
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, NULL::jsonb)', ph), 'invalid_input', 'null import');
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, %L::jsonb)', ph, '{"a":1}'), 'invalid_input', 'object instead of array');
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, %L::jsonb)', ph, '[1,2]'), 'invalid_input', 'array of scalars');
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, %L::jsonb)', ph, '[{"medicine_id":"nope","price":5}]'), 'invalid_input', 'malformed uuid');
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, %L::jsonb)', ph,
      (select jsonb_agg(jsonb_build_object('medicine_id', m3, 'price', 5)) from generate_series(1, 501))::text), 'invalid_input', 'more than 500 rows');
  v := public.bulk_upsert_pharmacy_products(ph,
      (select jsonb_agg(jsonb_build_object('medicine_id', m3, 'price', 5)) from generate_series(1, 500)));
  perform tests.eq((v ->> 'updated')::int, 1, '500 rows are accepted (collapse to one)');

  -- roles
  perform tests.act_as(cashier);
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, %L::jsonb)', ph, v_items::text), 'forbidden', 'cashier cannot import');
  perform tests.act_as(pb);
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, %L::jsonb)', ph, v_items::text), 'forbidden', 'other pharmacy cannot import');
  perform tests.act_as(c1);
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, %L::jsonb)', ph, v_items::text), 'forbidden', 'customer cannot import');
  perform tests.check_invariants();
end
$$;

create function tests.t_lst_05_match_medicine_names() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  m1 uuid := tests.uid(fx, 'm1');
  m2 uuid := tests.uid(fx, 'm2');
  v_pending uuid;
  r record;
begin
  perform tests.act_as(pa);
  v_pending := ((public.propose_medicine('بروفين مقترح', 'Brufen Proposed', null, null, '400mg', 'أقراص', 'علبة', null)) ->> 'id')::uuid;

  -- Typical spreadsheet names: Latin with noise, Arabic, partial.
  select * into r from public.match_medicine_names('["PANADOL 500mg TAB"]'::jsonb) where idx = 1 order by score desc limit 1;
  perform tests.eq(r.medicine_id, m1, 'Latin name with noise finds Panadol');
  select * into r from public.match_medicine_names('["أوميبرازول 20"]'::jsonb) where idx = 1 order by score desc limit 1;
  perform tests.eq(r.medicine_id, m2, 'Arabic name finds Omeprazole');
  select * into r from public.match_medicine_names('["omeprazol caps"]'::jsonb) where idx = 1 order by score desc limit 1;
  perform tests.eq(r.medicine_id, m2, 'a misspelt name still finds Omeprazole');

  -- Indexes follow the input order; at most three suggestions per name; nothing for unrelated text.
  perform tests.eq(tests.count($q$select 1 from public.match_medicine_names('["zzzzqqqq", "Panadol"]'::jsonb) where idx = 1$q$), 0::bigint, 'garbage matches nothing');
  perform tests.ok(tests.count($q$select 1 from public.match_medicine_names('["zzzzqqqq", "Panadol"]'::jsonb) where idx = 2$q$) between 1 and 3, 'second name keeps index 2');
  perform tests.eq(tests.count($q$select 1 from public.match_medicine_names('["ab"]'::jsonb)$q$), 0::bigint, 'names under 3 characters are ignored');
  perform tests.eq(tests.count($q$select 1 from public.match_medicine_names('["Brufen Proposed"]'::jsonb)$q$), 0::bigint, 'pending medicines are never suggested');
  perform tests.ok((select max(score) from public.match_medicine_names('["Panadol"]'::jsonb)) > 0.9, 'an exact name scores high');

  -- input rules
  perform tests.raises('select * from public.match_medicine_names(''[]''::jsonb)', 'invalid_input', 'empty list');
  perform tests.raises('select * from public.match_medicine_names(NULL::jsonb)', 'invalid_input', 'null list');
  perform tests.raises('select * from public.match_medicine_names(''{"a":1}''::jsonb)', 'invalid_input', 'object instead of array');
  perform tests.raises('select * from public.match_medicine_names(''[1,2]''::jsonb)', 'invalid_input', 'numbers instead of strings');
  perform tests.raises(format('select * from public.match_medicine_names(%L::jsonb)', (select jsonb_agg('panadol'::text) from generate_series(1, 101))::text), 'invalid_input', 'more than 100 names');
  perform tests.ok(tests.count(format('select 1 from public.match_medicine_names(%L::jsonb)', (select jsonb_agg('panadol'::text) from generate_series(1, 100))::text)) >= 100, '100 names are accepted');

  -- only pharmacists with an approved pharmacy (owner/manager) may use it
  perform tests.act_as(c1);
  perform tests.raises('select * from public.match_medicine_names(''["Panadol"]''::jsonb)', 'forbidden', 'customer cannot');
  perform tests.act_as(pb);
  perform tests.ok(tests.count('select 1 from public.match_medicine_names(''["Panadol"]''::jsonb)') >= 1, 'another approved pharmacist can');
end
$$;

-- ---------------------------------------------------------------------------
-- POS
-- ---------------------------------------------------------------------------
create function tests.t_pos_01_sale_happy_path() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  a2 uuid := tests.uid(fx, 'a2');
  s1 jsonb;
  s2 jsonb;
begin
  perform tests.act_as(pa);
  s1 := public.create_pos_sale(ph, tests.items(a1::text, '2', a2::text, '1'), 0, 'key-0000001');
  perform tests.eq((s1 ->> 'subtotal')::numeric, 4500.50, 'subtotal');
  perform tests.eq((s1 ->> 'total')::numeric, 4500.50, 'total without discount');
  perform tests.eq(s1 ->> 'invoice_no', 'INV-000001', 'first invoice number');
  perform tests.eq(s1 ->> 'currency', 'SYP', 'pharmacy currency copied');
  perform tests.eq(jsonb_array_length(s1 -> 'items'), 2, 'two lines');
  s2 := public.create_pos_sale(ph, tests.items(a1::text, '1'), 0, 'key-0000002');
  perform tests.eq(s2 ->> 'invoice_no', 'INV-000002', 'invoice numbers are sequential');

  perform tests.eq((public.get_sale((s1 ->> 'id')::uuid)) ->> 'invoice_no', 'INV-000001', 'get_sale returns the same sale');
  perform tests.reset();
  perform tests.eq((select count(*) from public.sale_items where sale_id = (s1 ->> 'id')::uuid), 2::bigint, 'one sale item per line');
  perform tests.check_invariants();
end
$$;

create function tests.t_pos_02_sale_is_all_or_nothing() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  b1 uuid := tests.uid(fx, 'b1');
begin
  perform tests.act_as(pa);
  -- the second line belongs to another pharmacy: nothing at all may be recorded
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, tests.items(a1::text, '1', b1::text, '1')::text, 'key-0000003'),
                       'product_unavailable', 'a foreign line aborts the whole sale');
  perform tests.reset();
  perform tests.eq(tests.count('select 1 from public.sales'), 0::bigint, 'no sale persisted');
  perform tests.eq(tests.count('select 1 from public.sale_items'), 0::bigint, 'no sale items persisted');
  perform tests.eq(tests.count('select 1 from public.idempotency_keys'), 0::bigint, 'failed attempt does not burn the key');
  perform tests.eq((select last_number from public.pharmacy_invoice_counters where pharmacy_id = ph), null, 'invoice number not consumed');
  perform tests.check_invariants();
end
$$;

create function tests.t_pos_03_discounts() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  cashier uuid := tests.mk_cashier(ph, 'cashier@t.test');
  s jsonb;
begin
  perform tests.act_as(pa);
  s := public.create_pos_sale(ph, tests.items(a1::text, '2'), 250.50, 'key-0000010');
  perform tests.eq((s ->> 'subtotal')::numeric, 2000.00, 'subtotal');
  perform tests.eq((s ->> 'discount_amount')::numeric, 250.50, 'discount stored');
  perform tests.eq((s ->> 'total')::numeric, 1749.50, 'total = subtotal - discount');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,2000.01,%L)', ph, tests.items(a1::text, '2')::text, 'key-0000011'), 'invalid_input', 'discount above subtotal');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,-1,%L)', ph, tests.items(a1::text, '1')::text, 'key-0000012'), 'invalid_input', 'negative discount');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,1.005,%L)', ph, tests.items(a1::text, '1')::text, 'key-0000013'), 'invalid_input', 'discount with 3 decimals');
  s := public.create_pos_sale(ph, tests.items(a1::text, '1'), 1000, 'key-0000014');
  perform tests.eq((s ->> 'total')::numeric, 0::numeric, 'a full discount gives total 0');

  perform tests.act_as(cashier);
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,10,%L)', ph, tests.items(a1::text, '1')::text, 'key-0000015'), 'forbidden', 'cashier cannot discount');
  s := public.create_pos_sale(ph, tests.items(a1::text, '1'), 0, 'key-0000016');
  perform tests.eq((s ->> 'total')::numeric, 1000::numeric, 'cashier can sell at full price');
  perform tests.reset();
  perform tests.eq(tests.count($q$select 1 from public.audit_logs where action = 'sale_discount'$q$), 2::bigint, 'discounts are audited');
  perform tests.check_invariants();
end
$$;

create function tests.t_pos_04_input_validation() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  b1 uuid := tests.uid(fx, 'b1');
  s jsonb;
begin
  perform tests.act_as(pa);
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, '[]', 'key-0000020'), 'invalid_input', 'empty cart');
  perform tests.raises(format('select public.create_pos_sale(%L,NULL::jsonb,0,%L)', ph, 'key-0000021'), 'invalid_input', 'null cart');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, '{"a":1}', 'key-0000022'), 'invalid_input', 'object instead of array');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, '"abc"', 'key-0000023'), 'invalid_input', 'string instead of array');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, '[1,2]', 'key-0000024'), 'invalid_input', 'array of scalars');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, '[{"product_id":"nope","quantity":1}]', 'key-0000025'), 'invalid_input', 'malformed uuid');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, jsonb_build_array(jsonb_build_object('product_id', a1, 'quantity', 0))::text, 'key-0000026'), 'invalid_input', 'zero quantity');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, jsonb_build_array(jsonb_build_object('product_id', a1, 'quantity', -1))::text, 'key-0000027'), 'invalid_input', 'negative quantity');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, jsonb_build_array(jsonb_build_object('product_id', a1, 'quantity', 1.5))::text, 'key-0000028'), 'invalid_input', 'fractional quantity');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, jsonb_build_array(jsonb_build_object('product_id', a1, 'quantity', 1000))::text, 'key-0000029'), 'invalid_input', 'quantity above POS cap');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, tests.items(a1::text, '1')::text, 'short'), 'invalid_input', 'idempotency key too short');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,NULL)', ph, tests.items(a1::text, '1')::text), 'invalid_input', 'idempotency key required');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, tests.items(b1::text, '1')::text, 'key-0000030'), 'product_unavailable', 'product of another pharmacy');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, tests.items(gen_random_uuid()::text, '1')::text, 'key-0000031'), 'product_unavailable', 'unknown product');

  -- duplicate lines for the same product are merged, and the merged quantity is what gets validated
  s := public.create_pos_sale(ph, jsonb_build_array(jsonb_build_object('product_id', a1, 'quantity', 2), jsonb_build_object('product_id', a1, 'quantity', 3)), 0, 'key-0000032');
  perform tests.eq(jsonb_array_length(s -> 'items'), 1, 'merged into one line');
  perform tests.eq((s -> 'items' -> 0 ->> 'quantity')::int, 5, 'merged quantity');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph,
                              jsonb_build_array(jsonb_build_object('product_id', a1, 'quantity', 600), jsonb_build_object('product_id', a1, 'quantity', 600))::text, 'key-0000033'),
                       'invalid_input', 'merged duplicates are still limited by the per-line cap (999)');

  -- No quantities exist: a product the pharmacy marked "unavailable" can still be sold over the counter.
  perform public.update_pharmacy_product(a1, null, false);
  s := public.create_pos_sale(ph, tests.items(a1::text, '1'), 0, 'key-0000034');
  perform tests.eq((s ->> 'total')::numeric, 1000::numeric, 'unavailable product can be sold (the shelf is the truth)');
  perform tests.check_invariants();
end
$$;

create function tests.t_pos_05_idempotent_retry() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  s1 jsonb;
  s2 jsonb;
begin
  perform tests.act_as(pa);
  s1 := public.create_pos_sale(ph, tests.items(a1::text, '2'), 0, 'retry-key-1');
  s2 := public.create_pos_sale(ph, tests.items(a1::text, '2'), 0, 'retry-key-1');
  perform tests.eq(s2 ->> 'id', s1 ->> 'id', 'retry returns the original sale');
  perform tests.raises(format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, tests.items(a1::text, '3')::text, 'retry-key-1'),
                       'duplicate_request', 'same key with a different request is rejected');
  perform tests.reset();
  perform tests.eq(tests.count('select 1 from public.sales'), 1::bigint, 'exactly one sale');
  perform tests.eq((select total from public.sales limit 1), 2000::numeric, 'recorded once at the right total');
  perform tests.check_invariants();
end
$$;

create function tests.t_pos_06_walk_in_sale_is_independent_of_reservations() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  o jsonb;
begin
  perform tests.act_as(c1);
  o := public.create_order(ph, tests.items(a1::text, '8'), null, null, 'order-key-1');
  perform tests.act_as(pa);
  perform public.accept_order((o ->> 'id')::uuid);
  -- A reservation is a promise to prepare the order, not stock accounting: counter sales are not limited by it.
  perform public.create_pos_sale(ph, tests.items(a1::text, '3'), 0, 'pos-key-0001');
  perform public.create_pos_sale(ph, tests.items(a1::text, '20'), 0, 'pos-key-0002');
  perform tests.reset();
  perform tests.eq((select status::text from public.orders where id = (o ->> 'id')::uuid), 'accepted', 'the reservation is untouched');
  perform tests.eq(tests.count('select 1 from public.sales'), 2::bigint, 'both walk-in sales recorded');
  perform tests.check_invariants();
end
$$;

create function tests.t_pos_07_access_control() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  admin uuid := tests.uid(fx, 'admin');
  ph uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  a1 uuid := tests.uid(fx, 'a1');
  b1 uuid := tests.uid(fx, 'b1');
  s jsonb;
  s_own jsonb;
  v_cashier uuid := tests.mk_cashier(ph, 'cashier@t.test');
  stmt text := format('select public.create_pos_sale(%L,%L::jsonb,0,%L)', ph, tests.items(a1::text, '1')::text, 'access-key-1');
begin
  perform tests.act_as(pb);
  perform tests.raises(stmt, 'forbidden', 'other pharmacy cannot sell from this pharmacy');
  perform tests.act_as(c1);
  perform tests.raises(stmt, 'forbidden', 'customer cannot use POS');
  perform tests.act_as(admin);
  perform tests.raises(stmt, 'forbidden', 'admin is not a pharmacy member');
  perform tests.act_as_anon();
  perform tests.raises(stmt, '42501', 'anonymous cannot call the RPC');

  perform tests.act_as(pa);
  s := public.create_pos_sale(ph, tests.items(a1::text, '1'), 0, 'access-key-2');
  -- sales are readable by the owning pharmacy only
  perform tests.act_as(pb);
  perform tests.raises(format('select public.get_sale(%L)', s ->> 'id'), 'not_found', 'other pharmacy cannot read the receipt');
  perform tests.eq(tests.count('select 1 from public.sales'), 0::bigint, 'RLS hides foreign sales');
  perform tests.eq(tests.count('select 1 from public.sale_items'), 0::bigint, 'RLS hides foreign sale items');
  perform tests.act_as(pa);
  perform tests.eq(tests.count('select 1 from public.sales'), 1::bigint, 'owner sees own sales');
  -- a cashier sees only the sales they rang up themselves
  perform tests.act_as(v_cashier);
  perform tests.raises(format('select public.get_sale(%L)', s ->> 'id'), 'not_found', 'cashier cannot read a colleague receipt');
  perform tests.eq(tests.count('select 1 from public.sales'), 0::bigint, 'cashier RLS: only own sales');
  s_own := public.create_pos_sale(ph, tests.items(a1::text, '1'), 0, 'access-key-4');
  perform tests.eq(public.get_sale((s_own ->> 'id')::uuid) ->> 'invoice_no', 'INV-000002', 'cashier reads own receipt');
  perform tests.eq(tests.count('select 1 from public.sales'), 1::bigint, 'cashier sees own sale');

  -- invoice numbering is per pharmacy
  perform tests.act_as(pb);
  s := public.create_pos_sale(ph_b, tests.items(b1::text, '1'), 0, 'access-key-3');
  perform tests.eq(s ->> 'invoice_no', 'INV-000001', 'pharmacy B starts its own sequence');

  -- clients can never write sales directly
  perform tests.act_as(pa);
  perform tests.raises(format($q$insert into public.sales (pharmacy_id, invoice_no, subtotal, total) values (%L, 'X-1', 1, 1)$q$, ph), '42501', 'no direct sale insert');
  perform tests.raises('update public.pharmacy_products set price = 1', '42501', 'no direct price update');
  perform tests.raises('update public.pharmacy_products set is_available = false', '42501', 'no direct availability update');
  perform tests.check_invariants();
end
$$;

create function tests.t_pos_08_sales_are_immutable_snapshots() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  s jsonb;
  v_sale uuid;
begin
  perform tests.act_as(pa);
  s := public.create_pos_sale(ph, tests.items(a1::text, '2'), 0, 'snap-key-001');
  v_sale := (s ->> 'id')::uuid;
  perform public.update_pharmacy_product(a1, 5000, null);
  perform tests.eq((public.get_sale(v_sale) -> 'items' -> 0 ->> 'unit_price')::numeric, 1000.00, 'receipt keeps the price at time of sale');
  perform tests.reset();
  perform tests.raises(format('update public.sales set total = 1 where id = %L', v_sale), 'append_only', 'sale is append-only');
  perform tests.raises(format('delete from public.sales where id = %L', v_sale), 'append_only', 'sale cannot be deleted');
  perform tests.raises(format('update public.sale_items set quantity = 9 where sale_id = %L', v_sale), 'append_only', 'sale item is append-only');
  perform tests.check_invariants();
end
$$;
