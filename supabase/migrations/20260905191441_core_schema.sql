-- Chez Yasmine — core multi-tenant schema
-- Organization > Establishment > PointOfSale, plus catalog, stock, POS, tables,
-- customers/credit, expenses/cash, and system tables (sync, audit, notifications).
-- RLS is enabled and policies are defined in a separate migration
-- (20260905190100_rls_policies.sql) so schema and access-control review stay separate.

create extension if not exists pgcrypto;

-- ── Tenancy ──────────────────────────────────────────────────────────────

create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table establishments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  address text,
  currency text not null default 'FCFA',
  created_at timestamptz not null default now()
);
create index establishments_organization_id_idx on establishments(organization_id);

create table points_of_sale (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);
create index points_of_sale_establishment_id_idx on points_of_sale(establishment_id);

-- ── Users / RBAC ─────────────────────────────────────────────────────────
-- Identity itself lives in Supabase Auth (auth.users). user_profiles mirrors
-- it 1:1 and carries the organization link + app-specific fields.

create table user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);
create index user_profiles_organization_id_idx on user_profiles(organization_id);

create table roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id) on delete cascade,
  name text not null,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);
create index roles_organization_id_idx on roles(organization_id);

create table permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text
);

create table role_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  permission_id uuid not null references permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table user_establishment_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references user_profiles(id) on delete cascade,
  establishment_id uuid not null references establishments(id) on delete cascade,
  role_id uuid not null references roles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, establishment_id, role_id)
);
create index user_establishment_roles_user_id_idx on user_establishment_roles(user_id);
create index user_establishment_roles_establishment_id_idx on user_establishment_roles(establishment_id);

-- ── Catalog ──────────────────────────────────────────────────────────────

create table categories (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);
create index categories_establishment_id_idx on categories(establishment_id);

create table suppliers (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  name text not null,
  phone text,
  address text,
  created_at timestamptz not null default now()
);
create index suppliers_establishment_id_idx on suppliers(establishment_id);

create table products (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  category_id uuid references categories(id) on delete set null,
  supplier_id uuid references suppliers(id) on delete set null,
  name text not null,
  reference text,
  description text,
  barcode text,
  qr_code text,
  unit text,
  purchase_price numeric(12,2),
  sale_price numeric(12,2) not null,
  vat_rate numeric(5,2) not null default 0,
  min_stock numeric(12,2) not null default 0,
  stock_quantity numeric(12,2) not null default 0,
  status text not null default 'active' check (status in ('active','archived')),
  created_at timestamptz not null default now()
);
create index products_establishment_id_idx on products(establishment_id);
create index products_category_id_idx on products(category_id);

create table product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  storage_path text not null,
  is_primary boolean not null default false,
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create index product_images_product_id_idx on product_images(product_id);

-- ── Stock ────────────────────────────────────────────────────────────────

create table stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  type text not null check (type in ('in','out','adjustment','sale','loss','transfer')),
  quantity numeric(12,2) not null,
  reason text,
  created_by uuid references user_profiles(id),
  created_at timestamptz not null default now()
);
create index stock_movements_product_id_idx on stock_movements(product_id);
create index stock_movements_created_at_idx on stock_movements(created_at);

-- ── Purchases ────────────────────────────────────────────────────────────

create table purchases (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  supplier_id uuid references suppliers(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','received','cancelled')),
  total numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);
create index purchases_establishment_id_idx on purchases(establishment_id);

create table purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references purchases(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity numeric(12,2) not null,
  unit_price numeric(12,2) not null
);
create index purchase_items_purchase_id_idx on purchase_items(purchase_id);

-- ── Tables / service à table ─────────────────────────────────────────────

create table restaurant_tables (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  name text not null,
  zone text,
  status text not null default 'free' check (status in ('free','occupied','billing')),
  created_at timestamptz not null default now()
);
create index restaurant_tables_establishment_id_idx on restaurant_tables(establishment_id);

create table reservations (
  id uuid primary key default gen_random_uuid(),
  table_id uuid not null references restaurant_tables(id) on delete cascade,
  customer_name text,
  phone text,
  reserved_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','confirmed','cancelled','seated')),
  created_at timestamptz not null default now()
);
create index reservations_table_id_idx on reservations(table_id);

create table orders (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  table_id uuid references restaurant_tables(id) on delete set null,
  server_id uuid references user_profiles(id),
  status text not null default 'open' check (status in ('open','closed')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz
);
create index orders_establishment_id_idx on orders(establishment_id);
create index orders_table_id_idx on orders(table_id);

create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity numeric(12,2) not null,
  unit_price numeric(12,2) not null,
  added_at timestamptz not null default now()
);
create index order_items_order_id_idx on order_items(order_id);

-- ── Customers / crédit ───────────────────────────────────────────────────

create table customers (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  name text not null,
  phone text,
  address text,
  credit_balance numeric(12,2) not null default 0,
  credit_limit numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);
create index customers_establishment_id_idx on customers(establishment_id);

-- ── Sales / POS ──────────────────────────────────────────────────────────

create table sales (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  point_of_sale_id uuid references points_of_sale(id),
  source text not null default 'pos' check (source in ('pos','table')),
  table_id uuid references restaurant_tables(id),
  order_id uuid references orders(id),
  customer_id uuid references customers(id) on delete set null,
  subtotal numeric(12,2) not null,
  discount numeric(12,2) not null default 0,
  total numeric(12,2) not null,
  created_by uuid references user_profiles(id),
  created_at timestamptz not null default now()
);
create index sales_establishment_id_idx on sales(establishment_id);
create index sales_customer_id_idx on sales(customer_id);
create index sales_created_at_idx on sales(created_at);

create table sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references sales(id) on delete cascade,
  product_id uuid not null references products(id),
  name text not null,
  quantity numeric(12,2) not null,
  unit_price numeric(12,2) not null
);
create index sale_items_sale_id_idx on sale_items(sale_id);

