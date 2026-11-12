-- Customer-facing reads (masked, paginated) and the pharmacy dashboard.
-- Customers never read pharmacies / pharmacy_products directly; these functions expose only what is public.
-- "Available" = the pharmacy marked it available AND confirmed it within listing_max_age_days.

-- ---------------------------------------------------------------------------
-- Medicine search (normalised Arabic/Latin substring match, trigram-indexed)
-- ---------------------------------------------------------------------------
create function public.search_medicines(
  p_query text,
  p_category_id uuid default null,
  p_dosage_form text default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns table (
  id uuid, name_ar text, name_en text, brand_name text, active_ingredient text, strength text,
  dosage_form text, package_description text, category_id uuid, pharmacy_count integer
)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_q text;
  v_tokens text[];
  v_p1 text := '%';
  v_p2 text := '%';
  v_p3 text := '%';
  v_p4 text := '%';
  v_form text := nullif(private.normalize_search(p_dosage_form), '');
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  perform private.assert_active_user();
  v_q := left(private.normalize_search(p_query), 100);
  if char_length(v_q) < 2 then
    return;
  end if;
  v_tokens := regexp_split_to_array(v_q, ' ');
  v_p1 := '%' || private.like_escape(v_tokens[1]) || '%';
  if array_length(v_tokens, 1) >= 2 then v_p2 := '%' || private.like_escape(v_tokens[2]) || '%'; end if;
  if array_length(v_tokens, 1) >= 3 then v_p3 := '%' || private.like_escape(v_tokens[3]) || '%'; end if;
  if array_length(v_tokens, 1) >= 4 then v_p4 := '%' || private.like_escape(v_tokens[4]) || '%'; end if;

  return query
  select m.id, m.name_ar, m.name_en, m.brand_name, m.active_ingredient, m.strength, m.dosage_form,
         m.package_description, m.category_id,
         (select count(*)::integer
          from public.pharmacy_products pp
          join public.pharmacies ph on ph.id = pp.pharmacy_id
          where pp.medicine_id = m.id and pp.is_available
            and pp.confirmed_at >= now() - make_interval(days => private.cfg_int('listing_max_age_days'))
            and ph.approval_status = 'approved' and ph.is_listed) as pharmacy_count
  from public.medicines m
  where m.catalog_status = 'approved'
    and m.search_text like v_p1
    and m.search_text like v_p2
    and m.search_text like v_p3
    and m.search_text like v_p4
    and (p_category_id is null or m.category_id = p_category_id)
    and (v_form is null or private.normalize_search(m.dosage_form) = v_form)
  order by (m.search_text like private.like_escape(v_tokens[1]) || '%') desc,
           extensions.similarity(m.search_text, v_q) desc,
           m.id
  limit v_limit offset v_offset;
end
$$;

-- ---------------------------------------------------------------------------
-- Pharmacies that list a medicine as available (confirmed recently), nearest first when a location is given
-- ---------------------------------------------------------------------------
create function public.get_medicine_pharmacies(
  p_medicine_id uuid,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_radius_km double precision default null,
  p_city text default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns table (
  pharmacy_id uuid, pharmacy_name text, city text, neighborhood text, address_line text, phone text,
  latitude double precision, longitude double precision, distance_km double precision,
  product_id uuid, price numeric, currency text, confirmed_at timestamptz, freshness text
)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_city text := nullif(private.normalize_search(p_city), '');
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_located boolean := p_latitude is not null or p_longitude is not null;
begin
  perform private.assert_active_user();
  if v_located then
    perform private.check_location(p_latitude, p_longitude);
  end if;
  if p_radius_km is not null and (not v_located or p_radius_km <= 0 or p_radius_km > 50) then
    perform private.fail('invalid_input', jsonb_build_object('field', 'radius_km'));
  end if;
  return query
  select t.pharmacy_id, t.pharmacy_name, t.city, t.neighborhood, t.address_line, t.phone,
         t.latitude, t.longitude, t.distance_km, t.product_id, t.price, t.currency, t.confirmed_at, t.freshness
  from (
    select ph.id as pharmacy_id, ph.name as pharmacy_name, ph.city, ph.neighborhood, ph.address_line,
           case when ph.show_phone_publicly then ph.phone else null end as phone,
           ph.latitude, ph.longitude,
           case when v_located and ph.latitude is not null
                then round(private.distance_km(p_latitude, p_longitude, ph.latitude, ph.longitude)::numeric, 2)::double precision
           end as distance_km,
           pp.id as product_id, pp.price, ph.currency, pp.confirmed_at,
           private.listing_freshness(pp.confirmed_at) as freshness
    from public.pharmacy_products pp
    join public.pharmacies ph on ph.id = pp.pharmacy_id
    join public.medicines m on m.id = pp.medicine_id
    where pp.medicine_id = p_medicine_id and pp.is_available
      and pp.confirmed_at >= now() - make_interval(days => private.cfg_int('listing_max_age_days'))
      and ph.approval_status = 'approved' and ph.is_listed
      and m.catalog_status = 'approved'
      and (v_city is null or private.normalize_search(ph.city) = v_city)
  ) t
  where p_radius_km is null or (t.distance_km is not null and t.distance_km <= p_radius_km)
  order by t.distance_km nulls last,
           (t.freshness = 'recent') desc,
           t.price, t.pharmacy_name, t.pharmacy_id
  limit v_limit offset v_offset;
end
$$;

-- ---------------------------------------------------------------------------
-- Public pharmacy directory
-- ---------------------------------------------------------------------------
create function public.list_public_pharmacies(
  p_query text default null,
  p_city text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_latitude double precision default null,
  p_longitude double precision default null
) returns table (
  id uuid, name text, city text, neighborhood text, address_line text, phone text, currency text,
  latitude double precision, longitude double precision, distance_km double precision
)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_q text := nullif(private.normalize_search(p_query), '');
  v_city text := nullif(private.normalize_search(p_city), '');
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_located boolean := p_latitude is not null or p_longitude is not null;
begin
  perform private.assert_active_user();
  if v_located then
    perform private.check_location(p_latitude, p_longitude);
  end if;
  return query
  select t.id, t.name, t.city, t.neighborhood, t.address_line, t.phone, t.currency,
         t.latitude, t.longitude, t.distance_km
  from (
    select ph.id, ph.name, ph.city, ph.neighborhood, ph.address_line,
           case when ph.show_phone_publicly then ph.phone else null end as phone, ph.currency,
           ph.latitude, ph.longitude,
           case when v_located and ph.latitude is not null
                then round(private.distance_km(p_latitude, p_longitude, ph.latitude, ph.longitude)::numeric, 2)::double precision
           end as distance_km
    from public.pharmacies ph
    where ph.approval_status = 'approved' and ph.is_listed
      and (v_q is null or private.normalize_search(ph.name) like '%' || private.like_escape(v_q) || '%')
      and (v_city is null or private.normalize_search(ph.city) = v_city)
  ) t
  order by t.distance_km nulls last, t.name, t.id
  limit v_limit offset v_offset;
end
$$;

create function public.get_public_pharmacy(p_pharmacy_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
begin
  perform private.assert_active_user();
  select jsonb_build_object(
    'id', ph.id, 'name', ph.name,
    'phone', case when ph.show_phone_publicly then ph.phone else null end,
    'address_line', ph.address_line, 'neighborhood', ph.neighborhood, 'city', ph.city,
    'directions', ph.directions, 'opening_hours', ph.opening_hours, 'currency', ph.currency,
    'latitude', ph.latitude, 'longitude', ph.longitude
  ) into v
  from public.pharmacies ph
  where ph.id = p_pharmacy_id and ph.approval_status = 'approved' and ph.is_listed;
  if v is null then
    perform private.fail('not_found');
  end if;
  return v;
end
$$;

create function public.get_public_pharmacy_products(
  p_pharmacy_id uuid,
  p_query text default null,
  p_category_id uuid default null,
  p_limit integer default 20,
  p_offset integer default 0
) returns table (
  product_id uuid, medicine_id uuid, name_ar text, name_en text, brand_name text, strength text,
  dosage_form text, price numeric, currency text, confirmed_at timestamptz, freshness text
)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_q text := nullif(private.normalize_search(p_query), '');
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  perform private.assert_active_user();
  if not exists (
    select 1 from public.pharmacies ph
    where ph.id = p_pharmacy_id and ph.approval_status = 'approved' and ph.is_listed
  ) then
    perform private.fail('not_found');
  end if;
  return query
  select pp.id, m.id, m.name_ar, m.name_en, m.brand_name, m.strength, m.dosage_form, pp.price, ph.currency,
         pp.confirmed_at, private.listing_freshness(pp.confirmed_at)
  from public.pharmacy_products pp
  join public.pharmacies ph on ph.id = pp.pharmacy_id
  join public.medicines m on m.id = pp.medicine_id
  where pp.pharmacy_id = p_pharmacy_id and pp.is_available and m.catalog_status = 'approved'
    and pp.confirmed_at >= now() - make_interval(days => private.cfg_int('listing_max_age_days'))
    and (v_q is null or m.search_text like '%' || private.like_escape(v_q) || '%')
    and (p_category_id is null or m.category_id = p_category_id)
  order by coalesce(nullif(m.name_ar, ''), m.name_en), pp.id
  limit v_limit offset v_offset;
end
$$;

-- ---------------------------------------------------------------------------
-- Dashboard
--   * Figures come only from completed sales (orders that were cancelled, rejected or expired never
--     create a sale). Returns/refunds are not part of the MVP, so none are netted out.
--   * Day boundaries use the pharmacy time zone; the week starts on Saturday.
-- ---------------------------------------------------------------------------
create function private.sales_period(p_pharmacy uuid, p_from date, p_to date, p_tz text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('total', coalesce(sum(s.total), 0), 'count', count(*))
  from public.sales s
  where s.pharmacy_id = p_pharmacy
    and s.created_at >= private.local_day_start(p_from, p_tz)
    and s.created_at < private.local_day_start(p_to + 1, p_tz)
$$;

create function public.pharmacy_dashboard(
  p_pharmacy_id uuid,
  p_from date default null,
  p_to date default null
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ph public.pharmacies;
  v_tz text;
  v_today date;
  v_from date;
  v_to date;
  v_week_start date;
  v_month_start date;
begin
  perform private.assert_active_user();
  perform private.assert_member(p_pharmacy_id, array['owner', 'manager']::public.member_role[], false);
  select * into v_ph from public.pharmacies where id = p_pharmacy_id;
  v_tz := v_ph.timezone;
  v_today := (now() at time zone v_tz)::date;
  v_to := coalesce(p_to, v_today);
  v_from := coalesce(p_from, v_to - 9);
  if v_from > v_to or v_to - v_from > 365 then
    perform private.fail('invalid_input', jsonb_build_object('field', 'range'));
  end if;
  v_week_start := v_today - ((extract(dow from v_today)::integer + 1) % 7);
  v_month_start := date_trunc('month', v_today)::date;

  return jsonb_build_object(
    'currency', v_ph.currency,
    'timezone', v_tz,
    'today', private.sales_period(p_pharmacy_id, v_today, v_today, v_tz),
    'week', private.sales_period(p_pharmacy_id, v_week_start, v_today, v_tz),
    'last_10_days', private.sales_period(p_pharmacy_id, v_today - 9, v_today, v_tz),
    'month', private.sales_period(p_pharmacy_id, v_month_start, v_today, v_tz),
    'range', jsonb_build_object('from', v_from, 'to', v_to) || private.sales_period(p_pharmacy_id, v_from, v_to, v_tz),
    'daily_series', coalesce((
      select jsonb_agg(jsonb_build_object('day', d.day, 'total', coalesce(t.total, 0), 'count', coalesce(t.cnt, 0)) order by d.day)
      from (select v_from + n as day from generate_series(0, v_to - v_from) n) d
      left join (
        select (s.created_at at time zone v_tz)::date as day, sum(s.total) as total, count(*) as cnt
        from public.sales s
        where s.pharmacy_id = p_pharmacy_id
          and s.created_at >= private.local_day_start(v_from, v_tz)
          and s.created_at < private.local_day_start(v_to + 1, v_tz)
        group by 1
      ) t on t.day = d.day
    ), '[]'::jsonb),
    'best_sellers', coalesce((
      select jsonb_agg(b order by b.quantity desc, b.name)
      from (
        select si.product_id, si.product_name as name, sum(si.quantity)::integer as quantity,
               sum(si.line_total) as revenue
        from public.sale_items si
        join public.sales s on s.id = si.sale_id
        where s.pharmacy_id = p_pharmacy_id
          and s.created_at >= private.local_day_start(v_from, v_tz)
          and s.created_at < private.local_day_start(v_to + 1, v_tz)
        group by si.product_id, si.product_name
        order by sum(si.quantity) desc, si.product_name
        limit 5
      ) b
    ), '[]'::jsonb),
    'listing', jsonb_build_object(
      'available', (select count(*) from public.pharmacy_products pp
                    where pp.pharmacy_id = p_pharmacy_id and pp.is_available),
      'unavailable', (select count(*) from public.pharmacy_products pp
                      where pp.pharmacy_id = p_pharmacy_id and not pp.is_available),
      'stale', (select count(*) from public.pharmacy_products pp
                where pp.pharmacy_id = p_pharmacy_id and pp.is_available
                  and pp.confirmed_at < now() - make_interval(days => private.cfg_int('fresh_days')))
    ),
    'open_requests_count', private.open_request_count(p_pharmacy_id),
    'pending_orders_count', (
      select count(*) from public.orders o where o.pharmacy_id = p_pharmacy_id and o.status = 'pending'
    ),
    'recent_orders', coalesce((
      select jsonb_agg(ro order by ro.created_at desc)
      from (
        select o.id, o.public_ref, o.status, o.subtotal, o.currency, o.created_at, o.customer_name
        from public.orders o
        where o.pharmacy_id = p_pharmacy_id
        order by o.created_at desc
        limit 10
      ) ro
    ), '[]'::jsonb)
  );
end
$$;
