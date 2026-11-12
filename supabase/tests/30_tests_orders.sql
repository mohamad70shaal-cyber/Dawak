-- Reservation (order) lifecycle tests. A reservation is the pharmacy's promise to prepare the order for 24 h;
-- there are no quantities, so nothing is reserved, decremented or released anywhere.

-- Creates an order as the given customer with a fresh idempotency key.
create function tests.place_order(p_customer uuid, p_pharmacy uuid, p_items jsonb) returns jsonb
language plpgsql as $$
begin
  perform tests.act_as(p_customer);
  return public.create_order(p_pharmacy, p_items, null, null, 'k-' || gen_random_uuid()::text);
end
$$;

create function tests.t_ord_01_full_lifecycle() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  a2 uuid := tests.uid(fx, 'a2');
  o jsonb;
  oid uuid;
  ref text;
  s jsonb;
begin
  o := tests.place_order(c1, ph, tests.items(a1::text, '2', a2::text, '1'));
  oid := (o ->> 'id')::uuid;
  ref := o ->> 'public_ref';
  perform tests.eq(o ->> 'status', 'pending', 'new order is pending');
  perform tests.ok(ref ~ '^DWK-[0-9A-F]{10}$', 'public reference format: ' || ref);
  perform tests.eq((o ->> 'subtotal')::numeric, 4500.50, 'subtotal snapshot');
  perform tests.eq(jsonb_array_length(o -> 'items'), 2, 'two items');
  perform tests.eq(o ->> 'currency', 'SYP', 'currency copied from pharmacy');
  perform tests.eq(o ->> 'pharmacy_name', 'Pharmacy A', 'pharmacy name snapshot');
  perform tests.ok((o ->> 'pharmacy_address') like 'Street 1%Mazzeh%Damascus', 'pharmacy address snapshot: ' || coalesce(o ->> 'pharmacy_address', 'NULL'));
  perform tests.eq(o ->> 'pharmacy_phone', '0933111111', 'phone snapshot (pharmacy shows its phone)');

  perform tests.act_as(pa);
  perform tests.eq(tests.count($q$select 1 from public.notifications where kind = 'order_new'$q$), 1::bigint, 'pharmacy was notified');

  o := public.accept_order(oid);
  perform tests.eq(o ->> 'status', 'accepted', 'accepted');
  perform tests.ok((o ->> 'reservation_expires_at')::timestamptz between now() + interval '23 hours 59 minutes' and now() + interval '24 hours 1 minute', '24h promise window');

  o := public.mark_order_ready(oid);
  perform tests.eq(o ->> 'status', 'ready_for_pickup', 'ready');

  s := public.complete_order(oid, ref);
  perform tests.eq(s ->> 'order_id', oid::text, 'sale linked to order');
  perform tests.eq((s ->> 'total')::numeric, 4500.50, 'sale total equals order subtotal');
  perform tests.eq(s ->> 'invoice_no', 'INV-000001', 'invoice number');
  perform tests.eq(s ->> 'payment_method', 'cash', 'cash at pickup');

  -- retrying the handover is harmless
  perform tests.eq(public.complete_order(oid, ref) ->> 'id', s ->> 'id', 'second completion returns the same sale');

  perform tests.act_as(c1);
  perform tests.eq(tests.count($q$select 1 from public.notifications where kind in ('order_accepted','order_ready','order_completed')$q$), 3::bigint, 'customer notified at each step');
  perform tests.reset();
  perform tests.eq(tests.count('select 1 from public.sales'), 1::bigint, 'exactly one sale');
  perform tests.eq(tests.count(format('select 1 from public.sale_items where sale_id = %L', s ->> 'id')), 2::bigint, 'one sale item per order line');
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_02_price_snapshot_and_price_change() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  o jsonb;
  oid uuid;
