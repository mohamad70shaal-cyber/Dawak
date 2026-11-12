-- "Ask the pharmacies nearby": availability requests (docs/availability_design.md).
--
-- Concurrency contract: every function that changes a request locks the request row first
-- (FOR UPDATE) and then its target rows; the expansion rule runs under that lock.
-- Clients have no direct access to availability_requests / availability_targets.

-- ---------------------------------------------------------------------------
-- Geography
-- ---------------------------------------------------------------------------
-- Approved, listed pharmacies with a location within p_radius_km of a point (bounding-box prefilter + exact distance).
create function private.pharmacies_within(
  p_lat double precision, p_lng double precision, p_radius_km double precision
) returns table (pharmacy_id uuid, distance_km double precision)
language sql stable security definer set search_path = '' as $$
  select t.id, t.d
  from (
    select ph.id, private.distance_km(p_lat, p_lng, ph.latitude, ph.longitude) as d
    from public.pharmacies ph
    where ph.approval_status = 'approved' and ph.is_listed and ph.latitude is not null
      and ph.latitude between p_lat - p_radius_km / 111.0 and p_lat + p_radius_km / 111.0
      and ph.longitude between p_lng - p_radius_km / (111.0 * greatest(cos(radians(p_lat)), 0.01))
                           and p_lng + p_radius_km / (111.0 * greatest(cos(radians(p_lat)), 0.01))
  ) t
  where t.d <= p_radius_km
$$;

-- ---------------------------------------------------------------------------
-- Targets and expansion
-- ---------------------------------------------------------------------------
-- Adds (and notifies) the pharmacies inside the radius of `p_step` that were not targeted yet,
-- nearest first, never exceeding max_request_targets in total. Returns how many were added.
create function private.add_request_targets(p_request_id uuid, p_step integer) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  r public.availability_requests;
  v_room integer;
  v_added integer := 0;
  v_name text;
  t record;
begin
  select * into r from public.availability_requests where id = p_request_id;
  select private.cfg_int('max_request_targets') - count(*) into v_room
  from public.availability_targets x where x.request_id = p_request_id;
  if v_room <= 0 then
    return 0;
  end if;
  select coalesce(nullif(btrim(m.name_ar), ''), m.name_en) into v_name
  from public.medicines m where m.id = r.medicine_id;

  for t in
    select w.pharmacy_id, w.distance_km
    from private.pharmacies_within(r.latitude, r.longitude, private.request_radius_km(p_step)) w
    where not exists (
      select 1 from public.availability_targets x
      where x.request_id = p_request_id and x.pharmacy_id = w.pharmacy_id
    )
    order by w.distance_km, w.pharmacy_id
    limit v_room
  loop
    insert into public.availability_targets (request_id, pharmacy_id, step, distance_km)
    values (p_request_id, t.pharmacy_id, p_step, round(t.distance_km::numeric, 2));
    perform private.notify_pharmacy(t.pharmacy_id, 'availability_request', 'availability_request', p_request_id,
                                    jsonb_build_object('medicine', v_name));
    v_added := v_added + 1;
  end loop;
  return v_added;
end
$$;

