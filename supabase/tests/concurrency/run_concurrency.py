#!/usr/bin/env python3
"""Concurrency tests: real parallel PostgreSQL sessions racing on the same rows.

    PGHOST=... PGPORT=... PGUSER=postgres python3 supabase/tests/concurrency/run_concurrency.py [iterations] [scenario-filter]

Each worker is a separate psql process that waits for a common start instant, becomes the `authenticated`
role with a given JWT subject (like PostgREST), and calls one RPC. Afterwards the committed state is checked:
no lost updates, one sale per order, unique gap-free invoice numbers, request/target rules (cap, radius,
a single "found" notification, open-request limit) and no deadlocks.
Requires a superuser connection. Uses the database $CONC_DB (default dawak_conc), recreated on every run.
"""
import json, os, pathlib, re, subprocess, sys, time, uuid
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parents[3]
DB = os.environ.get("CONC_DB", "dawak_conc")
ENV = {**os.environ, "PGCLIENTENCODING": "UTF8"}


def psql(sql, db=DB, user_sub=None, at=None, file=None):
    """Runs SQL; returns (ok, stdout, error_code, stderr)."""
    parts = []
    if at is not None:
        parts.append(f"select pg_sleep(greatest(0, {at} - extract(epoch from clock_timestamp())))")
    if user_sub:
        parts.append(f"select set_config('request.jwt.claim.sub', '{user_sub}', false)")
        parts.append("select set_config('request.jwt.claim.role', 'authenticated', false)")
        parts.append("set role authenticated")
    parts.append(sql)
    args = ["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-d", db]
    args += ["-f", str(file)] if file else ["-c", ";\n".join(parts)]
    r = subprocess.run(args, capture_output=True, text=True, env=ENV)
    code = None
    m = re.search(r"ERROR:\s+(\S+)", r.stderr)
    if m:
        code = m.group(1)
        if code in ("canceling", "deadlock") or "deadlock detected" in r.stderr:
            code = "DEADLOCK"
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    return r.returncode == 0, (lines[-1] if lines else ""), code, r.stderr


def setup_db():
    psql("drop database if exists " + DB, db="postgres")
    psql("create database " + DB, db="postgres")
    files = [ROOT / "supabase/tests/00_supabase_stub.sql", *sorted((ROOT / "supabase/migrations").glob("*.sql")),
             ROOT / "supabase/tests/01_helpers.sql"]
    for f in files:
        ok, _, _, err = psql("", file=f)
        if not ok:
            sys.exit(f"cannot load {f.name}: {err[:300]}")


_counter = [0]


def fixture():
    """A fresh fixture whose two pharmacies sit in their own part of the map, so that fixtures of earlier
    iterations never become targets of this iteration's availability requests."""
    tag = uuid.uuid4().hex[:8]
    ok, out, _, err = psql(f"select tests.fx('-{tag}')")
    if not ok:
        sys.exit("fixture failed: " + err[:300])
    fx = json.loads(out)
    _counter[0] += 1
    fx["lon"] = round(36.28 + 0.3 * _counter[0], 4)
    q(f"update public.pharmacies set longitude = {fx['lon']} where id in ('{fx['ph_a']}', '{fx['ph_b']}')")
    return fx


def q(sql):
    ok, out, _, err = psql(sql)
    if not ok:
        raise RuntimeError(err)
    return out


def race(calls):
    """calls: list of (user_uuid | None, sql). All start at the same instant. Returns [(ok, last_stdout, code)]."""
    at = time.time() + 1.2 + 0.03 * len(calls)
    with ThreadPoolExecutor(max_workers=len(calls)) as ex:
        futs = [ex.submit(psql, sql, DB, sub, at) for sub, sql in calls]
        return [(f.result()[0], f.result()[1], f.result()[2]) for f in futs]


def place_order(fx, customer, pharmacy, items):
    key = "k-" + uuid.uuid4().hex
    ok, out, code, err = psql(f"select public.create_order('{pharmacy}', '{json.dumps(items)}'::jsonb, null, null, '{key}')", user_sub=fx[customer])
    if not ok:
        raise RuntimeError(f"create_order failed: {code} {err[:200]}")
    return json.loads(out)


