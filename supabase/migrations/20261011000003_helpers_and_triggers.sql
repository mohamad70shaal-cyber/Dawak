-- Table-dependent helpers (authorization, audit, notifications, idempotency) and triggers.

-- ---------------------------------------------------------------------------
-- Authorization helpers
-- ---------------------------------------------------------------------------
create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin' and p.account_status = 'active'
  )
$$;

-- Active membership of the calling user (optionally restricted to roles). Used by RLS policies.
create function private.is_member(p_pharmacy uuid, p_roles public.member_role[] default null) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.pharmacy_members m
    join public.profiles p on p.id = m.user_id
    where m.pharmacy_id = p_pharmacy
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and p.account_status = 'active'
      and (p_roles is null or m.role = any (p_roles))
  )
$$;

-- Returns the caller's id; fails unless the caller is authenticated and not suspended.
create function private.assert_active_user() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_status public.account_status;
begin
  if v_uid is null then
    perform private.fail('not_authenticated');
  end if;
  select p.account_status into v_status from public.profiles p where p.id = v_uid;
  if not found then
    perform private.fail('not_authenticated');
  end if;
  if v_status <> 'active' then
    perform private.fail('account_suspended');
  end if;
  return v_uid;
end
$$;

create function private.assert_admin() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid;
begin
  v_uid := private.assert_active_user();
  if not private.is_admin() then
    perform private.fail('forbidden');
  end if;
  return v_uid;
end
$$;

-- Caller must be an active member with one of the roles; optionally the pharmacy must be approved.
create function private.assert_member(
  p_pharmacy uuid, p_roles public.member_role[], p_require_approved boolean default true
) returns public.member_role
language plpgsql stable security definer set search_path = '' as $$
declare
  v_role public.member_role;
  v_status public.approval_status;
begin
  select m.role into v_role
  from public.pharmacy_members m
  where m.pharmacy_id = p_pharmacy and m.user_id = auth.uid() and m.status = 'active';
  if v_role is null or not (v_role = any (p_roles)) then
    perform private.fail('forbidden');
  end if;
  if p_require_approved then
    select ph.approval_status into v_status from public.pharmacies ph where ph.id = p_pharmacy;
    if v_status is distinct from 'approved'::public.approval_status then
      perform private.fail('pharmacy_not_active');
    end if;
  end if;
  return v_role;
end
$$;

-- ---------------------------------------------------------------------------
-- Audit, notifications, idempotency
-- ---------------------------------------------------------------------------
create function private.audit(
  p_action text, p_entity_type text, p_entity_id uuid, p_pharmacy_id uuid, p_details jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, pharmacy_id, details)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, p_pharmacy_id, coalesce(p_details, '{}'::jsonb));
end
$$;

create function private.notify(
  p_user uuid, p_kind text, p_entity_type text, p_entity_id uuid, p_params jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, kind, entity_type, entity_id, params)
  values (p_user, p_kind, p_entity_type, p_entity_id, coalesce(p_params, '{}'::jsonb));
end
$$;

create function private.notify_pharmacy(
  p_pharmacy uuid, p_kind text, p_entity_type text, p_entity_id uuid, p_params jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, kind, entity_type, entity_id, params)
  select m.user_id, p_kind, p_entity_type, p_entity_id, coalesce(p_params, '{}'::jsonb)
  from public.pharmacy_members m
  where m.pharmacy_id = p_pharmacy and m.status = 'active';
end
$$;