begin
  perform tests.act_as(c1);
  -- the app sends the price the customer saw; a mismatch is refused with details, nothing is created
  perform tests.raises(format($q$select public.create_order(%L, %L::jsonb, NULL, NULL, 'k-price-0001')$q$, ph,
        jsonb_build_array(jsonb_build_object('product_id', a1, 'quantity', 1, 'expected_unit_price', 900))::text),
        'price_changed', 'stale price is refused');
  o := public.create_order(ph, jsonb_build_array(jsonb_build_object('product_id', a1, 'quantity', 2, 'expected_unit_price', 1000)), null, null, 'k-price-0002');
  oid := (o ->> 'id')::uuid;
  perform tests.eq((o -> 'items' -> 0 ->> 'unit_price')::numeric, 1000.00, 'order uses current price');

  -- later price rises do not change an existing order
  perform tests.act_as(pa);
  perform public.update_pharmacy_product(a1, 1500, null);
  perform public.accept_order(oid);
  perform public.mark_order_ready(oid);
  perform tests.eq((public.complete_order(oid, o ->> 'public_ref') ->> 'total')::numeric, 2000.00, 'customer pays the price agreed at order time');
  perform tests.reset();
  perform tests.eq(tests.count($q$select 1 from public.orders where status = 'pending'$q$), 0::bigint, 'nothing left pending');
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_03_create_validation_and_roles() returns void
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
  v_items text := tests.items(a1::text, '1')::text;
  o1 jsonb;
  o2 jsonb;
begin
  perform tests.act_as(c1);
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, '[]', 'k-val-00001'), 'invalid_input', 'empty cart');
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, tests.items(a1::text, '11')::text, 'k-val-00002'), 'invalid_input', 'above per-item cap of 10');
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, tests.items(b1::text, '1')::text, 'k-val-00003'), 'product_unavailable', 'product from another pharmacy');
  perform tests.act_as(pa);
  perform public.update_pharmacy_product(a1, null, false);
  perform tests.act_as(c1);
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, v_items, 'k-val-00003b'), 'product_unavailable', 'a product marked unavailable cannot be ordered');
  perform tests.act_as(pa);
  perform public.update_pharmacy_product(a1, null, true);
  perform tests.act_as(c1);
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', gen_random_uuid(), v_items, 'k-val-00004'), 'pharmacy_not_active', 'unknown pharmacy');
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,%L,NULL,%L)', ph, v_items, repeat('x', 301), 'k-val-00005'), 'invalid_input', 'notes longer than 300');
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,%L,%L)', ph, v_items, 'abc', 'k-val-00006'), 'invalid_input', 'bad phone');
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, v_items, 'x'), 'invalid_input', 'short idempotency key');
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,NULL)', ph, v_items), 'invalid_input', 'missing idempotency key');
  perform public.create_order(ph, v_items::jsonb, 'أحتاج الدواء اليوم', '0933 123 456', 'k-val-00007');
  perform tests.eq((select contact_phone from public.orders limit 1), '0933123456', 'phone normalised');

  -- unlisted / suspended pharmacies cannot receive orders
  perform tests.reset();
  perform tests.act_as(admin);
  perform public.admin_review_pharmacy(ph_b, 'suspend', 'test');
  perform tests.act_as(c1);
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph_b, tests.items(b1::text, '1')::text, 'k-val-00008'), 'pharmacy_not_active', 'suspended pharmacy');
  perform tests.reset();
  perform tests.act_as(admin);
  perform public.admin_review_pharmacy(ph_b, 'reinstate', null);

  -- only customers order
  perform tests.act_as(pa);
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, v_items, 'k-val-00009'), 'forbidden', 'pharmacist cannot create customer orders');
  perform tests.act_as(admin);
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, v_items, 'k-val-00010'), 'forbidden', 'admin cannot create customer orders');
  perform tests.act_as_anon();
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, v_items, 'k-val-00011'), '42501', 'anonymous cannot order');

  -- idempotent retry
  perform tests.act_as(c1);
  o1 := public.create_order(ph, v_items::jsonb, null, null, 'k-idem-0001');
  o2 := public.create_order(ph, v_items::jsonb, null, null, 'k-idem-0001');
  perform tests.eq(o2 ->> 'id', o1 ->> 'id', 'retry returns the same order');
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, tests.items(a1::text, '2')::text, 'k-idem-0001'), 'duplicate_request', 'same key, different content');
  perform tests.reset();
  perform tests.eq(tests.count('select 1 from public.orders'), 2::bigint, 'only two orders exist (one retried)');
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_04_limits() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  v_items text := tests.items(a1::text, '1')::text;
  o jsonb;
  i integer;