-- Applies the lifecycle rules to one request (caller should hold the row lock):
--   * past expires_at            -> 'expired'
--   * somebody answered available -> nothing to do
--   * otherwise the radius is widened one step when the current radius has no pharmacy, every notified
--     pharmacy answered "unavailable", or request_wait_minutes passed since the last step.
create function private.advance_request(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.availability_requests;
  v_total integer;
  v_answered integer;
  v_available integer;
begin
  loop
    select * into r from public.availability_requests where id = p_id for update;
    if not found or r.status <> 'open' then
      return;
    end if;
    if r.expires_at <= now() then
      update public.availability_requests set status = 'expired', closed_at = now() where id = p_id;
      return;
    end if;
    select count(*), count(*) filter (where t.answer is not null), count(*) filter (where t.answer = 'available')
    into v_total, v_answered, v_available
    from public.availability_targets t where t.request_id = p_id;

    if v_available > 0 or r.step >= private.cfg_int('request_max_step') then
      return;
    end if;
    if v_total = 0 or v_answered = v_total
       or r.last_expanded_at <= now() - make_interval(mins => private.cfg_int('request_wait_minutes')) then
      update public.availability_requests
      set step = r.step + 1, last_expanded_at = now()
      where id = p_id;
      perform private.add_request_targets(p_id, r.step + 1);
    else
      return;
    end if;
  end loop;
end
$$;

-- Maintenance for pg_cron (every minute is plenty): expands / expires open requests and deletes old ones.
create function private.advance_all_availability_requests() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  n integer := 0;
begin
  for v_id in
    select r.id from public.availability_requests r where r.status = 'open' order by r.id for update skip locked
  loop
    perform private.advance_request(v_id);
    n := n + 1;
  end loop;
  delete from public.availability_requests where created_at < now() - interval '30 days';
  return n;
end
$$;

-- ---------------------------------------------------------------------------
-- JSON for the customer (call only after the caller was authorised as the request's owner)
-- ---------------------------------------------------------------------------
create function private.request_json(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  r public.availability_requests;
  v_status text;
begin
  select * into r from public.availability_requests where id = p_id;
  v_status := case when r.status = 'open' and r.expires_at <= now() then 'expired' else r.status::text end;
  return jsonb_build_object(
    'id', r.id,
    'status', v_status,
    'step', r.step,
    'radius_km', private.request_radius_km(r.step),
    'radius_exhausted', r.step >= private.cfg_int('request_max_step'),
    'created_at', r.created_at,
    'expires_at', r.expires_at,
    'seconds_left', case when v_status = 'open' then greatest(0, extract(epoch from r.expires_at - now()))::integer else 0 end,
    'medicine', (
      select jsonb_build_object('id', m.id, 'name_ar', m.name_ar, 'name_en', m.name_en,
                                'brand_name', m.brand_name, 'strength', m.strength, 'dosage_form', m.dosage_form)
      from public.medicines m where m.id = r.medicine_id
    ),
    'notified', (select count(*) from public.availability_targets t where t.request_id = r.id),
    'answered', (select count(*) from public.availability_targets t where t.request_id = r.id and t.answer is not null),
    'unavailable', (select count(*) from public.availability_targets t where t.request_id = r.id and t.answer = 'unavailable'),
    'offers', coalesce((
      select jsonb_agg(o order by o.distance_km, o.price, o.pharmacy_id)
      from (
        select ph.id as pharmacy_id, ph.name, ph.address_line, ph.neighborhood, ph.city,
               case when ph.show_phone_publicly then ph.phone else null end as phone,
               ph.latitude, ph.longitude, t.distance_km, t.price, ph.currency, t.answered_at,
               pp.id as product_id
        from public.availability_targets t
        join public.pharmacies ph on ph.id = t.pharmacy_id
        left join public.pharmacy_products pp on pp.pharmacy_id = ph.id and pp.medicine_id = r.medicine_id
        where t.request_id = r.id and t.answer = 'available'
          and ph.approval_status = 'approved' and ph.is_listed
      ) o
    ), '[]'::jsonb)
  );
end
$$;

-- Locks a request owned by the caller (customer); `not_found` otherwise (no existence oracle).
create function private.lock_own_request(p_id uuid) returns public.availability_requests
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.assert_active_user();
  v_owner uuid;
  r public.availability_requests;
begin
  select q.customer_id into v_owner from public.availability_requests q where q.id = p_id;
  if v_owner is null or v_owner <> v_uid then
    perform private.fail('not_found');
  end if;
  select * into r from public.availability_requests where id = p_id for update;
  return r;
end
$$;

-- ---------------------------------------------------------------------------
-- Customer API
-- ---------------------------------------------------------------------------
create function public.create_availability_request(
  p_medicine_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_role public.user_role;
  v_lat double precision;
  v_lng double precision;
  v_hash text;
  v_prev jsonb;
  v_existing uuid;
  v_req public.availability_requests;
  v_resp jsonb;
begin
  v_uid := private.assert_active_user();
  -- Serialises one customer's requests so the caps below cannot be beaten by parallel calls.
  select p.role into v_role from public.profiles p where p.id = v_uid for no key update;
  if v_role <> 'customer' then
    perform private.fail('forbidden');
  end if;
  perform private.check_location(p_latitude, p_longitude);
  if p_medicine_id is null then
    perform private.fail('invalid_input', jsonb_build_object('field', 'medicine_id'));
  end if;
  v_lat := round(p_latitude::numeric, 3)::double precision;
  v_lng := round(p_longitude::numeric, 3)::double precision;

  v_hash := md5(p_medicine_id::text || ':' || v_lat::text || ':' || v_lng::text);
  v_prev := private.idem_begin(v_uid, 'create_request', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev;
  end if;

  if not exists (select 1 from public.medicines m where m.id = p_medicine_id and m.catalog_status = 'approved') then
    perform private.fail('not_found', jsonb_build_object('field', 'medicine_id'));
  end if;

  -- Same medicine from (nearly) the same spot while a request is still alive: reuse it.
  select q.id into v_existing
  from public.availability_requests q
  where q.customer_id = v_uid and q.medicine_id = p_medicine_id
    and q.status = 'open' and q.expires_at > now()
    and q.created_at > now() - make_interval(mins => private.cfg_int('request_dedupe_minutes'))
    and private.distance_km(q.latitude, q.longitude, v_lat, v_lng) < 0.5
  order by q.created_at desc
  limit 1;
  if v_existing is not null then
    select * into v_req from public.availability_requests where id = v_existing for update;
    perform private.advance_request(v_existing);
    v_resp := private.request_json(v_existing);
    perform private.idem_finish(v_uid, 'create_request', p_idempotency_key, v_resp);
    return v_resp;
  end if;

  if (select count(*) from public.availability_requests q
      where q.customer_id = v_uid and q.status = 'open' and q.expires_at > now())
       >= private.cfg_int('max_open_requests') then
    perform private.fail('too_many_requests');
  end if;
  if (select count(*) from public.availability_requests q
      where q.customer_id = v_uid and q.created_at > now() - interval '1 hour')
       >= private.cfg_int('max_requests_per_hour') then
    perform private.fail('rate_limited');
  end if;

  insert into public.availability_requests (customer_id, medicine_id, latitude, longitude, expires_at)
  values (v_uid, p_medicine_id, v_lat, v_lng, now() + make_interval(mins => private.cfg_int('request_ttl_minutes')))
  returning * into v_req;

  perform private.add_request_targets(v_req.id, 1);
  perform private.advance_request(v_req.id);

  v_resp := private.request_json(v_req.id);
  perform private.idem_finish(v_uid, 'create_request', p_idempotency_key, v_resp);
  return v_resp;
end
$$;

-- Polled by the customer's screen: also applies the expansion / expiry rules.
create function public.get_availability_request(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.availability_requests;
begin
  r := private.lock_own_request(p_request_id);
  perform private.advance_request(r.id);
  return private.request_json(r.id);
end
$$;

create function public.list_my_availability_requests(p_limit integer default 20, p_offset integer default 0)
returns table (
  id uuid, medicine_id uuid, name_ar text, name_en text, strength text, dosage_form text,
  status text, created_at timestamptz, expires_at timestamptz, offers_count integer
)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_uid uuid;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  v_uid := private.assert_active_user();
  return query
  select q.id, q.medicine_id, m.name_ar, m.name_en, m.strength, m.dosage_form,
         case when q.status = 'open' and q.expires_at <= now() then 'expired' else q.status::text end,
         q.created_at, q.expires_at,
         (select count(*)::integer from public.availability_targets t
          where t.request_id = q.id and t.answer = 'available')
  from public.availability_requests q
  join public.medicines m on m.id = q.medicine_id
  where q.customer_id = v_uid
  order by q.created_at desc, q.id
  limit v_limit offset v_offset;
end
$$;

-- "Search further": widens the radius by one step (also done automatically, see advance_request).
create function public.expand_availability_request(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.availability_requests;
begin
  r := private.lock_own_request(p_request_id);
  perform private.advance_request(r.id);
  select * into r from public.availability_requests where id = r.id;
  if r.status = 'closed' then
    perform private.fail('request_closed');
  end if;
  if r.status = 'expired' or r.expires_at <= now() then
    return private.request_json(r.id);
  end if;
  if r.step >= private.cfg_int('request_max_step') then
    perform private.fail('invalid_transition', jsonb_build_object('reason', 'max_radius'));
  end if;
  update public.availability_requests set step = r.step + 1, last_expanded_at = now() where id = r.id;
  perform private.add_request_targets(r.id, r.step + 1);
  perform private.advance_request(r.id);
  return private.request_json(r.id);
end
$$;

create function public.close_availability_request(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.availability_requests;
begin
  r := private.lock_own_request(p_request_id);
  if r.status = 'open' and r.expires_at > now() then
    update public.availability_requests set status = 'closed', closed_at = now() where id = r.id;
  end if;
  return private.request_json(r.id);
end
$$;

-- ---------------------------------------------------------------------------
-- Pharmacy API (inbox + answer). Pharmacies never see who asked or where the customer is.
-- ---------------------------------------------------------------------------
create function private.open_request_count(p_pharmacy_id uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer
  from public.availability_targets t
  join public.availability_requests r on r.id = t.request_id
  where t.pharmacy_id = p_pharmacy_id and t.answer is null
    and r.status = 'open' and r.expires_at > now()
$$;

create function public.count_pharmacy_availability_requests(p_pharmacy_id uuid) returns integer
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner', 'manager', 'cashier']::public.member_role[], true);
  return private.open_request_count(p_pharmacy_id);
end
$$;

create function public.list_pharmacy_availability_requests(
  p_pharmacy_id uuid,
  p_only_open boolean default true,
  p_limit integer default 30,
  p_offset integer default 0
) returns table (
  request_id uuid, medicine_id uuid, name_ar text, name_en text, brand_name text, strength text,
  dosage_form text, distance_km numeric, created_at timestamptz, expires_at timestamptz,
  request_status text, answer text, answer_price numeric, answered_at timestamptz,
  listed_price numeric, listed_available boolean
)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_limit integer := least(greatest(coalesce(p_limit, 30), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  perform private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner', 'manager', 'cashier']::public.member_role[], true);
  return query
  select r.id, m.id, m.name_ar, m.name_en, m.brand_name, m.strength, m.dosage_form,
         t.distance_km, r.created_at, r.expires_at,
         case when r.status = 'open' and r.expires_at <= now() then 'expired' else r.status::text end,
         t.answer::text, t.price, t.answered_at,
         pp.price, pp.is_available
  from public.availability_targets t
  join public.availability_requests r on r.id = t.request_id
  join public.medicines m on m.id = r.medicine_id
  left join public.pharmacy_products pp on pp.pharmacy_id = t.pharmacy_id and pp.medicine_id = r.medicine_id
  where t.pharmacy_id = p_pharmacy_id
    and (
      (p_only_open and r.status = 'open' and r.expires_at > now())
      or (not p_only_open and t.notified_at > now() - interval '7 days')
    )
  order by (t.answer is null and r.status = 'open' and r.expires_at > now()) desc, t.notified_at desc, r.id
  limit v_limit offset v_offset;
end
$$;

-- Answer "available" (with price) or "unavailable". May be repeated while the request is open.
-- Owners/managers' answers also keep the pharmacy list up to date; a cashier's answer only answers.
create function public.answer_availability_request(
  p_pharmacy_id uuid,
  p_request_id uuid,
  p_available boolean,
  p_price numeric default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_role public.member_role;
  r public.availability_requests;
  v_target public.availability_targets;
  v_first boolean;
  v_med_name text;
  v_ph_name text;
begin
  v_uid := private.assert_active_user();
  v_role := private.assert_member(p_pharmacy_id, array['owner', 'manager', 'cashier']::public.member_role[], true);
  if p_available is null then
    perform private.fail('invalid_input', jsonb_build_object('field', 'available'));
  end if;
  if p_available and (p_price is null or p_price <= 0 or p_price > 999999999999 or scale(p_price) > 2) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'price'));
  end if;

  select * into r from public.availability_requests where id = p_request_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  select * into v_target from public.availability_targets t
  where t.request_id = p_request_id and t.pharmacy_id = p_pharmacy_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  if r.status <> 'open' or r.expires_at <= now() then
    perform private.fail('request_closed');
  end if;

  v_first := p_available and not exists (
    select 1 from public.availability_targets t where t.request_id = p_request_id and t.answer = 'available'
  );

  update public.availability_targets set
    answer = case when p_available then 'available'::public.request_answer else 'unavailable'::public.request_answer end,
    price = case when p_available then p_price else null end,
    answered_by = v_uid,
    answered_at = now()
  where request_id = p_request_id and pharmacy_id = p_pharmacy_id
  returning * into v_target;

  -- The pharmacy list learns from the answer (owners and managers only: cashiers cannot change prices).
  if v_role in ('owner', 'manager') then
    if p_available then
      insert into public.pharmacy_products as pp (pharmacy_id, medicine_id, price, is_available, confirmed_at)
      values (p_pharmacy_id, r.medicine_id, p_price, true, now())
      on conflict (pharmacy_id, medicine_id) do update
        set price = excluded.price, is_available = true, confirmed_at = now();
    else
      update public.pharmacy_products
      set is_available = false, confirmed_at = now()
      where pharmacy_id = p_pharmacy_id and medicine_id = r.medicine_id;
    end if;
  end if;

  if v_first then
    select coalesce(nullif(btrim(m.name_ar), ''), m.name_en) into v_med_name
    from public.medicines m where m.id = r.medicine_id;
    select ph.name into v_ph_name from public.pharmacies ph where ph.id = p_pharmacy_id;
    perform private.notify(r.customer_id, 'availability_found', 'availability_request', r.id,
                           jsonb_build_object('medicine', v_med_name, 'pharmacy', v_ph_name));
  end if;

  return jsonb_build_object(
    'request_id', p_request_id, 'pharmacy_id', p_pharmacy_id,
    'answer', v_target.answer, 'price', v_target.price, 'answered_at', v_target.answered_at
  );
end
$$;
