-- Security and authorization tests (permitted AND forbidden access).

-- ---------------------------------------------------------------------------
create function tests.t_sec_01_rls_enabled_and_grants_minimal() returns void
language plpgsql as $$
declare
  r record;
begin
  perform tests.ok(tests.count($q$
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
  $q$) = 0, 'every public table has RLS enabled');

  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r'
  loop
    perform tests.ok(not has_table_privilege('anon', 'public.' || r.relname, 'select,insert,update,delete'),
                     'anon has no privilege on ' || r.relname);
    perform tests.ok(not has_table_privilege('authenticated', 'public.' || r.relname, 'delete'),
                     'authenticated cannot delete from ' || r.relname);
  end loop;

  -- No client write grants on trusted tables.
  for r in select unnest(array['pharmacies', 'pharmacy_members', 'pharmacy_products',
                               'orders', 'order_items', 'sales', 'sale_items',
                               'audit_logs', 'idempotency_keys', 'pharmacy_invoice_counters',
                               'availability_requests', 'availability_targets']) as t
  loop
    perform tests.ok(not has_table_privilege('authenticated', 'public.' || r.t, 'insert,update'),
                     'authenticated cannot write ' || r.t);
  end loop;

  perform tests.ok(not has_table_privilege('authenticated', 'public.idempotency_keys', 'select'), 'idempotency keys hidden');
  perform tests.ok(not has_table_privilege('authenticated', 'public.pharmacy_invoice_counters', 'select'), 'counters hidden');
  perform tests.ok(not has_table_privilege('authenticated', 'public.availability_requests', 'select'), 'availability requests hidden');
  perform tests.ok(not has_table_privilege('authenticated', 'public.availability_targets', 'select'), 'availability targets hidden');

  -- Every public function is callable by signed-in users only.
  perform tests.ok(tests.count($q$
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')
  $q$) = 0, 'anon cannot execute any public function');
  -- private helpers are not directly executable by clients (except the three used by policies).
  perform tests.ok(not has_function_privilege('authenticated', 'private.advance_request(uuid)', 'execute'),
                   'advance_request is internal');
  perform tests.ok(not has_function_privilege('authenticated', 'private.add_request_targets(uuid,integer)', 'execute'),
                   'add_request_targets is internal');
  perform tests.ok(not has_function_privilege('authenticated', 'private.advance_all_availability_requests()', 'execute'),
                   'availability sweeper is internal');
  perform tests.ok(not has_function_privilege('authenticated', 'private.expire_all_reservations()', 'execute'),
                   'global expiry is internal');
end
$$;

-- ---------------------------------------------------------------------------
create function tests.t_sec_02_signup_always_creates_customer() returns void
language plpgsql as $$
declare
  v uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v, 'evil@t.test', '{"display_name":"Evil","role":"admin","account_status":"suspended","phone":"abc"}'::jsonb);
  perform tests.eq((select role::text from public.profiles where id = v), 'customer', 'role forced to customer');
  perform tests.eq((select account_status::text from public.profiles where id = v), 'active', 'status active');
  perform tests.ok((select phone from public.profiles where id = v) is null, 'invalid phone dropped');
  perform tests.eq((select display_name from public.profiles where id = v), 'Evil', 'display name kept');
end
$$;

create function tests.t_sec_03_client_cannot_escalate_profile() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  c1 uuid := tests.uid(fx, 'c1');
begin
  perform tests.act_as(c1);
  perform tests.raises(format('update public.profiles set role = %L where id = %L', 'admin', c1), '42501', 'cannot set role');
  perform tests.raises(format('update public.profiles set account_status = %L where id = %L', 'suspended', c1), '42501', 'cannot set status');
  perform tests.raises(format('update public.profiles set suspended_reason = %L where id = %L', 'x', c1), '42501', 'cannot set reason');
  perform tests.raises('insert into public.profiles (id, role) values (gen_random_uuid(), ''admin'')', '42501', 'cannot insert profile');
  execute format('update public.profiles set display_name = %L, phone = %L where id = %L', 'New Name', '0955123456', c1);
  perform tests.eq((select display_name from public.profiles where id = c1), 'New Name', 'own name editable');
  perform tests.raises(format('update public.profiles set phone = %L where id = %L', 'not a phone', c1), '23514', 'phone validated');
  -- Cannot touch someone else's profile (RLS hides it: 0 rows updated).
  execute format('update public.profiles set display_name = %L where id = %L', 'Hacked', tests.uid(fx, 'c2'));
  perform tests.reset();
  perform tests.eq((select display_name from public.profiles where id = tests.uid(fx, 'c2')), 'Customer Two', 'other profile untouched');
  -- Defence in depth: even the trigger rejects client-role changes if a grant ever slipped through.
  perform tests.act_as(c1);
  perform tests.raises(format('update public.profiles set role = %L where id = %L', 'pharmacist', c1), '42501', 'still denied');
end
$$;

-- ---------------------------------------------------------------------------
create function tests.t_sec_04_new_pharmacy_is_pending_unlisted_and_unprivileged() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  v_new uuid := tests.create_user('pn@t.test', 'New Pharm');
  v_other uuid := tests.create_user('po@t.test', 'Other');
  v jsonb;
  v_id uuid;
