-- Trusted functions: pharmacy onboarding, admin actions, catalogue proposals, the pharmacy list (no quantities).
-- All are SECURITY DEFINER with an empty search_path and re-derive the caller from auth.uid().

-- ---------------------------------------------------------------------------
-- Pharmacy onboarding
-- ---------------------------------------------------------------------------
create function public.register_pharmacy(
  p_name text,
  p_phone text,
  p_address_line text,
  p_neighborhood text,
  p_city text,
  p_directions text,
  p_opening_hours jsonb,
  p_currency text,
  p_license_path text,
  p_latitude double precision,
  p_longitude double precision,
  p_show_phone_publicly boolean default true
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_role public.user_role;
  v_phone text;
  v_license text;
  v_hours jsonb := coalesce(p_opening_hours, '{}'::jsonb);
  v_pharmacy public.pharmacies;
begin
  v_uid := private.assert_active_user();
  select p.role into v_role from public.profiles p where p.id = v_uid;
  if v_role = 'admin' then
    perform private.fail('forbidden');
  end if;
  if exists (select 1 from public.pharmacies ph where ph.owner_id = v_uid) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'pharmacy', 'reason', 'already_registered'));
  end if;

  v_phone := private.clean_phone(p_phone);
  if v_phone is null then
    perform private.fail('invalid_input', jsonb_build_object('field', 'phone'));
  end if;
  if coalesce(p_currency, 'SYP') not in ('SYP', 'USD') then
    perform private.fail('invalid_input', jsonb_build_object('field', 'currency'));
  end if;
  if jsonb_typeof(v_hours) <> 'object' or char_length(v_hours::text) > 2000 then
    perform private.fail('invalid_input', jsonb_build_object('field', 'opening_hours'));
  end if;
  v_license := btrim(coalesce(p_license_path, ''));
  if v_license = '' or v_license not like v_uid::text || '/%' or v_license like '%..%' or char_length(v_license) > 300 then
    perform private.fail('invalid_input', jsonb_build_object('field', 'license_document'));
  end if;
  perform private.check_location(p_latitude, p_longitude);

  insert into public.pharmacies (
    owner_id, name, phone, show_phone_publicly, address_line, neighborhood, city, directions,
    opening_hours, currency, license_document_path, latitude, longitude
  ) values (
    v_uid,
    private.req_text(p_name, 'name', 2, 120),
    v_phone,
    coalesce(p_show_phone_publicly, true),
    private.req_text(p_address_line, 'address_line', 3, 250),
    coalesce(private.req_text(p_neighborhood, 'neighborhood', 1, 100, false), ''),
    private.req_text(p_city, 'city', 2, 100),
    private.req_text(p_directions, 'directions', 1, 500, false),
    v_hours,
    coalesce(p_currency, 'SYP'),
    v_license,
    p_latitude,
    p_longitude
  ) returning * into v_pharmacy;

  insert into public.pharmacy_members (pharmacy_id, user_id, role, status)
  values (v_pharmacy.id, v_uid, 'owner', 'active');

  update public.profiles set role = 'pharmacist' where id = v_uid and role = 'customer';

  perform private.audit('pharmacy_registered', 'pharmacy', v_pharmacy.id, v_pharmacy.id, '{}'::jsonb);
  return to_jsonb(v_pharmacy);
end
$$;

