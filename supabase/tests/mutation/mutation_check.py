#!/usr/bin/env python3
"""Mutation check for the SQL suite: deliberately breaks security/business rules and verifies that
at least one test fails for each break ("killed"). A surviving mutant means a missing test.

    PGHOST=... PGPORT=... PGUSER=postgres python3 supabase/tests/mutation/mutation_check.py [name-filter ...]
    MUT_RANGE=10:20 ...   # optional: run only mutants 10..19 (the whole list takes ~25 minutes)

Each mutation is (name, [(migration file, exact text, replacement), ...]). Migrations are copied to a
temp directory and mutated there; the repository files are never modified.
"""
import os, shutil, subprocess, sys, tempfile, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
MIG = ROOT / "supabase" / "migrations"

F1 = "20261011000001_foundation.sql"
F2 = "20261011000002_core_tables.sql"
F3 = "20261011000003_helpers_and_triggers.sql"
F4 = "20261011000004_rls_and_grants.sql"
F5 = "20261011000005_rpc_accounts_admin_listing.sql"
F6 = "20261011000006_rpc_pos_and_orders.sql"
F7 = "20261011000007_rpc_availability_requests.sql"
F8 = "20261011000008_rpc_public_and_dashboard.sql"
F9 = "20261011000009_storage_and_function_grants.sql"

