-- Test helpers (plain PL/pgSQL, no pgTAP needed). Loaded only into throw-away test databases.
-- Each test is a function tests.t_*() run in its own subtransaction that is always rolled back.

create schema if not exists tests;
grant usage on schema tests to public;
-- Migrations revoke the built-in PUBLIC execute default; test helpers run under `authenticated`/`anon`, so re-grant here (test DB only).
alter default privileges in schema tests grant execute on functions to public;

-- ---------------------------------------------------------------------------
-- Session / identity helpers
-- ---------------------------------------------------------------------------
create function tests.create_user(p_email text, p_name text default '') returns uuid
language plpgsql as $$
declare
  v uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v, p_email, jsonb_build_object('display_name', p_name));
  return v;
end
$$;

-- Behave like PostgREST: role `authenticated` with the JWT subject set.
create function tests.act_as(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
end
$$;

create function tests.act_as_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  execute 'set local role anon';
end
$$;

create function tests.reset() returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end
$$;

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
create function tests.ok(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if p_cond is not true then
    raise exception using errcode = 'T0001', message = 'ASSERT: ' || p_msg;
  end if;
end
$$;

create function tests.eq(p_actual anyelement, p_expected anyelement, p_msg text) returns void
language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception using errcode = 'T0001',
      message = format('ASSERT: %s (actual=%s expected=%s)', p_msg, coalesce(p_actual::text, 'NULL'), coalesce(p_expected::text, 'NULL'));
  end if;
end
$$;

-- Runs a statement and requires it to fail with MESSAGE = p_expected (business code) or that SQLSTATE.
create function tests.raises(p_sql text, p_expected text, p_msg text) returns void
language plpgsql as $$
declare
  v_state text;
  v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_message = p_expected or v_state = p_expected then
      return;
    end if;
    raise exception using errcode = 'T0001',
      message = format('ASSERT: %s — expected [%s] but got [%s] %s', p_msg, p_expected, v_state, v_message);
  end;
  raise exception using errcode = 'T0001',
    message = format('ASSERT: %s — expected error [%s] but statement succeeded', p_msg, p_expected);
end
$$;

create function tests.count(p_sql text) returns bigint
language plpgsql as $$
declare
  n bigint;
begin
  execute 'select count(*) from (' || p_sql || ') s' into n;
  return n;
end
$$;

-- Number of rows a DML statement touched (RLS without a matching policy silently yields 0).
create function tests.affected(p_sql text) returns bigint
language plpgsql as $$
declare
  n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end
$$;

create function tests.uid(p_fx jsonb, p_key text) returns uuid
language sql immutable as $$
  select (p_fx ->> p_key)::uuid
$$;

-- Invariants that must hold after any scenario: sale totals match their items; request answers have a
-- consistent shape; no pharmacy is targeted by a request that was never inside any radius step.
-- security definer: the checks must see every row whichever role the calling test is currently acting as
create function tests.check_invariants() returns void
language plpgsql security definer as $$
declare
  v_bad bigint;
begin
  select count(*) into v_bad
  from public.sales s
  where s.total <> s.subtotal - s.discount_amount
     or s.subtotal <> coalesce((select sum(si.line_total) from public.sale_items si where si.sale_id = s.id), 0);
  perform tests.ok(v_bad = 0, 'sale totals are consistent with their items');

  select count(*) into v_bad
  from public.availability_targets t
  join public.availability_requests r on r.id = t.request_id
  where t.step > r.step
     or t.distance_km > private.request_radius_km(t.step) + 0.01;
  perform tests.ok(v_bad = 0, 'every request target lies inside the radius of the step that added it');

  select count(*) into v_bad
  from public.availability_requests r
  where (select count(*) from public.availability_targets t where t.request_id = r.id)
        > private.cfg_int('max_request_targets');
  perform tests.ok(v_bad = 0, 'no request exceeds the target cap');
end
$$;

-- ---------------------------------------------------------------------------
-- Standard world: admin, two approved pharmacies (A, B), two customers, three approved medicines
-- ---------------------------------------------------------------------------
create function tests.fx(p_tag text default '') returns jsonb
language plpgsql as $$
declare
  v_admin uuid;
  v_pa uuid;
  v_pb uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_ph_a uuid;
  v_ph_b uuid;
  v_m1 uuid;
  v_m2 uuid;
  v_m3 uuid;
  v_a1 uuid;
  v_a2 uuid;
  v_b1 uuid;
begin
  v_admin := tests.create_user('admin' || p_tag || '@t.test', 'Admin');
  update public.profiles set role = 'admin' where id = v_admin;
  v_pa := tests.create_user('pa' || p_tag || '@t.test', 'Pharmacist A');
  v_pb := tests.create_user('pb' || p_tag || '@t.test', 'Pharmacist B');
  v_c1 := tests.create_user('c1' || p_tag || '@t.test', 'Customer One');
  v_c2 := tests.create_user('c2' || p_tag || '@t.test', 'Customer Two');

  insert into public.medicines (name_ar, name_en, brand_name, active_ingredient, strength, dosage_form, package_description, catalog_status)
  values ('بنادول', 'Panadol' || p_tag, 'Panadol', 'paracetamol', '500mg', 'أقراص', 'علبة 24 قرص', 'approved')
  returning id into v_m1;
  insert into public.medicines (name_ar, name_en, brand_name, active_ingredient, strength, dosage_form, package_description, catalog_status)
  values ('أوميبرازول', 'Omeprazole' || p_tag, null, 'omeprazole', '20mg', 'كبسولة', 'علبة 14 كبسولة', 'approved')
  returning id into v_m2;
  insert into public.medicines (name_ar, name_en, brand_name, active_ingredient, strength, dosage_form, package_description, catalog_status)
  values ('فيتامين ج', 'Vitamin C' || p_tag, null, 'ascorbic acid', '1000mg', 'أقراص فوارة', 'أنبوب 20 قرص', 'approved')
  returning id into v_m3;

  perform tests.act_as(v_pa);
  -- Pharmacy A at (33.5100, 36.2800); pharmacy B 0.56 km north of it. The standard customer spot used by the
  -- request tests is (33.5110, 36.2800): 0.11 km from A, 0.44 km from B.
  v_ph_a := ((public.register_pharmacy('Pharmacy A', '0933111111', 'Street 1', 'Mazzeh', 'Damascus', null,
                                       '{}'::jsonb, 'SYP', v_pa::text || '/lic.pdf', 33.5100, 36.2800)) ->> 'id')::uuid;
  perform tests.act_as(v_pb);
  v_ph_b := ((public.register_pharmacy('Pharmacy B', '0933222222', 'Street 2', 'Midan', 'Damascus', null,
                                       '{}'::jsonb, 'SYP', v_pb::text || '/lic.pdf', 33.5150, 36.2800)) ->> 'id')::uuid;
  perform tests.act_as(v_admin);
  perform public.admin_review_pharmacy(v_ph_a, 'approve', null);
  perform public.admin_review_pharmacy(v_ph_b, 'approve', null);

  perform tests.act_as(v_pa);
  v_a1 := ((public.add_pharmacy_product(v_ph_a, v_m1, 1000.00)) ->> 'id')::uuid;
  v_a2 := ((public.add_pharmacy_product(v_ph_a, v_m2, 2500.50)) ->> 'id')::uuid;
  perform tests.act_as(v_pb);
  v_b1 := ((public.add_pharmacy_product(v_ph_b, v_m1, 1100.00)) ->> 'id')::uuid;

  perform tests.reset();
  return jsonb_build_object(
    'admin', v_admin, 'pa', v_pa, 'pb', v_pb, 'c1', v_c1, 'c2', v_c2,
    'ph_a', v_ph_a, 'ph_b', v_ph_b, 'm1', v_m1, 'm2', v_m2, 'm3', v_m3,
    'a1', v_a1, 'a2', v_a2, 'b1', v_b1
  );
end
$$;

-- ---------------------------------------------------------------------------
-- Runner: executes every tests.t_* function in an isolated, always-rolled-back subtransaction.
-- ---------------------------------------------------------------------------
create function tests.run_all(p_pattern text default '%') returns table (name text, ok boolean, message text)
language plpgsql as $$
declare
  r record;
  v_state text;
  v_msg text;
begin
  for r in
    select p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'tests' and p.proname like 't\_%' and p.proname like p_pattern
    order by p.proname
  loop
    begin
      execute format('select tests.%I()', r.proname);
      raise exception using errcode = 'T0099', message = 'rollback_test';
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
      name := r.proname;
      if v_state = 'T0099' then
        ok := true;
        message := '';
      else
        ok := false;
        message := v_state || ': ' || v_msg;
      end if;
      return next;
    end;
  end loop;
end
$$;

-- A cashier employed at a pharmacy (employee-management UI is deferred, so tests insert the membership directly).
create function tests.mk_cashier(p_pharmacy uuid, p_email text) returns uuid
language plpgsql as $$
declare
  v uuid;
begin
  v := tests.create_user(p_email, 'Cashier');
  update public.profiles set role = 'pharmacist' where id = v;
  insert into public.pharmacy_members (pharmacy_id, user_id, role) values (p_pharmacy, v, 'cashier');
  return v;
end
$$;

-- Builds a JSON items array: tests.items(product1, qty1, product2, qty2, ...)
create function tests.items(variadic p_args text[]) returns jsonb
language plpgsql immutable as $$
declare
  v jsonb := '[]'::jsonb;
  i integer := 1;
begin
  while i < array_length(p_args, 1) loop
    v := v || jsonb_build_array(jsonb_build_object('product_id', p_args[i], 'quantity', p_args[i + 1]::integer));
    i := i + 2;
  end loop;
  return v;
end
$$;
