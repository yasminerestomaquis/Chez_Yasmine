-- Salaire hebdomadaire OU mensuel par employé, et type de période par paie
-- (demande du 2026-10-06, voir docs/api/expenses.md).
-- Purement additif : les employés et paies existants restent 'weekly'.
-- `employees.weekly_salary` garde son nom (renommage risqué) : c'est le
-- montant du salaire PAR PÉRIODE — par semaine ou par mois selon salary_type.

alter table employees
  add column if not exists salary_type text not null default 'weekly'
    check (salary_type in ('weekly', 'monthly'));

alter table payroll_runs
  add column if not exists period_type text not null default 'weekly'
    check (period_type in ('weekly', 'monthly'));