begin
  perform tests.act_as(v_new);
  v := public.register_pharmacy('New Pharmacy', '0944222222', 'Street 9', 'Kafr Sousa', 'Damascus', 'near the park',
                                '{}'::jsonb, 'USD', v_new::text || '/lic.png', 33.5, 36.28);
  v_id := (v ->> 'id')::uuid;
  perform tests.eq(v ->> 'latitude', '33.5', 'location stored');
  perform tests.eq(v ->> 'approval_status', 'pending', 'starts pending');
  perform tests.eq(v ->> 'is_listed', 'false', 'starts unlisted');
  perform tests.eq(v ->> 'currency', 'USD', 'currency as chosen');

  perform tests.reset();
  perform tests.eq((select role::text from public.profiles where id = v_new), 'pharmacist', 'promoted to pharmacist role');

  -- Not publicly visible.
  perform tests.act_as(tests.uid(fx, 'c1'));
  perform tests.eq(tests.count('select 1 from public.list_public_pharmacies() where name = ''New Pharmacy'''), '0', 'not in public list');
  perform tests.raises(format('select public.get_public_pharmacy(%L)', v_id), 'not_found', 'not publicly readable');
  perform tests.eq(tests.count(format('select 1 from public.pharmacies where id = %L', v_id)), '0', 'customer cannot read pharmacies table');

  -- The pharmacist cannot grant themselves anything.
  perform tests.act_as(v_new);
  perform tests.raises(format('select public.admin_review_pharmacy(%L, %L, null)', v_id, 'approve'), 'forbidden', 'cannot self-approve');
  perform tests.raises(format('update public.pharmacies set approval_status = %L, is_listed = true where id = %L', 'approved', v_id), '42501', 'no direct update');
  perform tests.raises(format('insert into public.pharmacy_members (pharmacy_id, user_id, role) values (%L, %L, %L)', tests.uid(fx, 'ph_a'), v_new, 'owner'), '42501', 'no direct membership');
  perform tests.raises(format('select public.add_pharmacy_product(%L, %L, 10)', v_id, tests.uid(fx, 'm1')), 'pharmacy_not_active', 'pending pharmacy cannot operate');
  perform tests.raises(format('select public.register_pharmacy(%L, %L, %L, %L, %L, null, %L::jsonb, %L, %L, 33.5, 36.28)',
                              'Again', '0944222222', 'Street', 'x', 'Damascus', '{}', 'SYP', v_new::text || '/l.pdf'), 'invalid_input', 'one pharmacy per owner');

  -- Licence path must live in the caller's own folder.
  perform tests.act_as(v_other);
  perform tests.raises(format('select public.register_pharmacy(%L, %L, %L, %L, %L, null, %L::jsonb, %L, %L, 33.5, 36.28)',
                              'Sneaky', '0944333333', 'Street', 'x', 'Damascus', '{}', 'SYP', v_new::text || '/lic.png'), 'invalid_input', 'licence path must be own folder');
  perform tests.raises(format('select public.register_pharmacy(%L, %L, %L, %L, %L, null, %L::jsonb, %L, %L, 33.5, 36.28)',
                              'Sneaky', '0944333333', 'Street', 'x', 'Damascus', '{}', 'EUR', v_other::text || '/lic.png'), 'invalid_input', 'currency validated');
  perform tests.raises(format('select public.register_pharmacy(%L, %L, %L, %L, %L, null, %L::jsonb, %L, %L, 33.5, 36.28)',
                              'Sneaky', 'abc', 'Street', 'x', 'Damascus', '{}', 'SYP', v_other::text || '/lic.png'), 'invalid_input', 'phone validated');
  -- The shop location is mandatory and must be a real coordinate pair.
  perform tests.raises(format('select public.register_pharmacy(%L, %L, %L, %L, %L, null, %L::jsonb, %L, %L, null, null)',
                              'Sneaky', '0944333333', 'Street', 'x', 'Damascus', '{}', 'SYP', v_other::text || '/lic.png'), 'invalid_input', 'location required');
  perform tests.raises(format('select public.register_pharmacy(%L, %L, %L, %L, %L, null, %L::jsonb, %L, %L, 91, 36.28)',
                              'Sneaky', '0944333333', 'Street', 'x', 'Damascus', '{}', 'SYP', v_other::text || '/lic.png'), 'invalid_input', 'latitude range');
  perform tests.raises(format('select public.register_pharmacy(%L, %L, %L, %L, %L, null, %L::jsonb, %L, %L, 33.5, 181)',
                              'Sneaky', '0944333333', 'Street', 'x', 'Damascus', '{}', 'SYP', v_other::text || '/lic.png'), 'invalid_input', 'longitude range');
  perform tests.raises(format('select public.register_pharmacy(%L, %L, %L, %L, %L, null, %L::jsonb, %L, %L, 0, 0)',
                              'Sneaky', '0944333333', 'Street', 'x', 'Damascus', '{}', 'SYP', v_other::text || '/lic.png'), 'invalid_input', 'null island rejected');