-- Returns the stored response for an already-processed (user, scope, key), or NULL when this is
-- the first time. The key row is created inside the caller's transaction, so concurrent duplicates
-- serialise on the primary key and a failed attempt leaves no trace.
create function private.idem_begin(p_user uuid, p_scope text, p_key text, p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_inserted integer;
  v_hash text;
  v_response jsonb;
begin
  if p_key is null or char_length(p_key) < 8 or char_length(p_key) > 100 then
    perform private.fail('invalid_input', jsonb_build_object('field', 'idempotency_key'));
  end if;
  insert into public.idempotency_keys (user_id, scope, key, request_hash)
  values (p_user, p_scope, p_key, p_hash)
  on conflict do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return null;
  end if;
  select k.request_hash, k.response into v_hash, v_response
  from public.idempotency_keys k
  where k.user_id = p_user and k.scope = p_scope and k.key = p_key;
  if v_hash is distinct from p_hash then
    perform private.fail('duplicate_request', jsonb_build_object('reason', 'key_reused_with_different_request'));
  end if;
  return v_response;
end
$$;

create function private.idem_finish(p_user uuid, p_scope text, p_key text, p_response jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.idempotency_keys
  set response = p_response
  where user_id = p_user and scope = p_scope and key = p_key;
end
$$;

-- Parses [{product_id, quantity, expected_unit_price?}] into merged, validated rows.
create function private.parse_items(p_items jsonb, p_max_lines integer, p_max_qty integer)
returns table (product_id uuid, quantity integer, expected_unit_price numeric)
language plpgsql stable set search_path = '' as $$
begin
  -- Nested checks: never rely on the evaluation order of OR operands.
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    perform private.fail('invalid_input', jsonb_build_object('field', 'items'));
  end if;
  if jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > p_max_lines then
    perform private.fail('invalid_input', jsonb_build_object('field', 'items'));
  end if;
  if exists (select 1 from jsonb_array_elements(p_items) e where jsonb_typeof(e) <> 'object') then
    perform private.fail('invalid_input', jsonb_build_object('field', 'items'));
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x (product_id uuid, quantity integer, expected_unit_price numeric)
    where x.product_id is null or x.quantity is null or x.quantity < 1
       or coalesce(x.expected_unit_price, 0) < 0
  ) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'items'));
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x (product_id uuid, quantity integer, expected_unit_price numeric)
    group by x.product_id
    having sum(x.quantity) > p_max_qty
  ) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'quantity', 'max', p_max_qty));
  end if;

  return query
    select x.product_id, sum(x.quantity)::integer, max(x.expected_unit_price)
    from jsonb_to_recordset(p_items) as x (product_id uuid, quantity integer, expected_unit_price numeric)
    group by x.product_id
    order by x.product_id;
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch or invalid_parameter_value then
    perform private.fail('invalid_input', jsonb_build_object('field', 'items'));
end
$$;

-- ---------------------------------------------------------------------------
-- Generic triggers
-- ---------------------------------------------------------------------------
create function private.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end
$$;

create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger pharmacies_set_updated_at before update on public.pharmacies
  for each row execute function private.set_updated_at();
create trigger medicines_set_updated_at before update on public.medicines
  for each row execute function private.set_updated_at();
create trigger pharmacy_products_set_updated_at before update on public.pharmacy_products
  for each row execute function private.set_updated_at();
create trigger orders_set_updated_at before update on public.orders
  for each row execute function private.set_updated_at();
create trigger user_reports_set_updated_at before update on public.user_reports
  for each row execute function private.set_updated_at();

-- Append-only tables: history can never be edited or removed.
create function private.reject_mutation() returns trigger
language plpgsql as $$
begin
  raise exception using errcode = 'P0001', message = 'append_only', detail = tg_table_name;
end
$$;

create trigger sales_append_only before update or delete on public.sales
  for each row execute function private.reject_mutation();
create trigger sale_items_append_only before update or delete on public.sale_items
  for each row execute function private.reject_mutation();
create trigger audit_logs_append_only before update or delete on public.audit_logs
  for each row execute function private.reject_mutation();

create trigger sales_no_truncate before truncate on public.sales
  for each statement execute function private.reject_mutation();
create trigger sale_items_no_truncate before truncate on public.sale_items
  for each statement execute function private.reject_mutation();