MUTATIONS = [
    # ---- orders / POS -----------------------------------------------------------------------------------
    ("complete_order skips reference check", [(F6,
     "  if upper(btrim(coalesce(p_reference, ''))) <> v_order.public_ref then\n    perform private.fail('reference_mismatch');\n  end if;",
     "")]),
    ("create_order accepts products marked unavailable", [(F6,
     "       or not coalesce(r.is_available, false)\n", "")]),
    ("create_order accepts another pharmacy's product", [(F6,
     "    if r.pharmacy_id is distinct from p_pharmacy_id\n       or not coalesce(r.is_available, false)",
     "    if false\n       or not coalesce(r.is_available, false)")]),
    ("POS sells another pharmacy's product", [(F6,
     "    if r.pharmacy_id is distinct from p_pharmacy_id then\n      perform private.fail('product_unavailable', jsonb_build_object('product_id', r.product_id));\n    end if;\n    v_subtotal",
     "    v_subtotal")]),
    ("orders readable by every signed-in user", [(F4,
     "using (customer_id = (select auth.uid()) or private.is_member(pharmacy_id));",
     "using (true);")]),
    ("order state machine trigger weakened", [(F3,
     "  if new.status is distinct from old.status\n     and not private.order_transition_allowed(old.status, new.status) then\n    perform private.fail('invalid_transition', jsonb_build_object('from', old.status, 'to', new.status));\n  end if;",
     "")]),
    ("discount allowed for cashiers", [(F6,
     "  if v_discount > 0 and v_role not in ('owner', 'manager') then\n    perform private.fail('forbidden', jsonb_build_object('reason', 'discount'));\n  end if;",
     "")]),
    ("idempotency key ignored (retry creates a second sale)", [(F3,
     "  on conflict do nothing;\n  get diagnostics v_inserted = row_count;\n  if v_inserted = 1 then\n    return null;\n  end if;",
     "  on conflict do nothing;\n  return null;")]),
    ("get_sale leaks other pharmacies' receipts", [(F6,
     "  if v_role is null or (v_role = 'cashier' and v_cashier is distinct from v_uid) then\n    perform private.fail('not_found');\n  end if;",
     "")]),
    ("stale client price accepted silently", [(F6,
     "  if jsonb_array_length(v_changes) > 0 then\n    perform private.fail('price_changed', jsonb_build_object('items', v_changes));\n  end if;",
     "")]),
    # ---- listing (layer 1) ------------------------------------------------------------------------------
    ("update_pharmacy_product does not confirm the row", [(F5,
     "    is_available = coalesce(p_is_available, is_available),\n    confirmed_at = now()\n  where id = p_product_id",
     "    is_available = coalesce(p_is_available, is_available)\n  where id = p_product_id")]),
    ("cashiers may edit the price list", [(F5,
     "  perform private.assert_member(v_pharmacy, array['owner', 'manager']::public.member_role[], true);\n  if p_price is not null and (p_price <= 0",
     "  perform private.assert_member(v_pharmacy, array['owner', 'manager', 'cashier']::public.member_role[], true);\n  if p_price is not null and (p_price <= 0")]),
    ("match_medicine_names open to every signed-in user", [(F5,
     "  ) then\n    perform private.fail('forbidden');\n  end if;\n  if p_names is null",
     "  ) and false then\n    perform private.fail('forbidden');\n  end if;\n  if p_names is null")]),
    ("medicine de-duplication removed (lookup + unique index)", [
     (F5, "  where m.dedupe_key = v_key and m.catalog_status in ('pending', 'approved');\n  if found then",
          "  where false;\n  if found then"),
     (F2, "create unique index medicines_dedupe_uq", "create index medicines_dedupe_uq")]),
    # ---- search (layer 2) -------------------------------------------------------------------------------
    ("search lists suspended/unlisted pharmacies", [(F8,
     "      and ph.approval_status = 'approved' and ph.is_listed\n      and m.catalog_status = 'approved'\n      and (v_city",
     "      and m.catalog_status = 'approved'\n      and (v_city")]),
    ("search shows pharmacies marked unavailable", [(F8,
     "    where pp.medicine_id = p_medicine_id and pp.is_available\n      and pp.confirmed_at",
     "    where pp.medicine_id = p_medicine_id\n      and pp.confirmed_at")]),
    ("search ignores the 30-day freshness cut-off", [(F8,
     "    where pp.medicine_id = p_medicine_id and pp.is_available\n      and pp.confirmed_at >= now() - make_interval(days => private.cfg_int('listing_max_age_days'))\n      and ph.approval_status",
     "    where pp.medicine_id = p_medicine_id and pp.is_available\n      and ph.approval_status")]),
    ("search ordering ignores distance", [(F8,
     "  order by t.distance_km nulls last,\n           (t.freshness = 'recent') desc,",
     "  order by (t.freshness = 'recent') desc,")]),
    ("search radius filter ignored", [(F8,
     "  where p_radius_km is null or (t.distance_km is not null and t.distance_km <= p_radius_km)",
     "  where true")]),
    ("search-result pharmacy_count counts unavailable rows", [(F8,
     "          where pp.medicine_id = m.id and pp.is_available\n            and pp.confirmed_at",
     "          where pp.medicine_id = m.id\n            and pp.confirmed_at")]),
    ("hidden phone numbers shown in search", [(F8,
     "           case when ph.show_phone_publicly then ph.phone else null end as phone,\n           ph.latitude, ph.longitude,\n           case when v_located",
     "           ph.phone as phone,\n           ph.latitude, ph.longitude,\n           case when v_located")]),
    # ---- availability requests (layer 3) ----------------------------------------------------------------
    ("request targets ignore the radius", [(F7,
     "  ) t\n  where t.d <= p_radius_km\n$$;", "  ) t\n$$;")]),
    ("unlisted/suspended pharmacies are asked", [(F7,
     "    where ph.approval_status = 'approved' and ph.is_listed and ph.latitude is not null",
     "    where ph.latitude is not null")]),
    ("target cap removed", [(F7,
     "  if v_room <= 0 then\n    return 0;\n  end if;", "  v_room := 1000;")]),
    ("no widening when everybody answered unavailable", [(F7,
     "    if v_total = 0 or v_answered = v_total\n       or r.last_expanded_at",
     "    if v_total = 0\n       or r.last_expanded_at")]),
    ("no widening after three minutes of silence", [(F7,
     "       or r.last_expanded_at <= now() - make_interval(mins => private.cfg_int('request_wait_minutes')) then",
     "       or false then")]),
    ("no skipping of empty radii", [(F7,
     "    if v_total = 0 or v_answered = v_total", "    if v_answered = v_total and v_total > 0")]),
    ("widening continues although somebody is available", [(F7,
     "    if v_available > 0 or r.step >= private.cfg_int('request_max_step') then",
     "    if r.step >= private.cfg_int('request_max_step') then")]),
    ("widening goes past the maximum radius", [(F7,
     "    if v_available > 0 or r.step >= private.cfg_int('request_max_step') then\n      return;",
     "    if v_available > 0 or r.step >= 99 then\n      return;")]),
    ("expired requests keep accepting work", [(F7,
     "    if r.expires_at <= now() then\n      update public.availability_requests set status = 'expired', closed_at = now() where id = p_id;\n      return;\n    end if;",
     "")]),
    ("open-request cap removed", [(F7,
     "       >= private.cfg_int('max_open_requests') then\n    perform private.fail('too_many_requests');",
     "       >= 1000 then\n    perform private.fail('too_many_requests');")]),
    ("hourly rate limit removed", [(F7,
     "       >= private.cfg_int('max_requests_per_hour') then\n    perform private.fail('rate_limited');",
     "       >= 100000 then\n    perform private.fail('rate_limited');")]),
    ("duplicate requests not merged", [(F7,
     "    and private.distance_km(q.latitude, q.longitude, v_lat, v_lng) < 0.5", "    and false")]),
    ("customer coordinates stored unrounded", [(F7,
     "  v_lat := round(p_latitude::numeric, 3)::double precision;", "  v_lat := p_latitude;")]),
    ("pharmacists may create requests", [(F7,
     "  if v_role <> 'customer' then\n    perform private.fail('forbidden');\n  end if;\n  perform private.check_location",
     "  perform private.check_location")]),
    ("any customer can read another's request", [(F7,
     "  if v_owner is null or v_owner <> v_uid then\n    perform private.fail('not_found');\n  end if;\n  select * into r from public.availability_requests where id = p_id for update;",
     "  select * into r from public.availability_requests where id = p_id for update;")]),
    ("a pharmacy that was not asked can answer", [(F7,
     "  where t.request_id = p_request_id and t.pharmacy_id = p_pharmacy_id for update;\n  if not found then\n    perform private.fail('not_found');\n  end if;",
     "  where t.request_id = p_request_id and t.pharmacy_id = p_pharmacy_id for update;")]),
    ("answers accepted on closed requests", [(F7,
     "  if r.status <> 'open' or r.expires_at <= now() then\n    perform private.fail('request_closed');\n  end if;\n\n  v_first",
     "  v_first")]),
    ("cashier answers change the price list", [(F7,
     "  if v_role in ('owner', 'manager') then\n    if p_available then", "  if true then\n    if p_available then")]),
    ("customer sees pharmacies that said unavailable", [(F7,
     "        where t.request_id = r.id and t.answer = 'available'\n          and ph.approval_status = 'approved' and ph.is_listed",
     "        where t.request_id = r.id\n          and ph.approval_status = 'approved' and ph.is_listed")]),
    ("offers show hidden phone numbers", [(F7,
     "               case when ph.show_phone_publicly then ph.phone else null end as phone,\n               ph.latitude, ph.longitude, t.distance_km",
     "               ph.phone as phone,\n               ph.latitude, ph.longitude, t.distance_km")]),
    ("first available answer does not notify the customer", [(F7,
     "  if v_first then\n    select coalesce", "  if false then\n    select coalesce")]),
    ("pharmacy inbox open to non-members", [(F7,
     "  perform private.assert_active_user();\n  perform private.assert_member(p_pharmacy_id, array['owner', 'manager', 'cashier']::public.member_role[], true);\n  return query\n  select r.id, m.id",
     "  perform private.assert_active_user();\n  return query\n  select r.id, m.id")]),
    # ---- infrastructure ---------------------------------------------------------------------------------
    ("dashboard day boundaries ignore time zone", [(F1,
     "select (p_day::timestamp) at time zone p_tz", "select (p_day::timestamp) at time zone 'UTC'")]),
    # Two layers keep private helpers closed (global default + explicit sweeps); remove all of them.
    ("private helpers executable by everyone (all layers)", [
     (F1, "alter default privileges revoke execute on functions from public;", ""),
     (F4, "revoke execute on all functions in schema private from public, anon, authenticated;", ""),
     (F9, "revoke execute on all functions in schema private from public, anon, authenticated;", "")]),
    ("availability tables readable by clients", [(F4,
     "alter table public.availability_requests enable row level security;",
     "alter table public.availability_requests enable row level security;\ngrant select on public.availability_requests to authenticated;\ncreate policy tmp_all on public.availability_requests for select to authenticated using (true);")]),
]

