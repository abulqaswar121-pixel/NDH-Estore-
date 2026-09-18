begin;

create extension if not exists pgcrypto;

create type public.app_role as enum ('admin', 'vendor', 'customer');
create type public.vendor_archetype as enum ('wigs_fashion', 'marketplace', 'grocery_food', 'wholesale_pod', 'cargo_logistics', 'travel_tours', 'freelance_services', 'event_ticketing', 'digital_products', 'rentals_subscriptions');
create type public.subscription_tier as enum ('starter', 'pro', 'global_enterprise');
create type public.subscription_status as enum ('trial', 'active', 'past_due', 'expired');
create type public.billing_cycle as enum ('monthly', 'yearly');
create type public.product_type as enum ('physical', 'booking', 'service', 'digital');
create type public.order_status as enum ('pending', 'awaiting_payment', 'paid', 'processing', 'fulfilled', 'cancelled', 'refunded');
create type public.payment_provider as enum ('paystack', 'flutterwave', 'stripe', 'bank_transfer', 'whatsapp');
create type public.payout_status as enum ('requested', 'processing', 'paid', 'failed', 'cancelled');

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text not null default '',
  avatar_url text,
  phone_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default now(),
  unique (user_id, role)
);

create or replace function public.has_role(requested_user_id uuid, requested_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = requested_user_id and role = requested_role
  );
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select public.has_role(auth.uid(), 'admin'::public.app_role); $$;

create table public.vendors (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references public.users(id) on delete cascade,
  email text not null,
  business_name text not null check (char_length(business_name) between 2 and 120),
  shop_slug text not null unique check (shop_slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  whatsapp_number text not null,
  business_category public.vendor_archetype not null,
  business_description text not null default '',
  support_email text,
  address jsonb not null default '{}'::jsonb,
  social_links jsonb not null default '{}'::jsonb,
  design_settings jsonb not null default '{"selected_dna":"minimal_luxe","nav_style":"centered","typography":"Inter","primary_accent":"#143d2e","background_accent":"#f7f8f5","announcement_text":"","enabled_pages":["shop"],"homepage_order":["hero","featured","products"],"show_newsletter":true,"logo_shape":"rounded","logo_text":"ND","logo_url":null}'::jsonb,
  subscription_tier public.subscription_tier not null default 'starter',
  billing_cycle public.billing_cycle not null default 'monthly',
  subscription_status public.subscription_status not null default 'trial',
  trial_end_date timestamptz not null default (now() + interval '14 days'),
  current_period_end timestamptz not null default (now() + interval '14 days'),
  platform_fee_percentage numeric(5,2) not null default 2.50 check (platform_fee_percentage between 0 and 100),
  default_currency char(3) not null default 'NGN',
  timezone text not null default 'Africa/Lagos',
  meta_pixel_id text,
  meta_capi_token_encrypted text,
  seo_title text,
  seo_description text,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 180),
  slug text not null,
  description text not null default '',
  base_price numeric(14,2) not null check (base_price >= 0),
  compare_at_price numeric(14,2) check (compare_at_price is null or compare_at_price >= 0),
  image_url text not null default '',
  image_urls jsonb not null default '[]'::jsonb,
  category text not null default 'General',
  is_featured boolean not null default false,
  is_active boolean not null default true,
  stock_count integer not null default 0 check (stock_count >= 0),
  product_type public.product_type not null default 'physical',
  weight_kg numeric(10,3) not null default 0 check (weight_kg >= 0),
  volume_cbm numeric(10,4) not null default 0 check (volume_cbm >= 0),
  allocation_threshold integer check (allocation_threshold is null or allocation_threshold >= 0),
  digital_file_path text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (vendor_id, slug)
);

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  variant_name text not null,
  variant_value text not null,
  sku text,
  price_modifier numeric(14,2) not null default 0,
  stock_count integer not null default 0 check (stock_count >= 0),
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, variant_name, variant_value)
);

create table public.shipping_zones (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  country_code char(2) not null default 'NG',
  state text not null,
  zone_name text not null,
  fee numeric(14,2) not null check (fee >= 0),
  estimated_days_min integer check (estimated_days_min >= 0),
  estimated_days_max integer check (estimated_days_max >= estimated_days_min),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (vendor_id, country_code, state, zone_name)
);

