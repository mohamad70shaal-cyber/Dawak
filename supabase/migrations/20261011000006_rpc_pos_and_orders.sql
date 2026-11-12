-- Trusted functions: POS sales and the customer reservation lifecycle.
--
-- A "reservation" is the pharmacy's promise to prepare an order for `reservation_hours`; there are no
-- quantities in this system (docs/availability_design.md), so nothing is decremented or released.
--
-- Concurrency contract (see docs/database_schema.md §7):
--   * every state change locks the order row and re-reads its status after taking the lock
--   * the invoice counter row serialises invoice numbers per pharmacy

-- ---------------------------------------------------------------------------
-- JSON builders (call only after the caller has been authorised)
-- ---------------------------------------------------------------------------
create function private.sale_json(p_sale_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', s.id,
    'invoice_no', s.invoice_no,
    'order_id', s.order_id,
    'payment_method', s.payment_method,
    'currency', s.currency,
    'subtotal', s.subtotal,
    'discount_amount', s.discount_amount,
    'total', s.total,
    'created_at', s.created_at,
    'cashier_name', coalesce(pr.display_name, ''),
    'pharmacy', jsonb_build_object(
      'id', ph.id, 'name', ph.name, 'phone', ph.phone,
      'address_line', ph.address_line, 'neighborhood', ph.neighborhood, 'city', ph.city
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'line_no', i.line_no, 'product_id', i.product_id, 'name', i.product_name,
        'strength', i.strength, 'quantity', i.quantity, 'unit_price', i.unit_price, 'line_total', i.line_total
      ) order by i.line_no)
      from public.sale_items i where i.sale_id = s.id
    ), '[]'::jsonb)
  )
  from public.sales s
  join public.pharmacies ph on ph.id = s.pharmacy_id
  left join public.profiles pr on pr.id = s.cashier_id
  where s.id = p_sale_id
$$;