def psql(db, *args, check=True):
    return subprocess.run(["psql", "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-d", db, *args],
                          capture_output=True, text=True, env={**os.environ, "PGCLIENTENCODING": "UTF8"})

def run_suite(mig_dir, db):
    psql("postgres", "-c", f'drop database if exists "{db}"', "-c", f'create database "{db}"')
    files = [ROOT / "supabase/tests/00_supabase_stub.sql", *sorted(pathlib.Path(mig_dir).glob("*.sql")),
             ROOT / "supabase/tests/01_helpers.sql", *sorted((ROOT / "supabase/tests").glob("[1-9]*_tests_*.sql"))]
    for f in files:
        r = psql(db, "-f", str(f))
        if r.returncode != 0:
            return None, f"load error in {f.name}: {r.stderr.strip()[:300]}"
    r = psql(db, "-F", "|", "-c", "select name, message from tests.run_all('%') where not ok")
    if r.returncode != 0:
        return None, r.stderr.strip()[:300]
    return [l for l in r.stdout.splitlines() if l.strip()], None

def main():
    only = sys.argv[1:]  # optional name filters
    survivors, errors, ran = [], [], 0
    # The unmutated code must load and pass, otherwise "killed" would be meaningless (e.g. no DB connection).
    failed, err = run_suite(MIG, "dawak_mut")
    if err or failed:
        print("BASELINE (unmutated) is not green; fix this before running mutants:")
        print(err or "\n".join(failed))
        sys.exit(2)
    print("baseline: all tests pass on unmutated migrations")
    with tempfile.TemporaryDirectory() as base:
        tmp = os.path.join(base, "m")
        lo, _, hi = os.environ.get("MUT_RANGE", "").partition(":")   # e.g. MUT_RANGE=10:20 runs mutants 10..19
        for idx, (name, edits) in enumerate(MUTATIONS):
            if lo and not (int(lo) <= idx < int(hi or len(MUTATIONS))):
                continue
            if only and not any(o.lower() in name.lower() for o in only):
                continue
            shutil.rmtree(tmp, ignore_errors=True); shutil.copytree(MIG, tmp)
            bad = None
            for fname, old, new in edits:
                p = pathlib.Path(tmp) / fname
                text = p.read_text(encoding="utf-8")
                if old not in text:
                    bad = f"anchor not found in {fname} (migration text changed?)"; break
                p.write_text(text.replace(old, new, 1), encoding="utf-8")
            if bad:
                errors.append((name, bad)); continue
            ran += 1
            failed, err = run_suite(tmp, "dawak_mut")
            if err:
                print(f"KILLED (load/DB error)  {name}: {err[:140]}")
                continue
            if failed:
                print(f"KILLED  {name}  <- {', '.join(l.split('|')[0] for l in failed[:4])}{' ...' if len(failed) > 4 else ''}")
            else:
                print(f"SURVIVED  {name}")
                survivors.append(name)
    print("----")
    print(f"mutants run: {ran}; killed: {ran - len(survivors)}; survivors: {len(survivors)}; anchor errors: {len(errors)}")
    for n, e in errors: print("ERROR", n, e)
    sys.exit(1 if survivors or errors else 0)

if __name__ == "__main__":
    main()
