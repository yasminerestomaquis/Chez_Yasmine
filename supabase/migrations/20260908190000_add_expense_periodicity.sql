-- Ajoute la périodicité (récurrente / ponctuelle) sur une dépense.
-- Étiquette informative uniquement : n'affecte ni le calcul du bénéfice
-- net (toute dépense compte déjà, quelle que soit sa périodicité) ni
-- aucune génération automatique de dépense.
alter table public.expenses
  add column periodicity text not null default 'one_off';

alter table public.expenses
  add constraint expenses_periodicity_check check (periodicity in ('one_off', 'recurring'));