end
$$;

create function tests.t_sec_05_admin_review_flow_controls_public_listing() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  v_new uuid := tests.create_user('pn@t.test', 'New Pharm');
  v_id uuid;
  v jsonb;
begin
  perform tests.act_as(v_new);
  v_id := ((public.register_pharmacy('Flow Pharmacy', '0944222222', 'Street 9', 'Kafr Sousa', 'Damascus', null,
                                     '{}'::jsonb, 'SYP', v_new::text || '/lic.png', 33.52, 36.3)) ->> 'id')::uuid;

  perform tests.act_as(tests.uid(fx, 'admin'));
  perform tests.eq(tests.count(format('select 1 from public.pharmacies where id = %L', v_id)), '1', 'admin sees application');
  perform tests.raises(format('select public.admin_review_pharmacy(%L, %L, null)', v_id, 'reject'), 'invalid_input', 'reject needs reason');
  perform tests.raises(format('select public.admin_review_pharmacy(%L, %L, null)', v_id, 'suspend'), 'invalid_transition', 'cannot suspend a pending one');
  perform tests.raises(format('select public.admin_review_pharmacy(%L, %L, null)', v_id, 'bogus'), 'invalid_input', 'unknown decision');
  v := public.admin_review_pharmacy(v_id, 'reject', 'Licence unreadable');
  perform tests.eq(v ->> 'approval_status', 'rejected', 'rejected');
  perform tests.eq(v ->> 'status_reason', 'Licence unreadable', 'reason stored');
  perform tests.raises(format('select public.admin_review_pharmacy(%L, %L, null)', v_id, 'approve'), 'invalid_transition', 'rejected cannot be approved directly');

  -- Pharmacist sees reason and resubmits.
  perform tests.act_as(v_new);
  perform tests.eq((select status_reason from public.pharmacies where id = v_id), 'Licence unreadable', 'owner sees reason');
  perform tests.raises(format('select public.update_my_pharmacy(%L, %L)', v_id, 'Renamed'), 'pharmacy_not_active', 'cannot edit while rejected');
  v := public.resubmit_pharmacy(v_id, 'Flow Pharmacy', '0944222222', 'Street 9', 'Kafr Sousa', 'Damascus', null, '{}'::jsonb, v_new::text || '/lic2.png');
  perform tests.eq(v ->> 'approval_status', 'pending', 'back to pending');
  perform tests.ok(v ->> 'status_reason' is null, 'reason cleared');
  perform tests.raises(format('select public.resubmit_pharmacy(%L, %L, %L, %L, %L, %L, null, %L::jsonb)', v_id, 'x', '0944222222', 'Street 9', 'k', 'Damascus', '{}'), 'invalid_transition', 'only rejected can resubmit');

  -- Approve: becomes public.
  perform tests.act_as(tests.uid(fx, 'admin'));
  perform public.admin_review_pharmacy(v_id, 'approve', null);
  perform tests.act_as(tests.uid(fx, 'c1'));
  perform tests.eq(tests.count('select 1 from public.list_public_pharmacies() where name = ''Flow Pharmacy'''), '1', 'listed after approval');

  -- Suspend: disappears and cannot operate.
  perform tests.act_as(tests.uid(fx, 'admin'));
  perform public.admin_review_pharmacy(v_id, 'suspend', 'Complaint under review');
  perform tests.act_as(tests.uid(fx, 'c1'));
  perform tests.eq(tests.count('select 1 from public.list_public_pharmacies() where name = ''Flow Pharmacy'''), '0', 'hidden after suspension');
  perform tests.raises(format('select public.get_public_pharmacy(%L)', v_id), 'not_found', 'suspended pharmacy not readable');
  perform tests.act_as(v_new);
  perform tests.raises(format('select public.update_my_pharmacy(%L, %L)', v_id, 'Renamed'), 'pharmacy_not_active', 'suspended cannot edit');

  -- Reinstate.
  perform tests.act_as(tests.uid(fx, 'admin'));
  perform public.admin_review_pharmacy(v_id, 'reinstate', null);
  perform tests.act_as(tests.uid(fx, 'c1'));
  perform tests.eq(tests.count('select 1 from public.list_public_pharmacies() where name = ''Flow Pharmacy'''), '1', 'listed again');

  -- Currency is immutable after approval even for a trusted caller.
  perform tests.reset();
  perform tests.raises(format('update public.pharmacies set currency = %L where id = %L', 'USD', v_id), 'invalid_input', 'currency locked');
end
$$;

-- ---------------------------------------------------------------------------
create function tests.t_sec_06_pharmacy_data_is_isolated() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  v_order uuid;
  v_order_b uuid;