begin
  perform tests.act_as(c1);
  for i in 1..5 loop
    perform public.create_order(ph, v_items::jsonb, null, null, 'k-limit-' || i);
  end loop;
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, v_items, 'k-limit-6'), 'too_many_pending', 'sixth pending order');
  -- the limit is per customer
  perform tests.act_as(c2);
  perform public.create_order(ph, v_items::jsonb, null, null, 'k-limit-other');
  -- cancelling frees pending slots but not the hourly rate limit
  perform tests.reset();
  update public.orders set status = 'cancelled', cancelled_at = now(), cancelled_by_role = 'customer' where customer_id = c1;
  perform tests.act_as(c1);
  for i in 6..10 loop
    o := public.create_order(ph, v_items::jsonb, null, null, 'k-limit-' || i);
    perform public.cancel_order((o ->> 'id')::uuid, null);
  end loop;
  perform tests.raises(format('select public.create_order(%L,%L::jsonb,NULL,NULL,%L)', ph, v_items, 'k-limit-11'), 'rate_limited', 'eleventh order within an hour');
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_05_state_machine_rejects_invalid_transitions() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  o jsonb;
  oid uuid;
  ref text;
begin
  o := tests.place_order(c1, ph, tests.items(a1::text, '1'));
  oid := (o ->> 'id')::uuid;
  ref := o ->> 'public_ref';

  perform tests.act_as(pa);
  perform tests.raises(format('select public.mark_order_ready(%L)', oid), 'invalid_transition', 'pending -> ready');
  perform tests.raises(format('select public.complete_order(%L,%L)', oid, ref), 'invalid_transition', 'pending -> completed');
  perform tests.raises(format('select public.pharmacy_cancel_order(%L,%L)', oid, 'سبب'), 'invalid_transition', 'pending is rejected, not pharmacy-cancelled');
  perform tests.raises(format('select public.reactivate_order(%L)', oid), 'invalid_transition', 'only expired orders reactivate');
  perform tests.raises(format('select public.reject_order(%L,%L)', oid, 'x'), 'invalid_input', 'reject reason too short');
  perform tests.raises(format('select public.reject_order(%L,NULL)', oid), 'invalid_input', 'reject reason required');

  perform public.accept_order(oid);
  perform tests.raises(format('select public.accept_order(%L)', oid), 'invalid_transition', 'accept twice');
  perform tests.raises(format('select public.reject_order(%L,%L)', oid, 'لا يوجد'), 'invalid_transition', 'accepted cannot be rejected');
  perform public.mark_order_ready(oid);
  perform tests.raises(format('select public.mark_order_ready(%L)', oid), 'invalid_transition', 'ready twice');
  perform public.complete_order(oid, ref);

  -- completed is terminal for everybody
  perform tests.raises(format('select public.pharmacy_cancel_order(%L,%L)', oid, 'سبب'), 'invalid_transition', 'completed cannot be cancelled by pharmacy');
  perform tests.raises(format('select public.reject_order(%L,%L)', oid, 'سبب'), 'invalid_transition', 'completed cannot be rejected');
  perform tests.act_as(c1);
  perform tests.raises(format('select public.cancel_order(%L,NULL)', oid), 'invalid_transition', 'completed cannot be cancelled by customer');

  -- rejected is terminal too
  o := tests.place_order(c1, ph, tests.items(a1::text, '1'));
  perform tests.act_as(pa);
  o := public.reject_order((o ->> 'id')::uuid, 'غير متوفر حالياً');
  perform tests.eq(o ->> 'status', 'rejected', 'rejected');
  perform tests.eq(o ->> 'reject_reason', 'غير متوفر حالياً', 'reason stored');
  perform tests.raises(format('select public.accept_order(%L)', o ->> 'id'), 'invalid_transition', 'rejected cannot be accepted');
  perform tests.act_as(c1);
  perform tests.raises(format('select public.cancel_order(%L,NULL)', o ->> 'id'), 'invalid_transition', 'rejected cannot be cancelled');

  -- the database also refuses terminal-state edits that bypass the RPCs
  perform tests.reset();
  perform tests.raises(format($q$update public.orders set status = 'pending' where id = %L$q$, o ->> 'id'), 'invalid_transition', 'trigger blocks leaving a terminal state');
  perform tests.raises(format($q$update public.orders set subtotal = 1 where id = %L$q$, oid), 'forbidden', 'trigger blocks identity edits');
  -- ...and illegal jumps between live states, even for a superuser-level direct update
  o := tests.place_order(c1, ph, tests.items(a1::text, '1'));
  perform tests.reset();
  perform tests.raises(format($q$update public.orders set status = 'completed' where id = %L$q$, o ->> 'id'), 'invalid_transition', 'trigger blocks pending -> completed');
  perform tests.raises(format($q$update public.orders set status = 'ready_for_pickup' where id = %L$q$, o ->> 'id'), 'invalid_transition', 'trigger blocks pending -> ready');
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_06_cancellation_by_each_side() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  o jsonb;
  oid uuid;