create table public.cargo_profiles (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  name text not null,
  origin_country char(2) not null default 'NG',
  destination_country char(2) not null,
  transport_mode text not null check (transport_mode in ('air', 'ocean', 'road', 'rail')),
  metric text not null check (metric in ('kg', 'cbm', 'flat')),
  rate numeric(14,2) not null check (rate >= 0),
  currency char(3) not null default 'NGN',
  minimum_charge numeric(14,2) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number bigint generated always as identity unique,
  vendor_id uuid not null references public.vendors(id) on delete restrict,
  customer_id uuid references public.users(id) on delete set null,
  customer_email text not null,
  customer_name text not null,
  customer_phone text,
  status public.order_status not null default 'pending',
  payment_provider public.payment_provider,
  payment_reference text unique,
  currency char(3) not null default 'NGN',
  subtotal numeric(14,2) not null check (subtotal >= 0),
  shipping_fee numeric(14,2) not null default 0 check (shipping_fee >= 0),
  platform_fee numeric(14,2) not null default 0 check (platform_fee >= 0),
  payment_processing_fee numeric(14,2) not null default 0 check (payment_processing_fee >= 0),
  total numeric(14,2) not null check (total >= 0),
  shipping_address jsonb,
  delivery_zone_id uuid references public.shipping_zones(id) on delete set null,
  customer_note text,
  metadata jsonb not null default '{}'::jsonb,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  variant_id uuid references public.product_variants(id) on delete set null,
  product_name text not null,
  variant_description text,
  quantity integer not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  weight_kg numeric(10,3) not null default 0,
  total_price numeric(14,2) generated always as (quantity * unit_price) stored,
  created_at timestamptz not null default now()
);

create table public.payouts (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  currency char(3) not null default 'NGN',
  status public.payout_status not null default 'requested',
  bank_account_snapshot jsonb not null,
  provider_reference text unique,
  failure_reason text,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  customer_id uuid references public.users(id) on delete set null,
  order_id uuid references public.orders(id) on delete set null,
  customer_name text not null,
  rating smallint not null check (rating between 1 and 5),
  body text not null default '',
  is_verified boolean not null default false,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id, product_id)
);

create table public.booking_slots (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at),
  capacity integer not null check (capacity > 0),
  reserved_count integer not null default 0 check (reserved_count >= 0 and reserved_count <= capacity),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (product_id, starts_at)
);

create table public.subscription_events (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  provider public.payment_provider not null,
  provider_reference text not null unique,
  event_type text not null,
  amount numeric(14,2),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index products_vendor_active_idx on public.products(vendor_id, is_active);
create index orders_vendor_created_idx on public.orders(vendor_id, created_at desc);
create index orders_customer_created_idx on public.orders(customer_id, created_at desc);
create index payouts_vendor_created_idx on public.payouts(vendor_id, created_at desc);
create index reviews_product_published_idx on public.reviews(product_id, is_published);
create index shipping_zones_vendor_idx on public.shipping_zones(vendor_id, active);
create index cargo_profiles_vendor_idx on public.cargo_profiles(vendor_id, active);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end; $$;

create trigger users_updated_at before update on public.users for each row execute function public.set_updated_at();
create trigger vendors_updated_at before update on public.vendors for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();
create trigger variants_updated_at before update on public.product_variants for each row execute function public.set_updated_at();
create trigger zones_updated_at before update on public.shipping_zones for each row execute function public.set_updated_at();
create trigger cargo_updated_at before update on public.cargo_profiles for each row execute function public.set_updated_at();
create trigger orders_updated_at before update on public.orders for each row execute function public.set_updated_at();
create trigger payouts_updated_at before update on public.payouts for each row execute function public.set_updated_at();
create trigger reviews_updated_at before update on public.reviews for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id, email, full_name)
  values (new.id, coalesce(new.email, ''), coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  insert into public.user_roles (user_id, role) values (new.id, 'customer') on conflict do nothing;
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.users enable row level security;
alter table public.user_roles enable row level security;
alter table public.vendors enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.shipping_zones enable row level security;
alter table public.cargo_profiles enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payouts enable row level security;
alter table public.reviews enable row level security;
alter table public.booking_slots enable row level security;
alter table public.subscription_events enable row level security;

create policy users_read_own on public.users for select using (id = auth.uid() or public.is_admin());
create policy users_update_own on public.users for update using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());
create policy roles_read_own on public.user_roles for select using (user_id = auth.uid() or public.is_admin());
create policy roles_admin_manage on public.user_roles for all using (public.is_admin()) with check (public.is_admin());