begin
  -- An order and a sale in each pharmacy.
  perform tests.act_as(tests.uid(fx, 'c1'));
  v_order_b := ((public.create_order(tests.uid(fx, 'ph_b'),
      jsonb_build_array(jsonb_build_object('product_id', tests.uid(fx, 'b1'), 'quantity', 1)), null, null, 'key-b-0001-aaaa')) ->> 'id')::uuid;
  perform tests.act_as(pb);
  perform public.create_pos_sale(tests.uid(fx, 'ph_b'),
      jsonb_build_array(jsonb_build_object('product_id', tests.uid(fx, 'b1'), 'quantity', 1)), 0, 'pos-b-0001-aaaa');
  perform public.update_pharmacy_product(tests.uid(fx, 'b1'), 1150, true);

  -- Pharmacist A sees none of it.
  perform tests.act_as(pa);
  perform tests.eq(tests.count('select 1 from public.pharmacy_products'), '2', 'A sees only its 2 products');
  perform tests.eq(tests.count(format('select 1 from public.pharmacy_products where pharmacy_id = %L', tests.uid(fx, 'ph_b'))), '0', 'B products hidden');
  perform tests.eq(tests.count('select 1 from public.sales'), '0', 'B sales hidden');
  perform tests.eq(tests.count(format('select 1 from public.orders where id = %L', v_order_b)), '0', 'B orders hidden');
  perform tests.eq(tests.count(format('select 1 from public.order_items where order_id = %L', v_order_b)), '0', 'B order items hidden');
  perform tests.eq(tests.count('select 1 from public.pharmacies'), '1', 'A sees only its own pharmacy row');
  perform tests.eq(tests.count('select 1 from public.pharmacy_members'), '1', 'A sees only its own membership');

  -- ...and cannot act on it.
  perform tests.raises(format('select public.update_pharmacy_product(%L, null, false)', tests.uid(fx, 'b1')), 'forbidden', 'cannot hide B product');
  perform tests.raises(format('select public.update_pharmacy_product(%L, 1)', tests.uid(fx, 'b1')), 'forbidden', 'cannot reprice B product');
  perform tests.raises(format('select public.bulk_upsert_pharmacy_products(%L, %L::jsonb)', tests.uid(fx, 'ph_b'),
      jsonb_build_array(jsonb_build_object('medicine_id', tests.uid(fx, 'm3'), 'price', 5))::text), 'forbidden', 'cannot import into B');
  perform tests.raises(format('select public.create_pos_sale(%L, %L::jsonb, 0, %L)', tests.uid(fx, 'ph_b'),
      jsonb_build_array(jsonb_build_object('product_id', tests.uid(fx, 'b1'), 'quantity', 1))::text, 'pos-x-0001-aaaa'), 'forbidden', 'cannot sell at B');
  perform tests.raises(format('select public.add_pharmacy_product(%L, %L, 5)', tests.uid(fx, 'ph_b'), tests.uid(fx, 'm3')), 'forbidden', 'cannot list at B');
  perform tests.raises(format('select public.accept_order(%L)', v_order_b), 'forbidden', 'cannot accept B order');
  perform tests.raises(format('select public.reject_order(%L, %L)', v_order_b, 'nope nope'), 'forbidden', 'cannot reject B order');
  perform tests.raises(format('select public.complete_order(%L, %L)', v_order_b, 'DWK-0000000000'), 'forbidden', 'cannot complete B order');
  perform tests.raises(format('select public.pharmacy_dashboard(%L)', tests.uid(fx, 'ph_b')), 'forbidden', 'cannot read B dashboard');
  perform tests.raises(format('select public.find_order_by_ref(%L, %L)', tests.uid(fx, 'ph_b'), 'DWK-0000000000'), 'forbidden', 'cannot look up B orders');
  perform tests.raises(format('select public.confirm_listing(%L)', tests.uid(fx, 'ph_b')), 'forbidden', 'cannot confirm B list');
  perform tests.raises(format('select public.count_pharmacy_availability_requests(%L)', tests.uid(fx, 'ph_b')), 'forbidden', 'cannot count B requests');
  perform tests.raises(format('select * from public.list_pharmacy_availability_requests(%L)', tests.uid(fx, 'ph_b')), 'forbidden', 'cannot read B request inbox');
  perform tests.raises(format('select public.answer_availability_request(%L, %L, false)', tests.uid(fx, 'ph_b'), gen_random_uuid()), 'forbidden', 'cannot answer for B');
  perform tests.raises(format('select public.update_my_pharmacy(%L, %L)', tests.uid(fx, 'ph_b'), 'Pwned'), 'forbidden', 'cannot edit B pharmacy');
  perform tests.raises(format('select public.get_sale(%L)', (select s.id from public.sales s limit 1)), 'not_found', 'no sale visible');
  perform tests.raises(format('update public.pharmacy_products set price = 1 where id = %L', tests.uid(fx, 'a1')), '42501', 'no direct write even on own');
  perform tests.raises(format('delete from public.pharmacy_products where id = %L', tests.uid(fx, 'a1')), '42501', 'no delete');
end
$$;