begin
  -- pending: cancel by customer
  o := tests.place_order(c1, ph, tests.items(a1::text, '3'));
  o := public.cancel_order((o ->> 'id')::uuid, 'غيّرت رأيي');
  perform tests.eq(o ->> 'status', 'cancelled', 'customer cancelled pending');
  perform tests.eq(o ->> 'cancelled_by_role', 'customer', 'cancelled by customer');

  -- accepted: customer cancel
  o := tests.place_order(c1, ph, tests.items(a1::text, '3'));
  oid := (o ->> 'id')::uuid;
  perform tests.act_as(pa);
  perform public.accept_order(oid);
  perform tests.act_as(c1);
  perform public.cancel_order(oid, null);
  perform tests.raises(format('select public.cancel_order(%L,NULL)', oid), 'invalid_transition', 'second cancel is refused');
  perform tests.act_as(pa);
  perform tests.eq(tests.count($q$select 1 from public.notifications where kind = 'order_cancelled'$q$), 2::bigint, 'pharmacy told about both customer cancellations');

  -- ready: pharmacy cancel with reason notifies the customer
  o := tests.place_order(c1, ph, tests.items(a1::text, '4'));
  oid := (o ->> 'id')::uuid;
  perform tests.act_as(pa);
  perform public.accept_order(oid);
  perform public.mark_order_ready(oid);
  perform tests.raises(format('select public.pharmacy_cancel_order(%L,NULL)', oid), 'invalid_input', 'pharmacy must give a reason');
  o := public.pharmacy_cancel_order(oid, 'نفد الدواء');
  perform tests.eq(o ->> 'cancelled_by_role', 'pharmacy', 'cancelled by pharmacy');
  perform tests.act_as(c1);
  perform tests.eq(tests.count($q$select 1 from public.notifications where kind = 'order_cancelled'$q$), 1::bigint, 'customer told about pharmacy cancellation');

  -- another customer cannot cancel it
  o := tests.place_order(c1, ph, tests.items(a1::text, '1'));
  perform tests.act_as(c2);
  perform tests.raises(format('select public.cancel_order(%L,NULL)', o ->> 'id'), 'not_found', 'cannot cancel someone else''s order');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_07_acceptance_is_a_promise_not_stock() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  a2 uuid := tests.uid(fx, 'a2');
  o1 jsonb;
  o2 jsonb;
  o3 jsonb;