create policy vendors_public_read on public.vendors for select using (published = true or owner_user_id = auth.uid() or public.is_admin());
create policy vendors_owner_insert on public.vendors for insert with check (owner_user_id = auth.uid() and public.has_role(auth.uid(), 'vendor'));
create policy vendors_owner_update on public.vendors for update using (owner_user_id = auth.uid() or public.is_admin()) with check (owner_user_id = auth.uid() or public.is_admin());
create policy vendors_owner_delete on public.vendors for delete using (owner_user_id = auth.uid() or public.is_admin());

create policy products_public_read on public.products for select using (is_active = true or exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy products_owner_insert on public.products for insert with check (exists(select 1 from public.vendors v where v.id = vendor_id and v.owner_user_id = auth.uid()));
create policy products_owner_update on public.products for update using (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin()))) with check (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy products_owner_delete on public.products for delete using (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));

create policy variants_public_read on public.product_variants for select using (exists(select 1 from public.products p where p.id = product_id and (p.is_active or exists(select 1 from public.vendors v where v.id = p.vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())))));
create policy variants_owner_manage on public.product_variants for all using (exists(select 1 from public.products p join public.vendors v on v.id = p.vendor_id where p.id = product_id and (v.owner_user_id = auth.uid() or public.is_admin()))) with check (exists(select 1 from public.products p join public.vendors v on v.id = p.vendor_id where p.id = product_id and (v.owner_user_id = auth.uid() or public.is_admin())));

create policy zones_public_read on public.shipping_zones for select using (active or exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy zones_owner_manage on public.shipping_zones for all using (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin()))) with check (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy cargo_public_read on public.cargo_profiles for select using (active or exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy cargo_owner_manage on public.cargo_profiles for all using (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin()))) with check (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));

create policy orders_customer_read on public.orders for select using (customer_id = auth.uid() or exists(select 1 from public.vendors v where v.id = vendor_id and v.owner_user_id = auth.uid()) or public.is_admin());
create policy orders_authenticated_insert on public.orders for insert with check (customer_id is null or customer_id = auth.uid());
create policy orders_vendor_update on public.orders for update using (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin()))) with check (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy items_order_read on public.order_items for select using (exists(select 1 from public.orders o join public.vendors v on v.id = o.vendor_id where o.id = order_id and (o.customer_id = auth.uid() or v.owner_user_id = auth.uid() or public.is_admin())));
create policy items_order_insert on public.order_items for insert with check (exists(select 1 from public.orders o where o.id = order_id and (o.customer_id = auth.uid() or o.customer_id is null)));

create policy payouts_vendor_read on public.payouts for select using (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy payouts_vendor_insert on public.payouts for insert with check (exists(select 1 from public.vendors v where v.id = vendor_id and v.owner_user_id = auth.uid()));
create policy payouts_admin_update on public.payouts for update using (public.is_admin()) with check (public.is_admin());

create policy reviews_public_read on public.reviews for select using (is_published or customer_id = auth.uid() or exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy reviews_customer_insert on public.reviews for insert with check (customer_id = auth.uid());
create policy reviews_owner_moderate on public.reviews for update using (customer_id = auth.uid() or exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));

create policy slots_public_read on public.booking_slots for select using (active or exists(select 1 from public.products p join public.vendors v on v.id = p.vendor_id where p.id = product_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy slots_owner_manage on public.booking_slots for all using (exists(select 1 from public.products p join public.vendors v on v.id = p.vendor_id where p.id = product_id and (v.owner_user_id = auth.uid() or public.is_admin()))) with check (exists(select 1 from public.products p join public.vendors v on v.id = p.vendor_id where p.id = product_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy subscription_events_owner_read on public.subscription_events for select using (exists(select 1 from public.vendors v where v.id = vendor_id and (v.owner_user_id = auth.uid() or public.is_admin())));
create policy subscription_events_admin_manage on public.subscription_events for all using (public.is_admin()) with check (public.is_admin());

revoke all on function public.has_role(uuid, public.app_role) from public;
grant execute on function public.has_role(uuid, public.app_role) to authenticated;
grant execute on function public.is_admin() to authenticated;

commit;