def items(*pairs):
    return [{"product_id": p, "quantity": n} for p, n in pairs]


def step(fx, who, sql):
    ok, out, code, err = psql(sql, user_sub=fx[who])
    if not ok:
        raise RuntimeError(f"{sql[:60]} failed: {code} {err[:200]}")
    return out


def ask_sql(fx, medicine, key=None, lat=33.5110, lon=None):
    key = key or "ask-" + uuid.uuid4().hex
    return f"select public.create_availability_request('{medicine}', {lat}, {lon if lon is not None else fx['lon']}, '{key}')"


def ask(fx, who, medicine, **kw):
    return json.loads(step(fx, who, ask_sql(fx, medicine, **kw)))


def invariants():
    bad = q("""select count(*) from (select order_id from public.sales where order_id is not null group by order_id having count(*) > 1) x""")
    assert bad == "0", "an order produced more than one sale"
    bad = q("""select count(*) from (select pharmacy_id, invoice_no from public.sales group by 1, 2 having count(*) > 1) x""")
    assert bad == "0", "duplicate invoice numbers"
    bad = q("""select count(*) from public.sales s
               where s.total <> s.subtotal - s.discount_amount
                  or s.subtotal <> coalesce((select sum(si.line_total) from public.sale_items si where si.sale_id = s.id), 0)""")
    assert bad == "0", "sale totals disagree with their items"
    bad = q("""select count(*) from public.availability_requests r
               where (select count(*) from public.availability_targets t where t.request_id = r.id) > private.cfg_int('max_request_targets')""")
    assert bad == "0", "a request exceeded the target cap"
    bad = q("""select count(*) from public.availability_targets t join public.availability_requests r on r.id = t.request_id
               where t.step > r.step or t.distance_km > private.request_radius_km(t.step) + 0.01""")
    assert bad == "0", "a target lies outside the radius of its step"
    bad = q("""select count(*) from (select user_id, entity_id from public.notifications
                                    where kind = 'availability_request' group by 1, 2 having count(*) > 1) x""")
    assert bad == "0", "a pharmacy member was notified twice about one request"
    bad = q("""select count(*) from (select user_id, entity_id from public.notifications
                                    where kind = 'availability_found' group by 1, 2 having count(*) > 1) x""")
    assert bad == "0", "the customer was told twice that somebody is available"
    bad = q("""select count(*) from (select customer_id from public.availability_requests
                                    where status = 'open' and expires_at > now() group by 1
                                    having count(*) > private.cfg_int('max_open_requests')) x""")
    assert bad == "0", "a customer holds more open requests than allowed"
    bad = q("""select count(*) from public.availability_targets
               where (answer is null) <> (answered_at is null) or (answer = 'available') <> (price is not null)""")
    assert bad == "0", "an answer is half-recorded"


def codes(results):
    return sorted([("OK" if ok else code) for ok, _, code in results])


# ---------------------------------------------------------------------------- scenarios: orders and sales
def s1_parallel_acceptances_never_contend(fx):
    """No stock any more: two customers ask for the same medicine, the pharmacy accepts both at once -> both succeed."""
    a1, ph = fx["a1"], fx["ph_a"]
    o1 = place_order(fx, "c1", ph, items((a1, 6)))
    o2 = place_order(fx, "c2", ph, items((a1, 6)))
    res = race([(fx["pa"], f"select public.accept_order('{o['id']}')") for o in (o1, o2)])
    assert codes(res) == ["OK", "OK"], codes(res)
    assert q(f"select count(*) from public.orders where status = 'accepted' and pharmacy_id = '{ph}'") == "2"


def s2_double_accept_same_order(fx):
    a1, ph = fx["a1"], fx["ph_a"]
    o = place_order(fx, "c1", ph, items((a1, 4)))
    res = race([(fx["pa"], f"select public.accept_order('{o['id']}')")] * 3)
    assert codes(res) == ["OK", "invalid_transition", "invalid_transition"], codes(res)
    assert q(f"select status from public.orders where id = '{o['id']}'") == "accepted"