create function tests.t_sec_07_customers_cannot_see_or_touch_others() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  v_order uuid;
begin
  perform tests.act_as(c1);
  v_order := ((public.create_order(tests.uid(fx, 'ph_a'),
      jsonb_build_array(jsonb_build_object('product_id', tests.uid(fx, 'a1'), 'quantity', 2)), 'please hurry', '0955123456', 'key-c1-0001-aaaa')) ->> 'id')::uuid;
  perform tests.eq(tests.count('select 1 from public.orders'), '1', 'c1 sees own order');
  perform tests.eq(tests.count('select 1 from public.order_items'), '1', 'c1 sees own items');

  perform tests.act_as(c2);
  perform tests.eq(tests.count('select 1 from public.orders'), '0', 'c2 sees no orders');
  perform tests.eq(tests.count('select 1 from public.order_items'), '0', 'c2 sees no items');
  perform tests.raises(format('select public.cancel_order(%L)', v_order), 'not_found', 'c2 cannot cancel c1 order');
  perform tests.raises(format('update public.orders set status = %L where id = %L', 'cancelled', v_order), '42501', 'no direct order update');
  perform tests.raises(format('select public.accept_order(%L)', v_order), 'forbidden', 'customer cannot accept');
  perform tests.raises(format('select public.complete_order(%L, %L)', v_order, 'DWK-0000000000'), 'forbidden', 'customer cannot complete');

  -- Customers have no direct view of pharmacy internals or history tables.
  perform tests.eq(tests.count('select 1 from public.pharmacy_products'), '0', 'no product rows');
  perform tests.eq(tests.count('select 1 from public.pharmacies'), '0', 'no pharmacy rows');
  perform tests.eq(tests.count('select 1 from public.pharmacy_members'), '0', 'no membership rows');
  perform tests.eq(tests.count('select 1 from public.sales'), '0', 'no sales');
  perform tests.eq(tests.count('select 1 from public.audit_logs'), '0', 'no audit logs');
  perform tests.raises('select * from public.availability_requests', '42501', 'availability requests unreachable');
  perform tests.raises('select * from public.availability_targets', '42501', 'availability targets unreachable');
  perform tests.eq(tests.count('select 1 from public.profiles where id <> ' || quote_literal(c2)), '0', 'no other profiles');
  perform tests.raises('select * from public.idempotency_keys', '42501', 'idempotency keys unreachable');
  perform tests.raises('select * from public.pharmacy_invoice_counters', '42501', 'counters unreachable');
  perform tests.raises(format('insert into public.sales (pharmacy_id, invoice_no, currency, subtotal, total, cashier_id) values (%L, %L, %L, 1, 1, %L)', tests.uid(fx, 'ph_a'), 'X-1', 'SYP', c2), '42501', 'cannot insert sales');
  perform tests.raises(format('insert into public.availability_requests (customer_id, medicine_id, latitude, longitude, expires_at) values (%L, %L, 1, 1, now())', c2, tests.uid(fx, 'm1')), '42501', 'cannot insert requests directly');
  perform tests.raises(format('update public.pharmacy_products set price = 1 where id = %L', tests.uid(fx, 'a1')), '42501', 'cannot update the list');
  perform tests.raises(format('select public.update_pharmacy_product(%L, 1)', tests.uid(fx, 'a1')), 'forbidden', 'cannot call list RPC');
  perform tests.raises(format('select public.create_pos_sale(%L, %L::jsonb, 0, %L)', tests.uid(fx, 'ph_a'),
      jsonb_build_array(jsonb_build_object('product_id', tests.uid(fx, 'a1'), 'quantity', 1))::text, 'pos-c2-0001-aaaa'), 'forbidden', 'customer cannot POS');
  perform tests.raises(format('select public.pharmacy_dashboard(%L)', tests.uid(fx, 'ph_a')), 'forbidden', 'customer cannot read dashboard');
  perform tests.raises('select public.admin_metrics()', 'forbidden', 'customer cannot read admin metrics');

  -- Pharmacy sees the customer's per-order snapshot, never their profile.
  perform tests.act_as(tests.uid(fx, 'pa'));
  perform tests.eq((select customer_name from public.orders where id = v_order), 'Customer One', 'name snapshot visible to pharmacy');
  perform tests.eq((select contact_phone from public.orders where id = v_order), '0955123456', 'order contact phone visible');
  perform tests.eq(tests.count('select 1 from public.profiles where id <> ' || quote_literal(tests.uid(fx, 'pa'))), '0', 'pharmacist cannot read other profiles');
end
$$;

create function tests.t_sec_08_anonymous_access_is_denied() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  r record;
begin
  perform tests.act_as_anon();
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r'
  loop
    perform tests.raises('select 1 from public.' || quote_ident(r.relname), '42501', 'anon cannot read ' || r.relname);
  end loop;
  perform tests.raises('select * from public.search_medicines(''panadol'')', '42501', 'anon cannot search');
  perform tests.raises(format('select public.get_public_pharmacy(%L)', tests.uid(fx, 'ph_a')), '42501', 'anon cannot read pharmacy');
  perform tests.raises(format('select public.create_order(%L, %L::jsonb, null, null, %L)', tests.uid(fx, 'ph_a'), '[]', 'anon-key-0001'), '42501', 'anon cannot order');
  perform tests.raises('select public.admin_metrics()', '42501', 'anon cannot call admin');
  -- Authenticated session without a profile (deleted user) is rejected.
  perform tests.reset();
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  execute 'set local role authenticated';
  perform tests.raises('select * from public.search_medicines(''panadol'')', 'not_authenticated', 'unknown subject rejected');