-- Owner re-submits a rejected application (optionally with a new licence document).
create function public.resubmit_pharmacy(
  p_pharmacy_id uuid,
  p_name text,
  p_phone text,
  p_address_line text,
  p_neighborhood text,
  p_city text,
  p_directions text,
  p_opening_hours jsonb,
  p_license_path text default null,
  p_show_phone_publicly boolean default true,
  p_latitude double precision default null,
  p_longitude double precision default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_ph public.pharmacies;
  v_phone text;
  v_license text;
  v_hours jsonb := coalesce(p_opening_hours, '{}'::jsonb);
begin
  v_uid := private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner']::public.member_role[], false);
  select * into v_ph from public.pharmacies where id = p_pharmacy_id for update;
  if v_ph.approval_status <> 'rejected' then
    perform private.fail('invalid_transition', jsonb_build_object('from', v_ph.approval_status, 'to', 'pending'));
  end if;

  v_phone := private.clean_phone(p_phone);
  if v_phone is null then
    perform private.fail('invalid_input', jsonb_build_object('field', 'phone'));
  end if;
  if jsonb_typeof(v_hours) <> 'object' or char_length(v_hours::text) > 2000 then
    perform private.fail('invalid_input', jsonb_build_object('field', 'opening_hours'));
  end if;
  v_license := nullif(btrim(coalesce(p_license_path, '')), '');
  if v_license is not null and (v_license not like v_uid::text || '/%' or v_license like '%..%' or char_length(v_license) > 300) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'license_document'));
  end if;
  -- NULL coordinates keep the current location; when either is given both must be valid.
  if p_latitude is not null or p_longitude is not null then
    perform private.check_location(p_latitude, p_longitude);
  end if;

  update public.pharmacies set
    name = private.req_text(p_name, 'name', 2, 120),
    phone = v_phone,
    show_phone_publicly = coalesce(p_show_phone_publicly, true),
    address_line = private.req_text(p_address_line, 'address_line', 3, 250),
    neighborhood = coalesce(private.req_text(p_neighborhood, 'neighborhood', 1, 100, false), ''),
    city = private.req_text(p_city, 'city', 2, 100),
    directions = private.req_text(p_directions, 'directions', 1, 500, false),
    opening_hours = v_hours,
    license_document_path = coalesce(v_license, license_document_path),
    latitude = coalesce(p_latitude, latitude),
    longitude = coalesce(p_longitude, longitude),
    approval_status = 'pending',
    status_reason = null,
    reviewed_by = null,
    reviewed_at = null,
    is_listed = false,
    submitted_at = now()
  where id = p_pharmacy_id
  returning * into v_ph;

  perform private.audit('pharmacy_resubmitted', 'pharmacy', v_ph.id, v_ph.id, '{}'::jsonb);
  return to_jsonb(v_ph);
end
$$;

-- Owner edits an approved pharmacy. NULL parameters mean "leave unchanged".
create function public.update_my_pharmacy(
  p_pharmacy_id uuid,
  p_name text default null,
  p_phone text default null,
  p_address_line text default null,
  p_neighborhood text default null,
  p_city text default null,
  p_directions text default null,
  p_opening_hours jsonb default null,
  p_show_phone_publicly boolean default null,
  p_is_listed boolean default null,
  p_latitude double precision default null,
  p_longitude double precision default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ph public.pharmacies;
  v_phone text;
begin
  perform private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner']::public.member_role[], true);
  select * into v_ph from public.pharmacies where id = p_pharmacy_id for update;

  if p_phone is not null then
    v_phone := private.clean_phone(p_phone);
    if v_phone is null then
      perform private.fail('invalid_input', jsonb_build_object('field', 'phone'));
    end if;
  end if;
  if p_opening_hours is not null
     and (jsonb_typeof(p_opening_hours) <> 'object' or char_length(p_opening_hours::text) > 2000) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'opening_hours'));
  end if;
  -- NULL coordinates keep the current location; when either is given both must be valid.
  if p_latitude is not null or p_longitude is not null then
    perform private.check_location(p_latitude, p_longitude);
  end if;

  update public.pharmacies set
    name = coalesce(private.req_text(p_name, 'name', 2, 120, false), name),
    phone = coalesce(v_phone, phone),
    address_line = coalesce(private.req_text(p_address_line, 'address_line', 3, 250, false), address_line),
    neighborhood = coalesce(private.req_text(p_neighborhood, 'neighborhood', 1, 100, false), neighborhood),
    city = coalesce(private.req_text(p_city, 'city', 2, 100, false), city),
    directions = coalesce(private.req_text(p_directions, 'directions', 1, 500, false), directions),
    opening_hours = coalesce(p_opening_hours, opening_hours),
    show_phone_publicly = coalesce(p_show_phone_publicly, show_phone_publicly),
    is_listed = coalesce(p_is_listed, is_listed),
    latitude = coalesce(p_latitude, latitude),
    longitude = coalesce(p_longitude, longitude)
  where id = p_pharmacy_id
  returning * into v_ph;

  perform private.audit('pharmacy_updated', 'pharmacy', v_ph.id, v_ph.id,
                        jsonb_build_object('location_changed', p_latitude is not null));
  return to_jsonb(v_ph);
