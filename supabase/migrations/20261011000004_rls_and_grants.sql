-- Row Level Security, grants and policies.
-- Strategy: deny everything, then grant the minimum. Writes with business meaning go through
-- SECURITY DEFINER functions (later migrations); tables without a write policy are read-only to clients.

-- ---------------------------------------------------------------------------
-- 1. Override Supabase's permissive default grants
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon, authenticated;
alter default privileges in schema private revoke execute on functions from anon, authenticated;

-- private schema: usable (for policy helpers) but not exposed through the API.
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.is_member(uuid, public.member_role[]) to authenticated;
grant execute on function private.normalize_search(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Enable RLS on every table
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.pharmacies enable row level security;
alter table public.pharmacy_members enable row level security;
alter table public.medicine_categories enable row level security;
alter table public.medicines enable row level security;
alter table public.pharmacy_products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.audit_logs enable row level security;
alter table public.user_reports enable row level security;
alter table public.notifications enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.pharmacy_invoice_counters enable row level security;
alter table public.availability_requests enable row level security;
alter table public.availability_targets enable row level security;

-- ---------------------------------------------------------------------------
-- 3. Grants (SELECT only unless stated). Policies below decide which rows.
-- ---------------------------------------------------------------------------
grant select on
  public.profiles, public.pharmacies, public.pharmacy_members, public.medicine_categories,
  public.medicines, public.pharmacy_products, public.orders,
  public.order_items, public.sales, public.sale_items,
  public.audit_logs, public.user_reports, public.notifications
to authenticated;

-- Profiles: users may edit only these columns of their own row.
grant update (display_name, phone, locale) on public.profiles to authenticated;

-- Reports: users may file reports (reporter_id/status are server-controlled).
grant insert (target_type, target_id, category, description) on public.user_reports to authenticated;

-- Notifications: users may mark their own as read.
grant update (read_at) on public.notifications to authenticated;

-- Catalogue: admin-only writes (enforced by policy; non-admins fail RLS).
grant insert (name_ar, name_en, sort_order, is_active) on public.medicine_categories to authenticated;
grant update (name_ar, name_en, sort_order, is_active) on public.medicine_categories to authenticated;
grant insert (category_id, name_ar, name_en, brand_name, active_ingredient, strength, dosage_form,
              package_description, catalog_status) on public.medicines to authenticated;
grant update (category_id, name_ar, name_en, brand_name, active_ingredient, strength, dosage_form,
              package_description, catalog_status) on public.medicines to authenticated;

-- Everything else (pharmacies, products, orders, sales, ...) has NO client write grant.
-- idempotency_keys, pharmacy_invoice_counters, availability_requests, availability_targets: no client access at all.

-- ---------------------------------------------------------------------------
-- 4. Policies
-- ---------------------------------------------------------------------------
-- profiles
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy profiles_select_admin on public.profiles
  for select to authenticated using (private.is_admin() and role <> 'customer');
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- pharmacies: members, owner and admin only. Customers use the public RPCs (masked data).
create policy pharmacies_select on public.pharmacies
  for select to authenticated
  using (owner_id = (select auth.uid()) or private.is_member(id) or private.is_admin());

-- pharmacy_members
create policy pharmacy_members_select_own on public.pharmacy_members
  for select to authenticated using (user_id = (select auth.uid()));
create policy pharmacy_members_select_owner on public.pharmacy_members
  for select to authenticated
  using (private.is_member(pharmacy_id, array['owner']::public.member_role[]));
create policy pharmacy_members_select_admin on public.pharmacy_members
  for select to authenticated using (private.is_admin());

-- medicine_categories
create policy medicine_categories_select on public.medicine_categories
  for select to authenticated using (is_active or private.is_admin());
create policy medicine_categories_insert_admin on public.medicine_categories
  for insert to authenticated with check (private.is_admin());
create policy medicine_categories_update_admin on public.medicine_categories
  for update to authenticated using (private.is_admin()) with check (private.is_admin());

-- medicines
create policy medicines_select on public.medicines
  for select to authenticated
  using (catalog_status = 'approved' or proposed_by = (select auth.uid()) or private.is_admin());
create policy medicines_insert_admin on public.medicines
  for insert to authenticated with check (private.is_admin());
create policy medicines_update_admin on public.medicines
  for update to authenticated using (private.is_admin()) with check (private.is_admin());

-- pharmacy_products: active members of that pharmacy.
create policy pharmacy_products_select on public.pharmacy_products
  for select to authenticated using (private.is_member(pharmacy_id));

-- orders: the customer, or members of the order's pharmacy. Admins get nothing (privacy).
create policy orders_select on public.orders
  for select to authenticated
  using (customer_id = (select auth.uid()) or private.is_member(pharmacy_id));

-- order_items inherit order visibility (the subquery is itself subject to orders RLS).
create policy order_items_select on public.order_items
  for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));

-- sales: owner/manager see all, cashier sees own sales.
create policy sales_select on public.sales
  for select to authenticated
  using (
    private.is_member(pharmacy_id, array['owner', 'manager']::public.member_role[])
    or (cashier_id = (select auth.uid()) and private.is_member(pharmacy_id))
  );
create policy sale_items_select on public.sale_items
  for select to authenticated
  using (exists (select 1 from public.sales s where s.id = sale_id));

-- audit_logs: admin only.
create policy audit_logs_select_admin on public.audit_logs
  for select to authenticated using (private.is_admin());

-- user_reports
create policy user_reports_insert_own on public.user_reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));
create policy user_reports_select_own on public.user_reports
  for select to authenticated using (reporter_id = (select auth.uid()));
create policy user_reports_select_admin on public.user_reports
  for select to authenticated using (private.is_admin());

-- notifications
create policy notifications_select_own on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- idempotency_keys / pharmacy_invoice_counters / availability_requests / availability_targets:
-- RLS on, no policies, no grants => unreachable by clients (RPC functions only).