end
$$;

create function tests.t_sec_09_admin_is_least_privileged() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  admin uuid := tests.uid(fx, 'admin');
  c1 uuid := tests.uid(fx, 'c1');
begin
  perform tests.act_as(c1);
  perform public.create_order(tests.uid(fx, 'ph_a'),
      jsonb_build_array(jsonb_build_object('product_id', tests.uid(fx, 'a1'), 'quantity', 1)), null, null, 'key-adm-0001-aaaa');

  perform tests.act_as(admin);
  perform tests.eq(tests.count('select 1 from public.orders'), '0', 'admin cannot read orders');
  perform tests.eq(tests.count('select 1 from public.order_items'), '0', 'admin cannot read order items');
  perform tests.eq(tests.count('select 1 from public.sales'), '0', 'admin cannot read sales');
  perform tests.eq(tests.count('select 1 from public.pharmacy_products'), '0', 'admin cannot read pharmacy lists');
  perform tests.eq(tests.count('select 1 from public.profiles where role = ''customer'''), '0', 'admin cannot read customer profiles');
  perform tests.ok(tests.count('select 1 from public.profiles where role = ''pharmacist''') >= 2, 'admin can read pharmacist profiles');
  perform tests.ok(tests.count('select 1 from public.pharmacies') >= 2, 'admin can read pharmacies');
  perform tests.ok(tests.count('select 1 from public.audit_logs') >= 2, 'admin can read audit logs');
  perform tests.eq((public.admin_metrics() -> 'pharmacies' ->> 'approved'), '2', 'metrics are aggregates');
  perform tests.raises(format('update public.profiles set role = %L where id = %L', 'admin', c1), '42501', 'admin cannot edit roles via table either');

  -- Account suspension.
  perform tests.raises(format('select public.admin_set_account_status(%L, %L, %L)', admin, 'suspended', 'x'), 'forbidden', 'admin cannot suspend self');
  perform tests.raises(format('select public.admin_set_account_status(%L, %L, null)', c1, 'suspended'), 'invalid_input', 'reason required');
  perform tests.raises(format('select public.admin_set_account_status(%L, %L, %L)', tests.uid(fx, 'pa'), 'banned', 'x'), 'invalid_input', 'unknown status');
  perform public.admin_set_account_status(c1, 'suspended', 'Abuse');

  perform tests.act_as(c1);
  perform tests.raises(format('select public.create_order(%L, %L::jsonb, null, null, %L)', tests.uid(fx, 'ph_a'),
      jsonb_build_array(jsonb_build_object('product_id', tests.uid(fx, 'a1'), 'quantity', 1))::text, 'key-adm-0002-aaaa'), 'account_suspended', 'suspended cannot order');
  perform tests.raises('select * from public.search_medicines(''panadol'')', 'account_suspended', 'suspended cannot search');

  -- Suspended pharmacist loses pharmacy powers too.
  perform tests.act_as(admin);
  perform public.admin_set_account_status(tests.uid(fx, 'pa'), 'suspended', 'Investigation');
  perform tests.act_as(tests.uid(fx, 'pa'));
  perform tests.raises(format('select public.update_pharmacy_product(%L, 3)', tests.uid(fx, 'a1')), 'account_suspended', 'suspended pharmacist blocked');
  perform tests.eq(tests.count('select 1 from public.pharmacy_products'), '0', 'suspended pharmacist reads nothing');

  perform tests.act_as(admin);
  perform tests.raises(format('select public.admin_set_account_status(%L, %L, null)', (select id from public.profiles where role = 'admin' and id <> admin limit 1), 'active'), 'not_found', 'sanity: no such admin');
  perform public.admin_set_account_status(c1, 'active', null);
  perform tests.act_as(c1);
  perform tests.ok(tests.count('select 1 from public.search_medicines(''panadol'')') >= 1, 'reinstated user works');
end
$$;

create function tests.t_sec_10_reports_are_private_and_admin_resolvable() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  c1 uuid := tests.uid(fx, 'c1');
  v_report uuid;