create trigger audit_logs_no_truncate before truncate on public.audit_logs
  for each statement execute function private.reject_mutation();

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
-- Every auth user gets a CUSTOMER profile. Client-supplied metadata can never choose the role.
create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, phone)
  values (
    new.id,
    left(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 80),
    private.clean_phone(new.raw_user_meta_data ->> 'phone')
  )
  on conflict (id) do nothing;
  return new;
end
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- Defence in depth: client roles can never change privileged profile columns.
create function private.profiles_guard() returns trigger
language plpgsql as $$
begin
  if current_user in ('anon', 'authenticated') then
    if new.id is distinct from old.id
       or new.role is distinct from old.role
       or new.account_status is distinct from old.account_status
       or new.suspended_reason is distinct from old.suspended_reason then
      raise exception using errcode = '42501', message = 'forbidden';
    end if;
  end if;
  return new;
end
$$;

create trigger profiles_guard_trg before update on public.profiles
  for each row execute function private.profiles_guard();

-- ---------------------------------------------------------------------------
-- Pharmacies
-- ---------------------------------------------------------------------------
create function private.pharmacies_guard() returns trigger
language plpgsql as $$
begin
  if current_user in ('anon', 'authenticated') then
    raise exception using errcode = '42501', message = 'forbidden';
  end if;
  if new.owner_id is distinct from old.owner_id then
    perform private.fail('forbidden', jsonb_build_object('field', 'owner_id'));
  end if;
  if old.approval_status in ('approved', 'suspended') and new.currency is distinct from old.currency then
    perform private.fail('invalid_input', jsonb_build_object('field', 'currency', 'reason', 'immutable_after_approval'));
  end if;
  return new;
end
$$;

create trigger pharmacies_guard_trg before update on public.pharmacies
  for each row execute function private.pharmacies_guard();

-- Pharmacy products: identity columns are immutable.
create function private.pharmacy_products_guard() returns trigger
language plpgsql as $$
begin
  if new.pharmacy_id is distinct from old.pharmacy_id or new.medicine_id is distinct from old.medicine_id then
    perform private.fail('forbidden', jsonb_build_object('field', 'identity'));
  end if;
  return new;
end
$$;

create trigger pharmacy_products_guard_trg before update on public.pharmacy_products
  for each row execute function private.pharmacy_products_guard();

-- ---------------------------------------------------------------------------
-- Orders: explicit state machine + immutable identity/amount columns.
-- ---------------------------------------------------------------------------
create function private.orders_guard() returns trigger
language plpgsql as $$
begin
  if new.customer_id is distinct from old.customer_id
     or new.pharmacy_id is distinct from old.pharmacy_id
     or new.public_ref is distinct from old.public_ref
     or new.currency is distinct from old.currency
     or new.subtotal is distinct from old.subtotal then
    perform private.fail('forbidden', jsonb_build_object('field', 'order_identity'));
  end if;

  if old.status in ('completed', 'rejected', 'cancelled') then
    perform private.fail('invalid_transition', jsonb_build_object('from', old.status, 'to', new.status));
  end if;

  if new.status is distinct from old.status
     and not private.order_transition_allowed(old.status, new.status) then
    perform private.fail('invalid_transition', jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  return new;
end
$$;

create trigger orders_guard_trg before update on public.orders
  for each row execute function private.orders_guard();

-- ---------------------------------------------------------------------------
-- Catalogue changes made directly by admins are audited.
-- ---------------------------------------------------------------------------
create function private.audit_catalog_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(),
    lower(tg_op) || '_' || tg_table_name,
    tg_table_name,
    case when tg_op = 'DELETE' then old.id else new.id end,
    jsonb_build_object('op', tg_op)
  );
  return coalesce(new, old);
end
$$;

create trigger medicines_audit after insert or update on public.medicines
  for each row execute function private.audit_catalog_change();
create trigger medicine_categories_audit after insert or update on public.medicine_categories
  for each row execute function private.audit_catalog_change();
