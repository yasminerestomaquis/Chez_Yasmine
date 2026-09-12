-- Étend `expenses` (mode de paiement, statut, lien optionnel vers un
-- paiement de paie) et crée les tables employees/payroll_runs/payroll_lines
-- pour le sous-module Salaires (voir docs/api/expenses.md).
-- Purement additif : aucune colonne existante modifiée/supprimée, valeurs
-- par défaut choisies pour que les dépenses déjà enregistrées restent
-- interprétées exactement comme avant (payment_method='cash', status='paid').

alter table expenses
  add column payment_method text not null default 'cash',
  add column status text not null default 'paid',
  add column payroll_run_id uuid unique;

create table employees (
  id                  uuid primary key default gen_random_uuid(),
  establishment_id    uuid not null references establishments(id) on delete cascade,
  last_name           text not null,
  first_name          text not null,
  gender              text,
  birth_date          date,
  phone               text not null,
  address             text,
  photo_url           text,
  position            text not null,
  hire_date           date not null,
  contract_type       text,
  weekly_salary       numeric(12, 2) not null,
  team                text,
  registration_number text,
  notes               text,
  status              text not null default 'active',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index employees_establishment_id_idx on employees(establishment_id);

create table payroll_runs (
  id               uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  period_start     date not null,
  period_end       date not null,
  status           text not null default 'prepared',
  prepared_by      uuid not null,
  validated_by     uuid,
  paid_by          uuid,
  validated_at     timestamptz,
  paid_at          timestamptz,
  cancelled_at     timestamptz,
  created_at       timestamptz not null default now()
);
create index payroll_runs_establishment_id_idx on payroll_runs(establishment_id);

create table payroll_lines (
  id             uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references payroll_runs(id) on delete cascade,
  employee_id    uuid not null references employees(id) on delete restrict,
  base_salary    numeric(12, 2) not null,
  advance        numeric(12, 2) not null default 0,
  adjustment     numeric(12, 2) not null default 0,
  net_amount     numeric(12, 2) not null,
  unique (payroll_run_id, employee_id)
);
create index payroll_lines_payroll_run_id_idx on payroll_lines(payroll_run_id);
create index payroll_lines_employee_id_idx on payroll_lines(employee_id);

alter table expenses
  add constraint expenses_payroll_run_id_fkey foreign key (payroll_run_id) references payroll_runs(id);

alter table employees enable row level security;
alter table payroll_runs enable row level security;
alter table payroll_lines enable row level security;

-- RLS : même politique établissement que le reste de l'app. La table de
-- jointure utilisateur↔établissement du plan initial (`user_establishment_roles`
-- filtrée par `auth.uid()`) n'est PAS le motif réellement utilisé ailleurs dans
-- le projet (vérifié dans supabase/migrations/20260905191510_rls_policies.sql) :
-- l'isolation existante repose sur la fonction SECURITY DEFINER
-- `user_has_establishment_access(establishment_id)` (organisation de
-- l'utilisateur via `current_user_organization_id()`), précisément pour éviter
-- la récursion RLS qu'une sous-requête directe sur une table protégée par RLS
-- provoquerait. On réutilise donc cette fonction, comme pour `expenses`,
-- `purchases`, `sales`, etc.
create policy tenant_isolation on employees for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

create policy tenant_isolation on payroll_runs for all to authenticated
  using (user_has_establishment_access(establishment_id))
  with check (user_has_establishment_access(establishment_id));

create policy tenant_isolation on payroll_lines for all to authenticated
  using (exists (
    select 1 from payroll_runs pr
    where pr.id = payroll_run_id and user_has_establishment_access(pr.establishment_id)
  ))
  with check (exists (
    select 1 from payroll_runs pr
    where pr.id = payroll_run_id and user_has_establishment_access(pr.establishment_id)
  ));