create table payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references sales(id) on delete cascade,
  method text not null check (method in ('cash','mobile_money','card','credit')),
  amount numeric(12,2) not null,
  created_at timestamptz not null default now()
);
create index payments_sale_id_idx on payments(sale_id);

create table credits (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete cascade,
  sale_id uuid references sales(id) on delete set null,
  amount numeric(12,2) not null,
  created_at timestamptz not null default now()
);
create index credits_customer_id_idx on credits(customer_id);

create table credit_payments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete cascade,
  amount numeric(12,2) not null,
  created_at timestamptz not null default now()
);
create index credit_payments_customer_id_idx on credit_payments(customer_id);

-- ── Dépenses / pertes / caisse / comptabilité ────────────────────────────

create table expenses (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  label text not null,
  category text,
  amount numeric(12,2) not null,
  expense_date date not null default current_date,
  note text,
  created_at timestamptz not null default now()
);
create index expenses_establishment_id_idx on expenses(establishment_id);

create table losses (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity numeric(12,2) not null,
  reason text,
  created_by uuid references user_profiles(id),
  created_at timestamptz not null default now()
);
create index losses_establishment_id_idx on losses(establishment_id);

create table cash_registers (
  id uuid primary key default gen_random_uuid(),
  point_of_sale_id uuid not null references points_of_sale(id) on delete cascade,
  name text not null
);
create index cash_registers_point_of_sale_id_idx on cash_registers(point_of_sale_id);

create table cash_closings (
  id uuid primary key default gen_random_uuid(),
  cash_register_id uuid not null references cash_registers(id) on delete cascade,
  opened_at timestamptz not null,
  closed_at timestamptz not null default now(),
  expected_amount numeric(12,2) not null,
  counted_amount numeric(12,2) not null,
  closed_by uuid references user_profiles(id)
);
create index cash_closings_cash_register_id_idx on cash_closings(cash_register_id);

create table accounting_entries (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  entry_type text not null,
  amount numeric(12,2) not null,
  reference_id uuid,
  created_at timestamptz not null default now()
);
create index accounting_entries_establishment_id_idx on accounting_entries(establishment_id);

create table server_commissions (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references user_profiles(id) on delete cascade,
  sale_id uuid not null references sales(id) on delete cascade,
  amount numeric(12,2) not null,
  created_at timestamptz not null default now()
);
create index server_commissions_server_id_idx on server_commissions(server_id);

-- ── Système : notifications, abonnement, synchronisation, audit ─────────

create table notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  user_id uuid references user_profiles(id) on delete cascade,
  title text not null,
  body text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_organization_id_idx on notifications(organization_id);
create index notifications_user_id_idx on notifications(user_id);

create table subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  plan text not null default 'free',
  status text not null default 'active' check (status in ('active','past_due','cancelled')),
  current_period_end timestamptz,
  created_at timestamptz not null default now()
);
create index subscriptions_organization_id_idx on subscriptions(organization_id);

-- Journal de synchronisation offline-first (prompt maître §26-27) : chaque
-- opération émise par un client est idempotente via son id (généré client).
create table sync_operations (
  id uuid primary key default gen_random_uuid(),
  operation_type text not null,
  entity_type text not null,
  entity_id uuid,
  payload jsonb not null,
  user_id uuid references user_profiles(id),
  device_id text not null,
  status text not null default 'PENDING' check (status in ('PENDING','SYNCING','SYNCED','FAILED','CONFLICT')),
  attempt_count integer not null default 0,
  created_at timestamptz not null default now()
);
create index sync_operations_status_idx on sync_operations(status);
create index sync_operations_entity_idx on sync_operations(entity_type, entity_id);

create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id) on delete cascade,
  user_id uuid references user_profiles(id),
  action text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_organization_id_idx on audit_logs(organization_id);
create index audit_logs_created_at_idx on audit_logs(created_at);
