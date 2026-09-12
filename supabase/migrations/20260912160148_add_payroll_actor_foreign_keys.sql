-- Ajoute les FK/index manquants sur les colonnes "acteur" de payroll_runs
-- (prepared_by/validated_by/paid_by) — repéré par la revue de code de la
-- Task 1 (refonte Dépenses/Salaires) : ces colonnes avaient été créées en
-- simple uuid, sans la contrainte référentielle vers user_profiles(id) que
-- toutes les autres colonnes "acteur" du schéma ont systématiquement
-- (created_by/closed_by/server_id, voir 20260905191441_core_schema.sql et
-- 20260905191701_add_missing_foreign_key_indexes.sql). Purement additif,
-- table payroll_runs vide à ce stade (module tout juste créé), aucun
-- backfill nécessaire.

alter table payroll_runs
  add constraint payroll_runs_prepared_by_fkey foreign key (prepared_by) references user_profiles(id),
  add constraint payroll_runs_validated_by_fkey foreign key (validated_by) references user_profiles(id),
  add constraint payroll_runs_paid_by_fkey foreign key (paid_by) references user_profiles(id);

create index payroll_runs_prepared_by_idx on payroll_runs(prepared_by);
create index payroll_runs_validated_by_idx on payroll_runs(validated_by);
create index payroll_runs_paid_by_idx on payroll_runs(paid_by);