begin
  perform tests.act_as(c1);
  insert into public.user_reports (target_type, target_id, category, description)
  values ('pharmacy', tests.uid(fx, 'ph_a'), 'wrong_info', 'The phone number is wrong') returning id into v_report;
  perform tests.eq((select reporter_id::text from public.user_reports where id = v_report), c1::text, 'reporter set server-side');
  perform tests.eq((select status::text from public.user_reports where id = v_report), 'open', 'starts open');
  perform tests.raises(format('insert into public.user_reports (reporter_id, target_type, category, description) values (%L, %L, %L, %L)', tests.uid(fx, 'c2'), 'app', 'bug', 'spoofed reporter'), '42501', 'cannot spoof reporter');
  perform tests.raises('insert into public.user_reports (target_type, category, description, status) values (''app'', ''bug'', ''sets status'', ''resolved'')', '42501', 'cannot set status');
  perform tests.raises('insert into public.user_reports (target_type, category, description) values (''app'', ''bug'', ''x'')', '23514', 'description validated');
  perform tests.raises(format('update public.user_reports set status = %L where id = %L', 'resolved', v_report), '42501', 'cannot update reports');

  perform tests.act_as(tests.uid(fx, 'c2'));
  perform tests.eq(tests.count('select 1 from public.user_reports'), '0', 'other customer cannot read it');
  perform tests.raises(format('select public.admin_resolve_report(%L, %L, null)', v_report, 'resolved'), 'forbidden', 'non-admin cannot resolve');

  perform tests.act_as(tests.uid(fx, 'admin'));
  perform tests.eq(tests.count('select 1 from public.user_reports'), '1', 'admin sees report');
  perform tests.raises(format('select public.admin_resolve_report(%L, %L, null)', v_report, 'open'), 'invalid_input', 'invalid target status');
  perform public.admin_resolve_report(v_report, 'resolved', 'Phone corrected');
  perform tests.eq((select status::text from public.user_reports where id = v_report), 'resolved', 'resolved');
end
$$;

create function tests.t_sec_11_catalogue_writes_are_admin_only_and_deduplicated() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  v1 jsonb;
  v2 jsonb;
  v3 jsonb;
  v_before bigint;
begin
  -- Customers and pharmacists cannot write the catalogue directly.
  perform tests.act_as(tests.uid(fx, 'c1'));
  perform tests.raises('insert into public.medicines (name_en, catalog_status) values (''Fake'', ''approved'')', '42501', 'customer cannot insert medicine');
  perform tests.raises('insert into public.medicine_categories (name_ar) values (''x'')', '42501', 'customer cannot insert category');
  perform tests.raises(format('select public.propose_medicine(%L, null, null, null, null, null, null)', 'دواء'), 'forbidden', 'customer cannot propose');

  perform tests.act_as(tests.uid(fx, 'pa'));
  perform tests.raises('insert into public.medicines (name_en, catalog_status) values (''Fake'', ''approved'')', '42501', 'pharmacist cannot insert medicine');
  select count(*) into v_before from public.medicines where catalog_status = 'approved';
  execute format('update public.medicines set name_en = %L where id = %L', 'Changed', tests.uid(fx, 'm1'));
  perform tests.eq((select name_en from public.medicines where id = tests.uid(fx, 'm1')), 'Panadol', 'pharmacist cannot update medicine (RLS hides row)');

  -- Proposal workflow with deduplication (case, tashkeel, alef and ta-marbuta variants collapse).
  v1 := public.propose_medicine('أموكسيسيلين', 'Amoxicillin', null, 'amoxicillin', '500mg', 'كبسولة', 'علبة 16', null);
  perform tests.eq(v1 ->> 'catalog_status', 'pending', 'proposal is pending');
  perform tests.eq(v1 ->> 'existed', 'false', 'new proposal');
  v2 := public.propose_medicine('اموكسيسيلين', 'AMOXICILLIN', null, null, '500mg', 'كبسوله', 'علبة 16', null);
  perform tests.eq(v2 ->> 'id', v1 ->> 'id', 'variant collapses to same row');
  perform tests.eq(v2 ->> 'existed', 'true', 'reported as existing');
  v3 := public.propose_medicine('أموكسيسيلين', 'Amoxicillin', null, null, '250mg', 'كبسولة', 'علبة 16', null);
  perform tests.ok(v3 ->> 'id' <> v1 ->> 'id', 'different strength is a different medicine');
  -- Existing approved medicine is returned, never duplicated.
  perform tests.eq((public.propose_medicine('بَنَادُول', 'PANADOL', 'Panadol', null, '500mg', 'أقراص', 'علبة 24 قرص', null) ->> 'id'), tests.uid(fx, 'm1')::text, 'approved medicine reused');
  perform tests.raises('select public.propose_medicine(null, null, null, null, null, null, null)', 'invalid_input', 'name required');
  perform tests.raises(format('select public.propose_medicine(%L, null, null, null, null, null, null, %L)', 'x', gen_random_uuid()), 'invalid_input', 'category must exist');

  -- Pending proposals: visible to proposer and admin only; invisible to others and to search.
  perform tests.eq(tests.count(format('select 1 from public.medicines where id = %L', v1 ->> 'id')), '1', 'proposer sees own proposal');
  perform tests.eq(tests.count('select 1 from public.search_medicines(''amoxicillin'')'), '0', 'pending not searchable');
  perform tests.raises(format('select public.add_pharmacy_product(%L, %L, 10)', tests.uid(fx, 'ph_a'), v1 ->> 'id'), 'not_found', 'cannot list a pending medicine');
  perform tests.act_as(tests.uid(fx, 'pb'));
  perform tests.eq(tests.count(format('select 1 from public.medicines where id = %L', v1 ->> 'id')), '0', 'other pharmacist cannot see it');
  perform tests.raises(format('select public.admin_review_medicine(%L, %L)', v1 ->> 'id', 'approve'), 'forbidden', 'pharmacist cannot approve');

  perform tests.act_as(tests.uid(fx, 'admin'));
  perform tests.eq(tests.count(format('select 1 from public.medicines where id = %L', v1 ->> 'id')), '1', 'admin sees proposal');
  perform public.admin_review_medicine((v1 ->> 'id')::uuid, 'approve');
  perform tests.raises(format('select public.admin_review_medicine(%L, %L)', v1 ->> 'id', 'approve'), 'invalid_transition', 'cannot approve twice');
  perform tests.act_as(tests.uid(fx, 'c1'));
  perform tests.eq(tests.count('select 1 from public.search_medicines(''amoxicillin'')'), '1', 'approved is searchable');

  -- Admin may edit the catalogue directly; generated columns follow.
  perform tests.act_as(tests.uid(fx, 'admin'));
  insert into public.medicine_categories (name_ar, name_en) values ('مسكنات', 'Analgesics');
  perform tests.raises('insert into public.medicine_categories (name_ar) values (''مُسَكِّنَات'')', '23505', 'duplicate category (normalised)');
  update public.medicines set name_en = 'Amoxicillin Forte' where id = (v1 ->> 'id')::uuid;
  perform tests.ok((select search_text from public.medicines where id = (v1 ->> 'id')::uuid) like '%forte%', 'search_text regenerated');
  perform tests.ok(tests.count('select 1 from public.audit_logs where entity_type in (''medicines'', ''medicine_categories'')') >= 2, 'catalogue changes audited');