def s3_double_handover(fx):
    a1, ph = fx["a1"], fx["ph_a"]
    o = place_order(fx, "c1", ph, items((a1, 3)))
    step(fx, "pa", f"select public.accept_order('{o['id']}')")
    step(fx, "pa", f"select public.mark_order_ready('{o['id']}')")
    res = race([(fx["pa"], f"select public.complete_order('{o['id']}', '{o['public_ref']}')")] * 4)
    assert all(ok for ok, _, _ in res), codes(res)
    sale_ids = {json.loads(out)["id"] for _, out, _ in res}
    assert len(sale_ids) == 1, f"handover produced {len(sale_ids)} different sales"
    assert q(f"select count(*) from public.sales where order_id = '{o['id']}'") == "1"
    assert q(f"select count(*) from public.sale_items where sale_id = '{next(iter(sale_ids))}'") == "1"


def s4_cancel_versus_handover(fx):
    a1, ph = fx["a1"], fx["ph_a"]
    o = place_order(fx, "c1", ph, items((a1, 3)))
    step(fx, "pa", f"select public.accept_order('{o['id']}')")
    step(fx, "pa", f"select public.mark_order_ready('{o['id']}')")
    res = race([(fx["c1"], f"select public.cancel_order('{o['id']}', null)"),
                (fx["pa"], f"select public.complete_order('{o['id']}', '{o['public_ref']}')")])
    status = q(f"select status from public.orders where id = '{o['id']}'")
    assert status in ("cancelled", "completed"), status
    sales = q(f"select count(*) from public.sales where order_id = '{o['id']}'")
    assert sales == ("1" if status == "completed" else "0"), (status, sales)
    assert codes(res) == ["OK", "invalid_transition"], codes(res)


def s5_parallel_walk_in_sales(fx):
    """Fifteen walk-in sales at the same moment: all succeed, invoice numbers are unique and gap-free."""
    a1, ph = fx["a1"], fx["ph_a"]
    calls = [(fx["pa"], f"select public.create_pos_sale('{ph}', '{json.dumps(items((a1, 1)))}'::jsonb, 0, 'pos-{uuid.uuid4().hex}')") for _ in range(15)]
    res = race(calls)
    assert codes(res) == ["OK"] * 15, codes(res)
    assert q(f"select count(*) from public.sales where pharmacy_id = '{ph}'") == "15"
    assert q(f"select count(distinct invoice_no) from public.sales where pharmacy_id = '{ph}'") == "15", "invoice numbers must be unique"
    assert q(f"select max(substr(invoice_no, 5)::int) from public.sales where pharmacy_id = '{ph}'") == "15", "gap in invoice numbers"


def s6_opposite_line_order_no_deadlock(fx):
    """Carts listing the same two products in opposite order must not deadlock."""
    a1, a2, ph = fx["a1"], fx["a2"], fx["ph_a"]
    calls = []
    for i in range(8):
        pairs = ((a1, 1), (a2, 1)) if i % 2 == 0 else ((a2, 1), (a1, 1))
        calls.append((fx["pa"], f"select public.create_pos_sale('{ph}', '{json.dumps(items(*pairs))}'::jsonb, 0, 'pos-{uuid.uuid4().hex}')"))
    res = race(calls)
    assert codes(res) == ["OK"] * 8, codes(res)


def s7_same_idempotency_key(fx):
    a1, ph = fx["a1"], fx["ph_a"]
    key = "same-key-" + uuid.uuid4().hex
    sql = f"select public.create_pos_sale('{ph}', '{json.dumps(items((a1, 2)))}'::jsonb, 0, '{key}')"
    res = race([(fx["pa"], sql)] * 6)
    assert all(ok for ok, _, _ in res), codes(res)
    assert len({json.loads(out)["id"] for _, out, _ in res}) == 1, "retries must return the same sale"
    assert q(f"select count(*) from public.sales where pharmacy_id = '{ph}'") == "1"


def s8_same_order_key_in_parallel(fx):
    a1, ph = fx["a1"], fx["ph_a"]
    key = "ord-key-" + uuid.uuid4().hex
    sql = f"select public.create_order('{ph}', '{json.dumps(items((a1, 1)))}'::jsonb, null, null, '{key}')"
    res = race([(fx["c1"], sql)] * 5)
    assert all(ok for ok, _, _ in res), codes(res)
    assert len({json.loads(out)["id"] for _, out, _ in res}) == 1
    assert q(f"select count(*) from public.orders where customer_id = '{fx['c1']}'") == "1"


