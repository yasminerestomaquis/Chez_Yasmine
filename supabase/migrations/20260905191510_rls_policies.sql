-- Chez Yasmine — Row Level Security
--
-- Isolation multi-tenant (prompt maître §15, §35) : un utilisateur authentifié
-- ne doit jamais pouvoir lire ou écrire les données d'une autre organisation.
--
-- Ceci est une isolation de *tenant*, pas le RBAC applicatif fin (rôles/permissions
-- métier) : ce dernier est appliqué par NestJS (cf. CLAUDE.md). `service_role`
-- (utilisé exclusivement côté NestJS) contourne RLS via son attribut BYPASSRLS —
-- ces policies protègent donc la clé `anon`/`authenticated`, jamais utilisée pour
-- les opérations métier critiques mais présente en défense en profondeur.

-- ── Fonctions utilitaires (SECURITY DEFINER pour éviter la récursion RLS) ──

create or replace function current_user_organization_id()
returns uuid
language sql
security definer
stable
set search_path = public
as $$
  select organization_id from user_profiles where id = auth.uid()
$$;

create or replace function user_has_establishment_access(target_establishment_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from establishments e
    where e.id = target_establishment_id
      and e.organization_id = current_user_organization_id()
  )
$$;

-- ── Tenancy ──────────────────────────────────────────────────────────────

alter table organizations enable row level security;
create policy tenant_isolation on organizations for all to authenticated
  using (id = current_user_organization_id())
  with check (id = current_user_organization_id());

alter table establishments enable row level security;
create policy tenant_isolation on establishments for all to authenticated
  using (organization_id = current_user_organization_id())
  with check (organization_id = current_user_organization_id());

alter table points_of_sale enable row level security;
create policy tenant_isolation on points_of_sale for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

-- ── Users / RBAC ─────────────────────────────────────────────────────────

alter table user_profiles enable row level security;
create policy tenant_isolation on user_profiles for all to authenticated
  using (organization_id = current_user_organization_id())
  with check (organization_id = current_user_organization_id());

alter table roles enable row level security;
create policy tenant_isolation on roles for all to authenticated
  using (organization_id is null or organization_id = current_user_organization_id())
  with check (organization_id is null or organization_id = current_user_organization_id());

alter table permissions enable row level security;
create policy readable_by_authenticated on permissions for select to authenticated using (true);

alter table role_permissions enable row level security;
create policy tenant_isolation on role_permissions for all to authenticated
  using (exists (select 1 from roles r where r.id = role_id and (r.organization_id is null or r.organization_id = current_user_organization_id())))
  with check (exists (select 1 from roles r where r.id = role_id and (r.organization_id is null or r.organization_id = current_user_organization_id())));

alter table user_establishment_roles enable row level security;
create policy tenant_isolation on user_establishment_roles for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

-- ── Catalog ──────────────────────────────────────────────────────────────

alter table categories enable row level security;
create policy tenant_isolation on categories for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table suppliers enable row level security;
create policy tenant_isolation on suppliers for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table products enable row level security;
create policy tenant_isolation on products for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table product_images enable row level security;
create policy tenant_isolation on product_images for all to authenticated
  using (exists (select 1 from products p where p.id = product_id and user_has_establishment_access(p.establishment_id)))
  with check (exists (select 1 from products p where p.id = product_id and user_has_establishment_access(p.establishment_id)));

-- ── Stock ────────────────────────────────────────────────────────────────

alter table stock_movements enable row level security;
create policy tenant_isolation on stock_movements for all to authenticated
  using (exists (select 1 from products p where p.id = product_id and user_has_establishment_access(p.establishment_id)))
  with check (exists (select 1 from products p where p.id = product_id and user_has_establishment_access(p.establishment_id)));

-- ── Purchases ────────────────────────────────────────────────────────────

alter table purchases enable row level security;
create policy tenant_isolation on purchases for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table purchase_items enable row level security;
create policy tenant_isolation on purchase_items for all to authenticated
  using (exists (select 1 from purchases pu where pu.id = purchase_id and user_has_establishment_access(pu.establishment_id)))
  with check (exists (select 1 from purchases pu where pu.id = purchase_id and user_has_establishment_access(pu.establishment_id)));

-- ── Tables / service à table ─────────────────────────────────────────────