create function private.order_json(p_order_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select to_jsonb(o) || jsonb_build_object(
    'pharmacy_name', ph.name,
    'items', coalesce((
      select jsonb_agg(to_jsonb(i) order by i.line_no)
      from public.order_items i where i.order_id = o.id
    ), '[]'::jsonb)
  )
  from public.orders o
  join public.pharmacies ph on ph.id = o.pharmacy_id
  where o.id = p_order_id
$$;

-- ---------------------------------------------------------------------------
-- Locking helpers
-- ---------------------------------------------------------------------------
create function private.lock_order_for_member(
  p_order_id uuid, p_roles public.member_role[], p_require_approved boolean
) returns public.orders
language plpgsql security definer set search_path = '' as $$
declare
  v_pharmacy uuid;
  v_order public.orders;
begin
  select o.pharmacy_id into v_pharmacy from public.orders o where o.id = p_order_id;
  if v_pharmacy is null then
    perform private.fail('not_found');
  end if;
  perform private.assert_member(v_pharmacy, p_roles, p_require_approved);
  select * into v_order from public.orders where id = p_order_id for update;
  return v_order;
end
$$;

-- ---------------------------------------------------------------------------
-- Reservation window
-- ---------------------------------------------------------------------------
-- Expires one order if (and only if) its reservation window has passed.
create function private.expire_order(p_order_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found
     or v_order.status not in ('accepted', 'ready_for_pickup')
     or v_order.reservation_expires_at is null
     or v_order.reservation_expires_at > now() then
    return false;
  end if;
  update public.orders set status = 'expired', expired_at = now() where id = v_order.id;
  perform private.notify(v_order.customer_id, 'order_expired', 'order', v_order.id,
                         jsonb_build_object('ref', v_order.public_ref));
  perform private.notify_pharmacy(v_order.pharmacy_id, 'order_expired', 'order', v_order.id,
                                  jsonb_build_object('ref', v_order.public_ref));
  return true;
end
$$;

-- SKIP LOCKED: an order another transaction is working on is simply left for the next run.
create function private.expire_pharmacy(p_pharmacy uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  n integer := 0;
begin
  for v_id in
    select o.id from public.orders o
    where o.pharmacy_id = p_pharmacy
      and o.status in ('accepted', 'ready_for_pickup')
      and o.reservation_expires_at <= now()
    order by o.id
    for update skip locked
  loop
    if private.expire_order(v_id) then
      n := n + 1;
    end if;
  end loop;
  return n;
end
$$;

-- For pg_cron / service context only (not exposed to clients).
create function private.expire_all_reservations() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  n integer := 0;
begin
  for v_id in
    select o.id from public.orders o
    where o.status in ('accepted', 'ready_for_pickup') and o.reservation_expires_at <= now()
    order by o.id
    for update skip locked
  loop
    if private.expire_order(v_id) then
      n := n + 1;
    end if;
  end loop;
  return n;
end
$$;

-- ---------------------------------------------------------------------------
-- POS
-- ---------------------------------------------------------------------------
create function public.create_pos_sale(
  p_pharmacy_id uuid,
  p_items jsonb,
  p_discount numeric,
  p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_role public.member_role;
  v_hash text;
  v_prev jsonb;
  v_currency text;
  v_lines jsonb := '[]'::jsonb;
  v_subtotal numeric(14, 2) := 0;
  v_discount numeric(14, 2);
  v_total numeric(14, 2);
  v_sale_id uuid;
  v_inv integer;
  v_line integer := 0;
  r record;
  v_resp jsonb;
begin
  v_uid := private.assert_active_user();
  v_role := private.assert_member(p_pharmacy_id, array['owner', 'manager', 'cashier']::public.member_role[], true);

  v_hash := md5(coalesce(p_items::text, '') || ':' || coalesce(p_discount, 0)::text || ':' || p_pharmacy_id::text);
  v_prev := private.idem_begin(v_uid, 'pos_sale', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev;
  end if;

  if coalesce(p_discount, 0) < 0 or scale(coalesce(p_discount, 0)) > 2 then
    perform private.fail('invalid_input', jsonb_build_object('field', 'discount'));
  end if;

  -- The shelf is the truth: any product of THIS pharmacy can be sold, whatever its "available" flag says.
  for r in
    select i.product_id, i.quantity, pp.pharmacy_id, pp.price,
           coalesce(nullif(btrim(m.name_ar), ''), m.name_en) as name, m.strength
    from private.parse_items(p_items, private.cfg_int('max_pos_lines'), private.cfg_int('max_pos_qty_per_item')) i
    left join public.pharmacy_products pp on pp.id = i.product_id
    left join public.medicines m on m.id = pp.medicine_id
    order by i.product_id
  loop
    if r.pharmacy_id is distinct from p_pharmacy_id then
      perform private.fail('product_unavailable', jsonb_build_object('product_id', r.product_id));
    end if;
    v_subtotal := v_subtotal + r.price * r.quantity;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'product_id', r.product_id, 'quantity', r.quantity, 'price', r.price,
      'name', r.name, 'strength', r.strength
    ));
  end loop;

  v_discount := coalesce(p_discount, 0);
  if v_discount > v_subtotal then
    perform private.fail('invalid_input', jsonb_build_object('field', 'discount', 'reason', 'exceeds_subtotal'));
  end if;
  if v_discount > 0 and v_role not in ('owner', 'manager') then
    perform private.fail('forbidden', jsonb_build_object('reason', 'discount'));
  end if;
  v_total := v_subtotal - v_discount;

  select ph.currency into v_currency from public.pharmacies ph where ph.id = p_pharmacy_id;

  insert into public.pharmacy_invoice_counters as c (pharmacy_id, last_number)
  values (p_pharmacy_id, 1)
  on conflict (pharmacy_id) do update set last_number = c.last_number + 1
  returning c.last_number into v_inv;

  insert into public.sales (pharmacy_id, invoice_no, currency, subtotal, discount_amount, total, cashier_id)
  values (p_pharmacy_id, 'INV-' || lpad(v_inv::text, 6, '0'), v_currency, v_subtotal, v_discount, v_total, v_uid)
  returning id into v_sale_id;

  for r in
    select x.product_id, x.quantity, x.price, x.name, x.strength
    from jsonb_to_recordset(v_lines) as x (product_id uuid, quantity integer, price numeric, name text, strength text)
    order by x.product_id
  loop
    v_line := v_line + 1;
    insert into public.sale_items (sale_id, line_no, product_id, product_name, strength, quantity, unit_price)
    values (v_sale_id, v_line, r.product_id, r.name, r.strength, r.quantity, r.price);
  end loop;

  if v_discount > 0 then
    perform private.audit('sale_discount', 'sale', v_sale_id, p_pharmacy_id,
                          jsonb_build_object('discount', v_discount, 'subtotal', v_subtotal));
  end if;

  v_resp := private.sale_json(v_sale_id);
  perform private.idem_finish(v_uid, 'pos_sale', p_idempotency_key, v_resp);
  return v_resp;
end
$$;

create function public.get_sale(p_sale_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_pharmacy uuid;
  v_cashier uuid;
  v_role public.member_role;
begin
  v_uid := private.assert_active_user();
  select s.pharmacy_id, s.cashier_id into v_pharmacy, v_cashier from public.sales s where s.id = p_sale_id;
  if v_pharmacy is null then
    perform private.fail('not_found');
  end if;
  -- Non-members (and cashiers looking at a colleague's sale) get not_found: no existence oracle.
  select m.role into v_role
  from public.pharmacy_members m
  where m.pharmacy_id = v_pharmacy and m.user_id = v_uid and m.status = 'active';
  if v_role is null or (v_role = 'cashier' and v_cashier is distinct from v_uid) then
    perform private.fail('not_found');
  end if;
  return private.sale_json(p_sale_id);
end
$$;

-- ---------------------------------------------------------------------------
-- Customer: create / cancel
-- ---------------------------------------------------------------------------
create function public.create_order(
  p_pharmacy_id uuid,
  p_items jsonb,
  p_notes text,
  p_contact_phone text,
  p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_role public.user_role;
  v_name text;
  v_hash text;
  v_prev jsonb;
  v_ph public.pharmacies;
  v_lines jsonb := '[]'::jsonb;
  v_changes jsonb := '[]'::jsonb;
  v_subtotal numeric(14, 2) := 0;
  v_notes text := private.req_text(p_notes, 'notes', 1, 300, false);
  v_phone text;
  v_order public.orders;
  v_try integer := 0;
  v_line integer := 0;
  r record;
  v_resp jsonb;
begin
  v_uid := private.assert_active_user();
  -- Serialise one customer's order creation so the pending/hourly caps below cannot be beaten by
  -- parallel requests (the row lock is held until the transaction ends).
  select p.role, p.display_name into v_role, v_name from public.profiles p where p.id = v_uid for no key update;
  if v_role <> 'customer' then
    perform private.fail('forbidden');
  end if;

  v_hash := md5(coalesce(p_items::text, '') || ':' || coalesce(p_notes, '') || ':' ||
                coalesce(p_contact_phone, '') || ':' || p_pharmacy_id::text);
  v_prev := private.idem_begin(v_uid, 'create_order', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev;
  end if;

  if nullif(btrim(coalesce(p_contact_phone, '')), '') is not null then
    v_phone := private.clean_phone(p_contact_phone);
    if v_phone is null then
      perform private.fail('invalid_input', jsonb_build_object('field', 'contact_phone'));
    end if;
  end if;

  if (select count(*) from public.orders o where o.customer_id = v_uid and o.status = 'pending')
       >= private.cfg_int('max_pending_orders') then
    perform private.fail('too_many_pending');
  end if;
  if (select count(*) from public.orders o
      where o.customer_id = v_uid and o.created_at > now() - interval '1 hour')
       >= private.cfg_int('max_orders_per_hour') then
    perform private.fail('rate_limited');
  end if;

  select * into v_ph from public.pharmacies ph where ph.id = p_pharmacy_id;
  if not found or v_ph.approval_status <> 'approved' or not v_ph.is_listed then
    perform private.fail('pharmacy_not_active');
  end if;

  for r in
    select i.product_id, i.quantity, i.expected_unit_price,
           pp.pharmacy_id, pp.price, pp.is_available,
           m.id as medicine_id, m.catalog_status, m.strength, m.dosage_form,
           coalesce(nullif(btrim(m.name_ar), ''), m.name_en) as name
    from private.parse_items(p_items, private.cfg_int('max_order_lines'), private.cfg_int('max_customer_qty_per_item')) i
    left join public.pharmacy_products pp on pp.id = i.product_id
    left join public.medicines m on m.id = pp.medicine_id
    order by i.product_id
  loop
    if r.pharmacy_id is distinct from p_pharmacy_id
       or not coalesce(r.is_available, false)
       or r.catalog_status is distinct from 'approved'::public.catalog_status then
      perform private.fail('product_unavailable', jsonb_build_object('product_id', r.product_id, 'name', r.name));
    end if;
    if r.expected_unit_price is not null and r.expected_unit_price <> r.price then
      v_changes := v_changes || jsonb_build_array(jsonb_build_object(
        'product_id', r.product_id, 'name', r.name, 'expected', r.expected_unit_price, 'current', r.price
      ));
    end if;
    v_subtotal := v_subtotal + r.price * r.quantity;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'product_id', r.product_id, 'medicine_id', r.medicine_id, 'name', r.name, 'strength', r.strength,
      'dosage_form', r.dosage_form, 'quantity', r.quantity, 'price', r.price
    ));
  end loop;

  if jsonb_array_length(v_changes) > 0 then
    perform private.fail('price_changed', jsonb_build_object('items', v_changes));
  end if;

  loop
    begin
      insert into public.orders (public_ref, customer_id, pharmacy_id, currency, subtotal, customer_name,
                                 contact_phone, customer_notes, pharmacy_name, pharmacy_address, pharmacy_phone)
      values (private.generate_order_ref(), v_uid, p_pharmacy_id, v_ph.currency, v_subtotal,
              coalesce(v_name, ''), v_phone, v_notes, v_ph.name,
              concat_ws('، ', nullif(btrim(v_ph.address_line), ''), nullif(btrim(v_ph.neighborhood), ''), nullif(btrim(v_ph.city), '')),
              case when v_ph.show_phone_publicly then v_ph.phone else null end)
      returning * into v_order;
      exit;
    exception when unique_violation then
      v_try := v_try + 1;
      if v_try >= 5 then
        raise exception using errcode = 'P0001', message = 'internal_error', detail = 'order_ref_collision';
      end if;
    end;
  end loop;

  for r in
    select x.product_id, x.medicine_id, x.name, x.strength, x.dosage_form, x.quantity, x.price
    from jsonb_to_recordset(v_lines) as x (
      product_id uuid, medicine_id uuid, name text, strength text, dosage_form text, quantity integer, price numeric
    )
    order by x.product_id
  loop
    v_line := v_line + 1;
    insert into public.order_items (order_id, line_no, product_id, medicine_id, medicine_name, strength,
                                    dosage_form, quantity, unit_price)
    values (v_order.id, v_line, r.product_id, r.medicine_id, r.name, r.strength, r.dosage_form, r.quantity, r.price);
  end loop;

  perform private.notify_pharmacy(p_pharmacy_id, 'order_new', 'order', v_order.id,
                                  jsonb_build_object('ref', v_order.public_ref));

  v_resp := private.order_json(v_order.id);
  perform private.idem_finish(v_uid, 'create_order', p_idempotency_key, v_resp);
  return v_resp;
end
$$;

create function public.cancel_order(p_order_id uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_owner uuid;
  v_order public.orders;
  v_reason text := private.req_text(p_reason, 'reason', 1, 300, false);
begin
  v_uid := private.assert_active_user();
  select o.customer_id into v_owner from public.orders o where o.id = p_order_id;
  if v_owner is null or v_owner <> v_uid then
    perform private.fail('not_found');
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.status not in ('pending', 'accepted', 'ready_for_pickup', 'expired') then
    perform private.fail('invalid_transition', jsonb_build_object('from', v_order.status, 'to', 'cancelled'));
  end if;

  update public.orders
  set status = 'cancelled', cancelled_at = now(), cancelled_by_role = 'customer', cancel_reason = v_reason
  where id = v_order.id;

  perform private.notify_pharmacy(v_order.pharmacy_id, 'order_cancelled', 'order', v_order.id,
                                  jsonb_build_object('ref', v_order.public_ref, 'by', 'customer'));
  return private.order_json(v_order.id);
end
$$;

-- ---------------------------------------------------------------------------
-- Pharmacy: handle the reservation
-- ---------------------------------------------------------------------------
create function public.accept_order(p_order_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pharmacy uuid;
  v_order public.orders;
  v_expires timestamptz;
begin
  perform private.assert_active_user();
  select o.pharmacy_id into v_pharmacy from public.orders o where o.id = p_order_id;
  if v_pharmacy is null then
    perform private.fail('not_found');
  end if;
  perform private.assert_member(v_pharmacy, array['owner', 'manager', 'cashier']::public.member_role[], true);

  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.status <> 'pending' then
    perform private.fail('invalid_transition', jsonb_build_object('from', v_order.status, 'to', 'accepted'));
  end if;

  v_expires := now() + make_interval(hours => private.cfg_int('reservation_hours'));

  update public.orders
  set status = 'accepted', accepted_at = now(), reservation_expires_at = v_expires
  where id = v_order.id;

  perform private.notify(v_order.customer_id, 'order_accepted', 'order', v_order.id,
                         jsonb_build_object('ref', v_order.public_ref, 'expires_at', v_expires));
  return private.order_json(v_order.id);
end
$$;

create function public.reject_order(p_order_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders;
  v_reason text := private.req_text(p_reason, 'reason', 3, 300);
begin
  perform private.assert_active_user();
  v_order := private.lock_order_for_member(
    p_order_id, array['owner', 'manager', 'cashier']::public.member_role[], true);
  if v_order.status <> 'pending' then
    perform private.fail('invalid_transition', jsonb_build_object('from', v_order.status, 'to', 'rejected'));
  end if;
  update public.orders set status = 'rejected', rejected_at = now(), reject_reason = v_reason
  where id = v_order.id;
  perform private.notify(v_order.customer_id, 'order_rejected', 'order', v_order.id,
                         jsonb_build_object('ref', v_order.public_ref, 'reason', v_reason));
  return private.order_json(v_order.id);
end
$$;

create function public.mark_order_ready(p_order_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders;
begin
  perform private.assert_active_user();
  v_order := private.lock_order_for_member(
    p_order_id, array['owner', 'manager', 'cashier']::public.member_role[], true);
  if v_order.status <> 'accepted' then
    perform private.fail('invalid_transition', jsonb_build_object('from', v_order.status, 'to', 'ready_for_pickup'));
  end if;
  if v_order.reservation_expires_at <= now() then
    perform private.fail('reservation_expired');
  end if;
  update public.orders set status = 'ready_for_pickup', ready_at = now() where id = v_order.id;
  perform private.notify(v_order.customer_id, 'order_ready', 'order', v_order.id,
                         jsonb_build_object('ref', v_order.public_ref, 'expires_at', v_order.reservation_expires_at));
  return private.order_json(v_order.id);
end
$$;

create function public.pharmacy_cancel_order(p_order_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders;
  v_reason text := private.req_text(p_reason, 'reason', 3, 300);
begin
  perform private.assert_active_user();
  v_order := private.lock_order_for_member(
    p_order_id, array['owner', 'manager', 'cashier']::public.member_role[], true);
  if v_order.status not in ('accepted', 'ready_for_pickup') then
    perform private.fail('invalid_transition', jsonb_build_object('from', v_order.status, 'to', 'cancelled'));
  end if;
  update public.orders
  set status = 'cancelled', cancelled_at = now(), cancelled_by_role = 'pharmacy', cancel_reason = v_reason
  where id = v_order.id;
  perform private.notify(v_order.customer_id, 'order_cancelled', 'order', v_order.id,
                         jsonb_build_object('ref', v_order.public_ref, 'by', 'pharmacy', 'reason', v_reason));
  return private.order_json(v_order.id);
end
$$;

-- Handover: verifies the reference, then in ONE transaction records the sale and completes the order.
-- Safe to retry.
create function public.complete_order(p_order_id uuid, p_reference text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_order public.orders;
  v_sale_id uuid;
  v_inv integer;
begin
  v_uid := private.assert_active_user();
  v_order := private.lock_order_for_member(
    p_order_id, array['owner', 'manager', 'cashier']::public.member_role[], true);

  if upper(btrim(coalesce(p_reference, ''))) <> v_order.public_ref then
    perform private.fail('reference_mismatch');
  end if;

  if v_order.status = 'completed' then
    select s.id into v_sale_id from public.sales s where s.order_id = v_order.id;
    return private.sale_json(v_sale_id);
  end if;
  if v_order.status <> 'ready_for_pickup' then
    perform private.fail('invalid_transition', jsonb_build_object('from', v_order.status, 'to', 'completed'));
  end if;
  if v_order.reservation_expires_at <= now() then
    perform private.fail('reservation_expired');
  end if;

  insert into public.pharmacy_invoice_counters as c (pharmacy_id, last_number)
  values (v_order.pharmacy_id, 1)
  on conflict (pharmacy_id) do update set last_number = c.last_number + 1
  returning c.last_number into v_inv;

  insert into public.sales (pharmacy_id, invoice_no, order_id, currency, subtotal, discount_amount, total, cashier_id)
  values (v_order.pharmacy_id, 'INV-' || lpad(v_inv::text, 6, '0'), v_order.id, v_order.currency,
          v_order.subtotal, 0, v_order.subtotal, v_uid)
  returning id into v_sale_id;

  insert into public.sale_items (sale_id, line_no, product_id, product_name, strength, quantity, unit_price)
  select v_sale_id, oi.line_no, oi.product_id, oi.medicine_name, oi.strength, oi.quantity, oi.unit_price
  from public.order_items oi where oi.order_id = v_order.id;

  update public.orders set status = 'completed', completed_at = now() where id = v_order.id;
  perform private.notify(v_order.customer_id, 'order_completed', 'order', v_order.id,
                         jsonb_build_object('ref', v_order.public_ref));
  return private.sale_json(v_sale_id);
end
$$;

-- An expired order may be put back in play by the pharmacy (it promises to prepare it again).
create function public.reactivate_order(p_order_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pharmacy uuid;
  v_order public.orders;
  v_expires timestamptz;
begin
  perform private.assert_active_user();
  select o.pharmacy_id into v_pharmacy from public.orders o where o.id = p_order_id;
  if v_pharmacy is null then
    perform private.fail('not_found');
  end if;
  perform private.assert_member(v_pharmacy, array['owner', 'manager', 'cashier']::public.member_role[], true);
  perform private.expire_pharmacy(v_pharmacy);

  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.status <> 'expired' then
    perform private.fail('invalid_transition', jsonb_build_object('from', v_order.status, 'to', 'accepted'));
  end if;

  v_expires := now() + make_interval(hours => private.cfg_int('reservation_hours'));
  update public.orders
  set status = 'accepted', accepted_at = now(), ready_at = null, reservation_expires_at = v_expires
  where id = v_order.id;

  perform private.notify(v_order.customer_id, 'order_reactivated', 'order', v_order.id,
                         jsonb_build_object('ref', v_order.public_ref, 'expires_at', v_expires));
  return private.order_json(v_order.id);
end
$$;

create function public.find_order_by_ref(p_pharmacy_id uuid, p_ref text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  perform private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner', 'manager', 'cashier']::public.member_role[], false);
  select o.id into v_id
  from public.orders o
  where o.pharmacy_id = p_pharmacy_id and o.public_ref = upper(btrim(coalesce(p_ref, '')));
  if v_id is null then
    perform private.fail('not_found');
  end if;
  return private.order_json(v_id);
end
$$;

-- Members trigger expiry for their own pharmacy (the app calls it when the orders screen opens).
create function public.expire_reservations(p_pharmacy_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner', 'manager', 'cashier']::public.member_role[], false);
  return jsonb_build_object('expired', private.expire_pharmacy(p_pharmacy_id));
end
$$;