begin
  -- Two customers each ask for 9 of the same medicine: the pharmacy decides, nothing is counted.
  o1 := tests.place_order(c1, ph, tests.items(a1::text, '9'));
  o2 := tests.place_order(c2, ph, tests.items(a1::text, '9'));
  perform tests.act_as(pa);
  perform public.accept_order((o1 ->> 'id')::uuid);
  perform public.accept_order((o2 ->> 'id')::uuid);
  perform tests.eq(tests.count($q$select 1 from public.orders where status = 'accepted'$q$), 2::bigint, 'both orders accepted');

  -- A product marked unavailable after the order was placed does not block the pharmacy's decision.
  o3 := tests.place_order(c1, ph, tests.items(a2::text, '1'));
  perform tests.act_as(pa);
  perform public.update_pharmacy_product(a2, null, false);
  perform tests.eq(public.accept_order((o3 ->> 'id')::uuid) ->> 'status', 'accepted', 'pharmacist may still accept');

  -- ...but the pharmacy can refuse with a reason instead.
  o3 := tests.place_order(c1, ph, tests.items(a1::text, '1'));
  perform tests.act_as(pa);
  perform tests.eq(public.reject_order((o3 ->> 'id')::uuid, 'غير متوفر الآن') ->> 'status', 'rejected', 'or reject it');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_08_expiry_and_reactivation() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  c1 uuid := tests.uid(fx, 'c1');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  o jsonb;
  oid uuid;
  ref text;
  v jsonb;
begin
  o := tests.place_order(c1, ph, tests.items(a1::text, '4'));
  oid := (o ->> 'id')::uuid;
  ref := o ->> 'public_ref';
  perform tests.act_as(pa);
  perform public.accept_order(oid);
  perform public.mark_order_ready(oid);

  -- time passes (the only direct edit in the suite: simulating the clock)
  perform tests.reset();
  update public.orders set reservation_expires_at = now() - interval '1 minute' where id = oid;
  perform tests.act_as(pa);

  -- the window has passed but nobody has swept yet: handover must still be refused
  perform tests.raises(format('select public.complete_order(%L,%L)', oid, ref), 'reservation_expired', 'cannot complete after the window');

  v := public.expire_reservations(ph);
  perform tests.eq((v ->> 'expired')::int, 1, 'one order expired');
  perform tests.eq((select status::text from public.orders where id = oid), 'expired', 'order expired');
  perform tests.eq((public.expire_reservations(ph) ->> 'expired')::int, 0, 'sweeping again changes nothing');
  perform tests.raises(format('select public.complete_order(%L,%L)', oid, ref), 'invalid_transition', 'expired order cannot be completed');
  perform tests.raises(format('select public.mark_order_ready(%L)', oid), 'invalid_transition', 'expired order cannot be marked ready');

  -- reactivation puts it back with a fresh window
  o := public.reactivate_order(oid);
  perform tests.eq(o ->> 'status', 'accepted', 'reactivated');
  perform tests.ok((o ->> 'reservation_expires_at')::timestamptz > now() + interval '23 hours', 'new 24h window');
  perform tests.raises(format('select public.reactivate_order(%L)', oid), 'invalid_transition', 'only expired orders reactivate');
  perform public.mark_order_ready(oid);
  perform public.complete_order(oid, ref);

  -- an order that lapsed while the pharmacy was not looking is expired by reactivation's own sweep
  o := tests.place_order(c1, ph, tests.items(a1::text, '5'));
  oid := (o ->> 'id')::uuid;
  perform tests.act_as(pa);
  perform public.accept_order(oid);
  perform tests.reset();
  update public.orders set reservation_expires_at = now() - interval '1 minute' where id = oid;
  perform tests.act_as(pa);
  perform tests.eq(public.reactivate_order(oid) ->> 'status', 'accepted', 'a lapsed order can be reactivated directly');

  -- the customer may still cancel an expired order
  perform tests.reset();
  update public.orders set status = 'expired', expired_at = now() where id = oid;
  perform tests.act_as(c1);
  perform tests.eq(public.cancel_order(oid, null) ->> 'status', 'cancelled', 'customer cancels expired order');

  -- the cron entry point sweeps every pharmacy
  o := tests.place_order(c1, ph, tests.items(a1::text, '1'));
  perform tests.act_as(pa);
  perform public.accept_order((o ->> 'id')::uuid);
  perform tests.reset();
  update public.orders set reservation_expires_at = now() - interval '1 minute' where id = (o ->> 'id')::uuid;
  perform tests.eq(private.expire_all_reservations(), 1, 'cron sweep expires due orders');
  perform tests.eq(private.expire_all_reservations(), 0, 'cron sweep is idempotent');
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_09_handover_checks() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  o jsonb;
  oid uuid;
  ref text;