alter table restaurant_tables enable row level security;
create policy tenant_isolation on restaurant_tables for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table reservations enable row level security;
create policy tenant_isolation on reservations for all to authenticated
  using (exists (select 1 from restaurant_tables t where t.id = table_id and user_has_establishment_access(t.establishment_id)))
  with check (exists (select 1 from restaurant_tables t where t.id = table_id and user_has_establishment_access(t.establishment_id)));

alter table orders enable row level security;
create policy tenant_isolation on orders for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table order_items enable row level security;
create policy tenant_isolation on order_items for all to authenticated
  using (exists (select 1 from orders o where o.id = order_id and user_has_establishment_access(o.establishment_id)))
  with check (exists (select 1 from orders o where o.id = order_id and user_has_establishment_access(o.establishment_id)));

-- ── Customers / crédit ───────────────────────────────────────────────────

alter table customers enable row level security;
create policy tenant_isolation on customers for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table credits enable row level security;
create policy tenant_isolation on credits for all to authenticated
  using (exists (select 1 from customers c where c.id = customer_id and user_has_establishment_access(c.establishment_id)))
  with check (exists (select 1 from customers c where c.id = customer_id and user_has_establishment_access(c.establishment_id)));

alter table credit_payments enable row level security;
create policy tenant_isolation on credit_payments for all to authenticated
  using (exists (select 1 from customers c where c.id = customer_id and user_has_establishment_access(c.establishment_id)))
  with check (exists (select 1 from customers c where c.id = customer_id and user_has_establishment_access(c.establishment_id)));

-- ── Sales / POS ──────────────────────────────────────────────────────────

alter table sales enable row level security;
create policy tenant_isolation on sales for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table sale_items enable row level security;
create policy tenant_isolation on sale_items for all to authenticated
  using (exists (select 1 from sales s where s.id = sale_id and user_has_establishment_access(s.establishment_id)))
  with check (exists (select 1 from sales s where s.id = sale_id and user_has_establishment_access(s.establishment_id)));

alter table payments enable row level security;
create policy tenant_isolation on payments for all to authenticated
  using (exists (select 1 from sales s where s.id = sale_id and user_has_establishment_access(s.establishment_id)))
  with check (exists (select 1 from sales s where s.id = sale_id and user_has_establishment_access(s.establishment_id)));

-- ── Dépenses / pertes / caisse / comptabilité ────────────────────────────

alter table expenses enable row level security;
create policy tenant_isolation on expenses for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table losses enable row level security;
create policy tenant_isolation on losses for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table cash_registers enable row level security;
create policy tenant_isolation on cash_registers for all to authenticated
  using (exists (select 1 from points_of_sale pos where pos.id = point_of_sale_id and user_has_establishment_access(pos.establishment_id)))
  with check (exists (select 1 from points_of_sale pos where pos.id = point_of_sale_id and user_has_establishment_access(pos.establishment_id)));

alter table cash_closings enable row level security;
create policy tenant_isolation on cash_closings for all to authenticated
  using (exists (
    select 1 from cash_registers cr
    join points_of_sale pos on pos.id = cr.point_of_sale_id
    where cr.id = cash_register_id and user_has_establishment_access(pos.establishment_id)
  ))
  with check (exists (
    select 1 from cash_registers cr
    join points_of_sale pos on pos.id = cr.point_of_sale_id
    where cr.id = cash_register_id and user_has_establishment_access(pos.establishment_id)
  ));

alter table accounting_entries enable row level security;
create policy tenant_isolation on accounting_entries for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

alter table server_commissions enable row level security;
create policy tenant_isolation on server_commissions for all to authenticated
  using (exists (select 1 from sales s where s.id = sale_id and user_has_establishment_access(s.establishment_id)))
  with check (exists (select 1 from sales s where s.id = sale_id and user_has_establishment_access(s.establishment_id)));

-- ── Système : notifications, abonnement, synchronisation, audit ─────────

alter table notifications enable row level security;
create policy tenant_isolation on notifications for all to authenticated
  using (organization_id = current_user_organization_id())
  with check (organization_id = current_user_organization_id());

alter table subscriptions enable row level security;
create policy tenant_isolation on subscriptions for all to authenticated
  using (organization_id = current_user_organization_id())
  with check (organization_id = current_user_organization_id());

-- sync_operations et audit_logs : écriture/lecture réservées à service_role
-- (NestJS) — pas de policy pour authenticated, donc RLS bloque tout accès
-- direct depuis le client. C'est intentionnel : ce sont des journaux internes.
alter table sync_operations enable row level security;
alter table audit_logs enable row level security;