def s9_pending_limit_under_parallel_creates(fx):
    """A customer firing 9 different orders at once must not exceed the pending-order cap (5)."""
    a1, ph = fx["a1"], fx["ph_a"]
    calls = [(fx["c1"], f"select public.create_order('{ph}', '{json.dumps(items((a1, 1)))}'::jsonb, null, null, 'par-{uuid.uuid4().hex}')") for _ in range(9)]
    res = race(calls)
    c = codes(res)
    assert "DEADLOCK" not in c, c
    pending = int(q(f"select count(*) from public.orders where customer_id = '{fx['c1']}' and status = 'pending'"))
    assert pending <= 5, f"{pending} pending orders exist (cap is 5): {c}"


def s10_sweeper_versus_cancel_and_accept(fx):
    """Expiry sweep racing with cancel and with a fresh acceptance on the same pharmacy."""
    a1, ph = fx["a1"], fx["ph_a"]
    o1 = place_order(fx, "c1", ph, items((a1, 4)))
    step(fx, "pa", f"select public.accept_order('{o1['id']}')")
    o2 = place_order(fx, "c2", ph, items((a1, 5)))
    q(f"update public.orders set reservation_expires_at = now() - interval '1 minute' where id = '{o1['id']}'")
    res = race([(fx["c1"], f"select public.cancel_order('{o1['id']}', null)"),
                (fx["pa"], f"select public.expire_reservations('{ph}')"),
                (fx["pa"], f"select public.accept_order('{o2['id']}')")])
    c = codes(res)
    assert "DEADLOCK" not in c, c
    assert q(f"select status from public.orders where id = '{o1['id']}'") in ("cancelled", "expired")
    assert q(f"select status from public.orders where id = '{o2['id']}'") == "accepted", "accepting is independent of the other order"


# ---------------------------------------------------------------------------- scenarios: availability requests
def s11_same_request_key_in_parallel(fx):
    """A double tap / network retry: six identical calls -> one request, one notification per pharmacy member."""
    key = "ask-same-" + uuid.uuid4().hex
    res = race([(fx["c1"], ask_sql(fx, fx["m1"], key))] * 6)
    assert all(ok for ok, _, _ in res), codes(res)
    ids = {json.loads(out)["id"] for _, out, _ in res}
    assert len(ids) == 1, f"{len(ids)} different requests for one key"
    rid = next(iter(ids))
    assert q(f"select count(*) from public.availability_targets where request_id = '{rid}'") == "2"
    assert q(f"select count(*) from public.notifications where entity_id = '{rid}' and kind = 'availability_request'") == "2"


def s12_different_requests_in_parallel_respect_the_open_cap(fx):
    """Six requests from one customer at six different spots at once: exactly three are allowed (open cap)."""
    calls = [(fx["c1"], ask_sql(fx, fx["m1"], lat=round(33.5110 + 0.02 * i, 4))) for i in range(6)]
    res = race(calls)
    c = codes(res)
    assert "DEADLOCK" not in c, c
    assert c == ["OK", "OK", "OK", "too_many_requests", "too_many_requests", "too_many_requests"], c
    assert q(f"select count(*) from public.availability_requests where customer_id = '{fx['c1']}'") == "3"


def s13_two_pharmacies_answer_available_together(fx):
    """Both pharmacies say 'available' at the same instant while the customer polls and widens: no deadlock,
    both answers kept, the customer is told only once."""
    req = ask(fx, "c1", fx["m1"])
    rid = req["id"]
    res = race([(fx["pa"], f"select public.answer_availability_request('{fx['ph_a']}', '{rid}', true, 1200)"),
                (fx["pb"], f"select public.answer_availability_request('{fx['ph_b']}', '{rid}', true, 1300)"),
                (fx["c1"], f"select public.get_availability_request('{rid}')"),
                (fx["c1"], f"select public.expand_availability_request('{rid}')")])
    c = codes(res)
    assert "DEADLOCK" not in c, c
    assert c == ["OK"] * 4, c
    assert q(f"select count(*) from public.availability_targets where request_id = '{rid}' and answer = 'available'") == "2"
    assert q(f"select count(*) from public.notifications where entity_id = '{rid}' and kind = 'availability_found'") == "1", \
        "the first-offer notification must be sent exactly once"
    offers = json.loads(step(fx, "c1", f"select public.get_availability_request('{rid}')"))["offers"]
    assert len(offers) == 2, offers
    assert q(f"select price from public.pharmacy_products where id = '{fx['a1']}'") == "1200.00"
    assert q(f"select price from public.pharmacy_products where id = '{fx['b1']}'") == "1300.00"