begin
  o := tests.place_order(c1, ph, tests.items(a1::text, '2'));
  oid := (o ->> 'id')::uuid;
  ref := o ->> 'public_ref';
  perform tests.act_as(pa);
  perform public.accept_order(oid);
  perform public.mark_order_ready(oid);

  perform tests.raises(format('select public.complete_order(%L,%L)', oid, 'DWK-0000000000'), 'reference_mismatch', 'wrong reference');
  perform tests.raises(format('select public.complete_order(%L,NULL)', oid), 'reference_mismatch', 'missing reference');
  perform tests.eq((select status::text from public.orders where id = oid), 'ready_for_pickup', 'failed handover changes nothing');
  perform tests.eq(tests.count('select 1 from public.sales'), 0::bigint, 'failed handover records no sale');

  perform tests.act_as(pb);
  perform tests.raises(format('select public.complete_order(%L,%L)', oid, ref), 'forbidden', 'other pharmacy cannot complete');
  perform tests.raises(format('select public.mark_order_ready(%L)', oid), 'forbidden', 'other pharmacy cannot touch');
  perform tests.raises(format('select public.accept_order(%L)', oid), 'forbidden', 'other pharmacy cannot accept');
  perform tests.act_as(c1);
  perform tests.raises(format('select public.complete_order(%L,%L)', oid, ref), 'forbidden', 'customer cannot complete own order');
  perform tests.raises(format('select public.accept_order(%L)', oid), 'forbidden', 'customer cannot accept');

  perform tests.act_as(pa);
  perform tests.eq(public.complete_order(oid, '  ' || lower(ref) || ' ') ->> 'order_id', oid::text, 'reference is case/space tolerant');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_10_visibility_and_direct_writes() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  ph uuid := tests.uid(fx, 'ph_a');
  ph_b uuid := tests.uid(fx, 'ph_b');
  a1 uuid := tests.uid(fx, 'a1');
  o jsonb;
  oid uuid;