end
$$;

create function tests.t_sec_12_history_is_append_only() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  v jsonb;
begin
  perform tests.act_as(tests.uid(fx, 'pa'));
  v := public.create_pos_sale(tests.uid(fx, 'ph_a'),
      jsonb_build_array(jsonb_build_object('product_id', tests.uid(fx, 'a1'), 'quantity', 1)), 0, 'pos-ao-0001-aaaa');
  perform tests.reset();
  perform tests.raises('update public.sales set total = 0, subtotal = 0', 'append_only', 'sales immutable');
  perform tests.raises('delete from public.sales', 'append_only', 'sales not deletable');
  perform tests.raises('update public.sale_items set quantity = 5', 'append_only', 'sale items immutable');
  perform tests.raises('delete from public.sale_items', 'append_only', 'sale items not deletable');
  perform tests.raises('update public.audit_logs set action = ''x''', 'append_only', 'audit immutable');
  perform tests.raises('delete from public.audit_logs', 'append_only', 'audit not deletable');
  perform tests.raises('truncate public.sales cascade', 'append_only', 'sales not truncatable (cascade)');
  perform tests.raises('truncate public.audit_logs', 'append_only', 'audit not truncatable');
  -- Products with history cannot be hard-deleted.
  perform tests.raises(format('delete from public.pharmacy_products where id = %L', tests.uid(fx, 'a1')), '23503', 'product with history cannot be deleted');
  perform tests.raises(format('delete from public.pharmacies where id = %L', tests.uid(fx, 'ph_a')), '23503', 'pharmacy with history cannot be deleted');
end
$$;

create function tests.t_sec_13_licence_storage_policies() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
begin
  perform tests.act_as(pa);
  insert into storage.objects (bucket_id, name, owner) values ('pharmacy-documents', pa::text || '/licence.pdf', pa);
  perform tests.raises(format('insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)', 'pharmacy-documents', tests.uid(fx, 'pb')::text || '/licence.pdf', pa), '42501', 'cannot write into another folder');
  perform tests.raises(format('insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)', 'pharmacy-documents', 'loose.pdf', pa), '42501', 'must be in own folder');
  perform tests.raises(format('insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)', 'other-bucket', pa::text || '/x.pdf', pa), '42501', 'other buckets not allowed');
  perform tests.eq(tests.count('select 1 from storage.objects'), '1', 'owner reads own file');
  perform tests.eq(tests.affected(format('update storage.objects set name = %L', pa::text || '/renamed.pdf')), 0::bigint, 'no update policy: rename touches nothing');
  perform tests.eq(tests.affected('delete from storage.objects'), 0::bigint, 'no delete policy: delete touches nothing');
  perform tests.eq(tests.count('select 1 from storage.objects where name = ' || quote_literal(pa::text || '/licence.pdf')), 1::bigint, 'file still present and unrenamed');
  perform tests.act_as(tests.uid(fx, 'pb'));
  perform tests.eq(tests.count('select 1 from storage.objects'), '0', 'other pharmacist sees nothing');
  perform tests.act_as(tests.uid(fx, 'c1'));
  perform tests.eq(tests.count('select 1 from storage.objects'), '0', 'customer sees nothing');
  perform tests.act_as(tests.uid(fx, 'admin'));
  perform tests.eq(tests.count('select 1 from storage.objects'), '1', 'admin reads licence documents');
  perform tests.eq((select file_size_limit::text from storage.buckets where id = 'pharmacy-documents'), '5242880', 'bucket limited to 5 MB');
  perform tests.eq((select public::text from storage.buckets where id = 'pharmacy-documents'), 'false', 'bucket private');
end
$$;