end
$$;

-- ---------------------------------------------------------------------------
-- Admin
-- ---------------------------------------------------------------------------
create function public.admin_review_pharmacy(p_pharmacy_id uuid, p_decision text, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_ph public.pharmacies;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_new public.approval_status;
  v_kind text;
begin
  v_uid := private.assert_admin();
  select * into v_ph from public.pharmacies where id = p_pharmacy_id for update;
  if not found then
    perform private.fail('not_found');
  end if;

  case p_decision
    when 'approve' then
      if v_ph.approval_status <> 'pending' then
        perform private.fail('invalid_transition', jsonb_build_object('from', v_ph.approval_status, 'to', 'approved'));
      end if;
      v_new := 'approved'; v_kind := 'pharmacy_approved';
    when 'reject' then
      if v_ph.approval_status <> 'pending' then
        perform private.fail('invalid_transition', jsonb_build_object('from', v_ph.approval_status, 'to', 'rejected'));
      end if;
      if v_reason is null then
        perform private.fail('invalid_input', jsonb_build_object('field', 'reason', 'reason', 'required'));
      end if;
      v_new := 'rejected'; v_kind := 'pharmacy_rejected';
    when 'suspend' then
      if v_ph.approval_status <> 'approved' then
        perform private.fail('invalid_transition', jsonb_build_object('from', v_ph.approval_status, 'to', 'suspended'));
      end if;
      if v_reason is null then
        perform private.fail('invalid_input', jsonb_build_object('field', 'reason', 'reason', 'required'));
      end if;
      v_new := 'suspended'; v_kind := 'pharmacy_suspended';
    when 'reinstate' then
      if v_ph.approval_status <> 'suspended' then
        perform private.fail('invalid_transition', jsonb_build_object('from', v_ph.approval_status, 'to', 'approved'));
      end if;
      v_new := 'approved'; v_kind := 'pharmacy_reinstated';
    else
      perform private.fail('invalid_input', jsonb_build_object('field', 'decision'));
  end case;

  update public.pharmacies set
    approval_status = v_new,
    status_reason = case when v_new in ('rejected', 'suspended') then v_reason else null end,
    is_listed = (v_new = 'approved'),
    reviewed_by = v_uid,
    reviewed_at = now()
  where id = p_pharmacy_id
  returning * into v_ph;

  perform private.audit('pharmacy_' || p_decision, 'pharmacy', v_ph.id, v_ph.id,
                        jsonb_build_object('reason', v_reason, 'status', v_new));
  perform private.notify(v_ph.owner_id, v_kind, 'pharmacy', v_ph.id, jsonb_build_object('reason', v_reason));
  return to_jsonb(v_ph);
end
$$;

create function public.admin_set_account_status(p_user_id uuid, p_status text, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_target public.profiles;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  v_uid := private.assert_admin();
  if p_user_id = v_uid then
    perform private.fail('forbidden', jsonb_build_object('reason', 'self'));
  end if;
  if p_status not in ('active', 'suspended') then
    perform private.fail('invalid_input', jsonb_build_object('field', 'status'));
  end if;
  if p_status = 'suspended' and v_reason is null then
    perform private.fail('invalid_input', jsonb_build_object('field', 'reason', 'reason', 'required'));
  end if;
  select * into v_target from public.profiles where id = p_user_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  if v_target.role = 'admin' then
    perform private.fail('forbidden', jsonb_build_object('reason', 'target_is_admin'));
  end if;

  update public.profiles set
    account_status = p_status::public.account_status,
    suspended_reason = case when p_status = 'suspended' then v_reason else null end
  where id = p_user_id;

  perform private.audit('account_' || p_status, 'profile', p_user_id, null, jsonb_build_object('reason', v_reason));
  return jsonb_build_object('id', p_user_id, 'account_status', p_status);
end
$$;

create function public.admin_review_medicine(p_medicine_id uuid, p_decision text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_med public.medicines;
  v_new public.catalog_status;
begin
  v_uid := private.assert_admin();
  select * into v_med from public.medicines where id = p_medicine_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  case p_decision
    when 'approve' then
      if v_med.catalog_status <> 'pending' then
        perform private.fail('invalid_transition', jsonb_build_object('from', v_med.catalog_status, 'to', 'approved'));
      end if;
      v_new := 'approved';
    when 'reject' then
      if v_med.catalog_status <> 'pending' then
        perform private.fail('invalid_transition', jsonb_build_object('from', v_med.catalog_status, 'to', 'rejected'));
      end if;
      v_new := 'rejected';
    when 'archive' then
      if v_med.catalog_status = 'archived' then
        perform private.fail('invalid_transition', jsonb_build_object('from', v_med.catalog_status, 'to', 'archived'));
      end if;
      v_new := 'archived';
    else
      perform private.fail('invalid_input', jsonb_build_object('field', 'decision'));
  end case;
  update public.medicines set catalog_status = v_new, reviewed_by = v_uid, reviewed_at = now()
  where id = p_medicine_id;
  perform private.audit('medicine_' || p_decision, 'medicine', p_medicine_id, null, '{}'::jsonb);
  return jsonb_build_object('id', p_medicine_id, 'catalog_status', v_new);
end
$$;

create function public.admin_resolve_report(p_report_id uuid, p_status text, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  v_uid := private.assert_admin();
  if p_status not in ('in_review', 'resolved', 'dismissed') then
    perform private.fail('invalid_input', jsonb_build_object('field', 'status'));
  end if;
  if char_length(coalesce(v_note, '')) > 500 then
    perform private.fail('invalid_input', jsonb_build_object('field', 'note'));
  end if;
  update public.user_reports set
    status = p_status::public.report_status,
    resolution_note = v_note,
    resolved_by = v_uid
  where id = p_report_id;
  if not found then
    perform private.fail('not_found');
  end if;
  perform private.audit('report_' || p_status, 'user_report', p_report_id, null, '{}'::jsonb);
  return jsonb_build_object('id', p_report_id, 'status', p_status);
end
$$;

-- Aggregates only: no personal data.
create function public.admin_metrics() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.assert_admin();
  return jsonb_build_object(
    'pharmacies', jsonb_build_object(
      'pending', (select count(*) from public.pharmacies where approval_status = 'pending'),
      'approved', (select count(*) from public.pharmacies where approval_status = 'approved'),
      'rejected', (select count(*) from public.pharmacies where approval_status = 'rejected'),
      'suspended', (select count(*) from public.pharmacies where approval_status = 'suspended')
    ),
    'users', jsonb_build_object(
      'customers', (select count(*) from public.profiles where role = 'customer'),
      'pharmacists', (select count(*) from public.profiles where role = 'pharmacist'),
      'suspended', (select count(*) from public.profiles where account_status = 'suspended')
    ),
    'medicines', jsonb_build_object(
      'approved', (select count(*) from public.medicines where catalog_status = 'approved'),
      'pending', (select count(*) from public.medicines where catalog_status = 'pending')
    ),
    'orders_30d', jsonb_build_object(
      'total', (select count(*) from public.orders where created_at >= now() - interval '30 days'),
      'completed', (select count(*) from public.orders where status = 'completed' and created_at >= now() - interval '30 days'),
      'cancelled_or_rejected', (select count(*) from public.orders where status in ('cancelled', 'rejected') and created_at >= now() - interval '30 days')
    ),
    'sales_30d_count', (select count(*) from public.sales where created_at >= now() - interval '30 days'),
    'open_reports', (select count(*) from public.user_reports where status in ('open', 'in_review'))
  );
end
$$;

-- ---------------------------------------------------------------------------
-- Catalogue proposals (pharmacists propose; admin approves)
-- ---------------------------------------------------------------------------
create function public.propose_medicine(
  p_name_ar text,
  p_name_en text,
  p_brand_name text,
  p_active_ingredient text,
  p_strength text,
  p_dosage_form text,
  p_package_description text,
  p_category_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid;
  v_name_ar text := private.req_text(p_name_ar, 'name_ar', 1, 160, false);
  v_name_en text := private.req_text(p_name_en, 'name_en', 1, 160, false);
  v_brand text := private.req_text(p_brand_name, 'brand_name', 1, 160, false);
  v_ingredient text := private.req_text(p_active_ingredient, 'active_ingredient', 1, 200, false);
  v_strength text := private.req_text(p_strength, 'strength', 1, 60, false);
  v_form text := private.req_text(p_dosage_form, 'dosage_form', 1, 60, false);
  v_pack text := private.req_text(p_package_description, 'package_description', 1, 200, false);
  v_key text;
  v_existing public.medicines;
  v_new public.medicines;
begin
  v_uid := private.assert_active_user();
  if not private.is_admin() and not exists (
    select 1
    from public.pharmacy_members m
    join public.pharmacies ph on ph.id = m.pharmacy_id
    where m.user_id = v_uid and m.status = 'active'
      and m.role in ('owner', 'manager') and ph.approval_status = 'approved'
  ) then
    perform private.fail('forbidden');
  end if;
  if v_name_ar is null and v_name_en is null then
    perform private.fail('invalid_input', jsonb_build_object('field', 'name'));
  end if;
  if p_category_id is not null and not exists (
    select 1 from public.medicine_categories c where c.id = p_category_id and c.is_active
  ) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'category_id'));
  end if;

  v_key := private.normalize_search(
    coalesce(v_name_ar, '') || '|' || coalesce(v_name_en, '') || '|' || coalesce(v_brand, '') || '|' ||
    coalesce(v_strength, '') || '|' || coalesce(v_form, '') || '|' || coalesce(v_pack, '')
  );

  select * into v_existing
  from public.medicines m
  where m.dedupe_key = v_key and m.catalog_status in ('pending', 'approved');
  if found then
    return jsonb_build_object('id', v_existing.id, 'catalog_status', v_existing.catalog_status, 'existed', true);
  end if;

  begin
    insert into public.medicines (
      category_id, name_ar, name_en, brand_name, active_ingredient, strength, dosage_form,
      package_description, catalog_status, proposed_by
    ) values (
      p_category_id, v_name_ar, v_name_en, v_brand, v_ingredient, v_strength, v_form, v_pack, 'pending', v_uid
    ) returning * into v_new;
  exception when unique_violation then
    select * into v_existing
    from public.medicines m
    where m.dedupe_key = v_key and m.catalog_status in ('pending', 'approved');
    return jsonb_build_object('id', v_existing.id, 'catalog_status', v_existing.catalog_status, 'existed', true);
  end;

  return jsonb_build_object('id', v_new.id, 'catalog_status', v_new.catalog_status, 'existed', false);
end
$$;

-- ---------------------------------------------------------------------------
-- The pharmacy list (what the pharmacy says it has; no quantities, see docs/availability_design.md)
-- ---------------------------------------------------------------------------
create function public.add_pharmacy_product(
  p_pharmacy_id uuid,
  p_medicine_id uuid,
  p_price numeric
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_existing uuid;
  v_product public.pharmacy_products;
begin
  perform private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner', 'manager']::public.member_role[], true);
  if p_price is null or p_price <= 0 or p_price > 999999999999 or scale(p_price) > 2 then
    perform private.fail('invalid_input', jsonb_build_object('field', 'price'));
  end if;
  if not exists (select 1 from public.medicines m where m.id = p_medicine_id and m.catalog_status = 'approved') then
    perform private.fail('not_found', jsonb_build_object('field', 'medicine_id'));
  end if;
  select pp.id into v_existing from public.pharmacy_products pp
  where pp.pharmacy_id = p_pharmacy_id and pp.medicine_id = p_medicine_id;
  if v_existing is not null then
    perform private.fail('invalid_input', jsonb_build_object('field', 'medicine_id', 'reason', 'already_exists', 'product_id', v_existing));
  end if;

  insert into public.pharmacy_products (pharmacy_id, medicine_id, price)
  values (p_pharmacy_id, p_medicine_id, p_price)
  returning * into v_product;

  perform private.audit('product_added', 'pharmacy_product', v_product.id, p_pharmacy_id,
                        jsonb_build_object('price', p_price));
  return to_jsonb(v_product);
end
$$;

-- NULL parameters mean "leave unchanged". Any call confirms the row (confirmed_at = now()).
create function public.update_pharmacy_product(
  p_product_id uuid,
  p_price numeric default null,
  p_is_available boolean default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pharmacy uuid;
  v_old public.pharmacy_products;
  v_new public.pharmacy_products;
begin
  perform private.assert_active_user();
  select pp.pharmacy_id into v_pharmacy from public.pharmacy_products pp where pp.id = p_product_id;
  if v_pharmacy is null then
    perform private.fail('not_found');
  end if;
  perform private.assert_member(v_pharmacy, array['owner', 'manager']::public.member_role[], true);
  if p_price is not null and (p_price <= 0 or p_price > 999999999999 or scale(p_price) > 2) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'price'));
  end if;

  select * into v_old from public.pharmacy_products where id = p_product_id for update;
  update public.pharmacy_products set
    price = coalesce(p_price, price),
    is_available = coalesce(p_is_available, is_available),
    confirmed_at = now()
  where id = p_product_id
  returning * into v_new;

  if v_new.price is distinct from v_old.price or v_new.is_available is distinct from v_old.is_available then
    perform private.audit('product_updated', 'pharmacy_product', p_product_id, v_pharmacy, jsonb_build_object(
      'price', jsonb_build_array(v_old.price, v_new.price),
      'is_available', jsonb_build_array(v_old.is_available, v_new.is_available)
    ));
  end if;
  return to_jsonb(v_new);
end
$$;

-- "My list is still correct today": refreshes the confirmation time of every available product.
create function public.confirm_listing(p_pharmacy_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  perform private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner', 'manager']::public.member_role[], true);
  update public.pharmacy_products set confirmed_at = now()
  where pharmacy_id = p_pharmacy_id and is_available;
  get diagnostics v_count = row_count;
  perform private.audit('listing_confirmed', 'pharmacy', p_pharmacy_id, p_pharmacy_id,
                        jsonb_build_object('products', v_count));
  return jsonb_build_object('confirmed', v_count);
end
$$;

-- Bulk import: [{medicine_id, price}] (at most max_import_items). Rows whose medicine is not an approved
-- catalogue entry, or whose price is not a positive amount with <= 2 decimals, are skipped (counted).
-- Existing rows get the new price and become available + confirmed. Duplicates in one call: the last wins.
create function public.bulk_upsert_pharmacy_products(p_pharmacy_id uuid, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_total integer;
  v_inserted integer;
  v_updated integer;
begin
  perform private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner', 'manager']::public.member_role[], true);
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > private.cfg_int('max_import_items') then
    perform private.fail('invalid_input', jsonb_build_object('field', 'items'));
  end if;
  if exists (select 1 from jsonb_array_elements(p_items) e where jsonb_typeof(e) <> 'object') then
    perform private.fail('invalid_input', jsonb_build_object('field', 'items'));
  end if;
  v_total := jsonb_array_length(p_items);

  with raw as (
    select x.medicine_id, x.price, x.ord
    from rows from (jsonb_to_recordset(p_items) as (medicine_id uuid, price numeric)) with ordinality as x (medicine_id, price, ord)
  ),
  valid as (
    select distinct on (r.medicine_id) r.medicine_id, r.price
    from raw r
    join public.medicines m on m.id = r.medicine_id and m.catalog_status = 'approved'
    where r.price is not null and r.price > 0 and r.price <= 999999999999 and scale(r.price) <= 2
    order by r.medicine_id, r.ord desc
  ),
  up as (
    insert into public.pharmacy_products as pp (pharmacy_id, medicine_id, price, is_available, confirmed_at)
    select p_pharmacy_id, v.medicine_id, v.price, true, now() from valid v
    on conflict (pharmacy_id, medicine_id) do update
      set price = excluded.price, is_available = true, confirmed_at = now()
    returning (xmax = 0) as was_inserted
  )
  select count(*) filter (where was_inserted), count(*) filter (where not was_inserted)
  into v_inserted, v_updated
  from up;

  perform private.audit('products_imported', 'pharmacy', p_pharmacy_id, p_pharmacy_id,
                        jsonb_build_object('inserted', v_inserted, 'updated', v_updated,
                                           'skipped', v_total - v_inserted - v_updated));
  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated,
                            'skipped', v_total - v_inserted - v_updated);
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch or invalid_parameter_value then
    perform private.fail('invalid_input', jsonb_build_object('field', 'items'));
end
$$;

-- Suggests approved catalogue entries for names typed in a pharmacy's own spreadsheet (top 3 per name).
-- Uses trigram *word similarity* (the typed name is short, the catalogue search text is long).
-- Only the client decides what to accept; nothing is written here.
create function public.match_medicine_names(p_names jsonb) returns table (
  idx integer, medicine_id uuid, name_ar text, name_en text, brand_name text, strength text,
  dosage_form text, score real
)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_uid uuid;
begin
  v_uid := private.assert_active_user();
  if not exists (
    select 1
    from public.pharmacy_members m
    join public.pharmacies ph on ph.id = m.pharmacy_id
    where m.user_id = v_uid and m.status = 'active'
      and m.role in ('owner', 'manager') and ph.approval_status = 'approved'
  ) then
    perform private.fail('forbidden');
  end if;
  if p_names is null or jsonb_typeof(p_names) <> 'array'
     or jsonb_array_length(p_names) = 0 or jsonb_array_length(p_names) > private.cfg_int('max_match_names') then
    perform private.fail('invalid_input', jsonb_build_object('field', 'names'));
  end if;
  if exists (select 1 from jsonb_array_elements(p_names) e where jsonb_typeof(e) <> 'string') then
    perform private.fail('invalid_input', jsonb_build_object('field', 'names'));
  end if;
  -- Threshold of the `<%` operator (transaction-local); candidates below it are not even considered.
  perform set_config('pg_trgm.word_similarity_threshold', '0.4', true);

  return query
  select n.idx, c.id, c.name_ar, c.name_en, c.brand_name, c.strength, c.dosage_form, c.score
  from (
    select o.ord::integer as idx, left(private.normalize_search(o.val), 200) as q
    from jsonb_array_elements_text(p_names) with ordinality as o (val, ord)
  ) n
  cross join lateral (
    select m.id, m.name_ar, m.name_en, m.brand_name, m.strength, m.dosage_form,
           extensions.word_similarity(n.q, m.search_text)::real as score
    from public.medicines m
    where m.catalog_status = 'approved'
      and char_length(n.q) >= 3
      and n.q operator(extensions.<%) m.search_text
    order by extensions.word_similarity(n.q, m.search_text) desc,
             extensions.similarity(n.q, m.search_text) desc, m.id
    limit 3
  ) c
  order by n.idx, c.score desc;
end
$$;