begin
  o := tests.place_order(c1, ph, tests.items(a1::text, '2'));
  oid := (o ->> 'id')::uuid;
  perform tests.act_as(pa);
  perform public.accept_order(oid);

  perform tests.act_as(c1);
  perform tests.eq(tests.count('select 1 from public.orders'), 1::bigint, 'customer sees own order');
  perform tests.eq(tests.count('select 1 from public.order_items'), 1::bigint, 'customer sees own order items');
  perform tests.act_as(c2);
  perform tests.eq(tests.count('select 1 from public.orders'), 0::bigint, 'another customer sees nothing');
  perform tests.eq(tests.count('select 1 from public.order_items'), 0::bigint, 'nor items');
  perform tests.act_as(pa);
  perform tests.eq(tests.count('select 1 from public.orders'), 1::bigint, 'pharmacy sees its orders');
  perform tests.act_as(pb);
  perform tests.eq(tests.count('select 1 from public.orders'), 0::bigint, 'other pharmacy sees nothing');

  -- look-up by reference
  perform tests.act_as(pa);
  perform tests.eq(public.find_order_by_ref(ph, lower(o ->> 'public_ref')) ->> 'id', oid::text, 'find by ref (case-insensitive)');
  perform tests.raises(format('select public.find_order_by_ref(%L,%L)', ph, 'DWK-NOPE000000'), 'not_found', 'unknown reference');
  perform tests.act_as(pb);
  perform tests.raises(format('select public.find_order_by_ref(%L,%L)', ph, o ->> 'public_ref'), 'forbidden', 'other pharmacy cannot look up');
  perform tests.raises(format('select public.find_order_by_ref(%L,%L)', ph_b, o ->> 'public_ref'), 'not_found', 'reference is scoped to the pharmacy');

  -- nobody can write orders directly
  perform tests.act_as(c1);
  perform tests.raises(format($q$update public.orders set status = 'cancelled' where id = %L$q$, oid), '42501', 'customer cannot update orders directly');
  perform tests.raises(format($q$delete from public.orders where id = %L$q$, oid), '42501', 'customer cannot delete orders');
  perform tests.raises(format($q$insert into public.orders (public_ref, customer_id, pharmacy_id, currency, subtotal) values ('DWK-X', %L, %L, 'SYP', 0)$q$, c1, ph), '42501', 'customer cannot insert orders');
  perform tests.act_as(pa);
  perform tests.raises(format($q$update public.orders set status = 'completed' where id = %L$q$, oid), '42501', 'pharmacist cannot update orders directly');
  perform tests.raises(format($q$update public.order_items set quantity = 1 where order_id = %L$q$, oid), '42501', 'nobody edits items');
  perform tests.reset();
  perform tests.check_invariants();
end
$$;

create function tests.t_ord_11_notifications_are_private() returns void
language plpgsql as $$
declare
  fx jsonb := tests.fx();
  pa uuid := tests.uid(fx, 'pa');
  pb uuid := tests.uid(fx, 'pb');
  c1 uuid := tests.uid(fx, 'c1');
  c2 uuid := tests.uid(fx, 'c2');
  ph uuid := tests.uid(fx, 'ph_a');
  a1 uuid := tests.uid(fx, 'a1');
  v_id uuid;
begin
  perform tests.place_order(c1, ph, tests.items(a1::text, '1'));
  perform tests.act_as(pa);
  perform tests.eq(tests.count($q$select 1 from public.notifications where kind = 'order_new'$q$), 1::bigint, 'pharmacy owner has the new-order notification');
  v_id := (select id from public.notifications where kind = 'order_new');
  perform tests.eq(tests.count($q$select 1 from public.notifications where kind = 'order_new' and read_at is null$q$), 1::bigint, 'unread');
  perform tests.eq(tests.affected(format('update public.notifications set read_at = now() where id = %L', v_id)), 1::bigint, 'owner marks it read');
  perform tests.raises(format($q$update public.notifications set kind = 'x' where id = %L$q$, v_id), '42501', 'cannot edit other columns');
  perform tests.raises('delete from public.notifications', '42501', 'cannot delete');
  perform tests.raises(format($q$insert into public.notifications (user_id, kind) values (%L, 'spam')$q$, pa), '42501', 'cannot forge notifications');
  perform tests.act_as(pb);
  perform tests.eq(tests.count($q$select 1 from public.notifications where kind = 'order_new'$q$), 0::bigint, 'other pharmacy sees none of them');
  perform tests.eq(tests.affected(format('update public.notifications set read_at = now() where id = %L', v_id)), 0::bigint, 'cannot touch another user''s notification');
  perform tests.act_as(c2);
  perform tests.eq(tests.count($q$select 1 from public.notifications where kind = 'order_new'$q$), 0::bigint, 'unrelated customer sees none');
end
$$;