def s14_answer_versus_close(fx):
    """A pharmacy answers while the customer closes the request: either order is fine, the end state is consistent."""
    req = ask(fx, "c1", fx["m1"])
    rid = req["id"]
    res = race([(fx["pa"], f"select public.answer_availability_request('{fx['ph_a']}', '{rid}', true, 1200)"),
                (fx["c1"], f"select public.close_availability_request('{rid}')")])
    c = codes(res)
    assert c in (["OK", "OK"], ["OK", "request_closed"]), c
    assert q(f"select status from public.availability_requests where id = '{rid}'") == "closed"


def s15_parallel_manual_expansion(fx):
    """Three 'search further' taps at once walk step 1 -> 2 -> 3 -> 4 (radius 1 -> 3 -> 5 -> 10 km) exactly one step each; a fourth is refused."""
    rid = ask(fx, "c1", fx["m1"])["id"]
    res = race([(fx["c1"], f"select public.expand_availability_request('{rid}')")] * 4)
    c = codes(res)
    assert "DEADLOCK" not in c, c
    assert c == ["OK", "OK", "OK", "invalid_transition"], c
    assert q(f"select step from public.availability_requests where id = '{rid}'") == "4"


def s16_sweeper_versus_polling_and_answers(fx):
    """pg_cron's sweeper racing with the customer's polling and a pharmacy's answer."""
    rid = ask(fx, "c1", fx["m1"])["id"]
    q(f"update public.availability_requests set last_expanded_at = now() - interval '5 minutes' where id = '{rid}'")
    res = race([(None, "select private.advance_all_availability_requests()"),
                (fx["c1"], f"select public.get_availability_request('{rid}')"),
                (fx["pa"], f"select public.answer_availability_request('{fx['ph_a']}', '{rid}', false)"),
                (fx["c1"], f"select public.get_availability_request('{rid}')")])
    c = codes(res)
    assert "DEADLOCK" not in c, c
    assert c == ["OK"] * 4, c
    step_now = int(q(f"select step from public.availability_requests where id = '{rid}'"))
    assert 2 <= step_now <= 4, step_now


SCENARIOS = [s1_parallel_acceptances_never_contend, s2_double_accept_same_order, s3_double_handover,
             s4_cancel_versus_handover, s5_parallel_walk_in_sales, s6_opposite_line_order_no_deadlock,
             s7_same_idempotency_key, s8_same_order_key_in_parallel, s9_pending_limit_under_parallel_creates,
             s10_sweeper_versus_cancel_and_accept,
             s11_same_request_key_in_parallel, s12_different_requests_in_parallel_respect_the_open_cap,
             s13_two_pharmacies_answer_available_together, s14_answer_versus_close, s15_parallel_manual_expansion,
             s16_sweeper_versus_polling_and_answers]


def main():
    iterations = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    flt = sys.argv[2] if len(sys.argv) > 2 else ""
    setup_db()
    failures = 0
    for sc in SCENARIOS:
        if flt and flt not in sc.__name__:
            continue
        bad = []
        for i in range(iterations):
            try:
                fx = fixture()
                sc(fx)
                invariants()
            except Exception as e:  # noqa: BLE001
                bad.append(f"iteration {i + 1}: {type(e).__name__}: {str(e)[:300]}")
        if bad:
            failures += 1
            print(f"FAIL  {sc.__name__}  ({len(bad)}/{iterations} iterations failed)")
            for b in bad[:3]:
                print("      " + b)
        else:
            print(f"PASS  {sc.__name__}  ({iterations} iterations)")
    print("----")
    print(f"concurrency scenarios failed: {failures}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
