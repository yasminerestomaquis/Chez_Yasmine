-- Pinger anti-veille de l'API Render (plan gratuit : mise en veille après
-- ~15 min sans trafic, cold start de 30 à 60 s ensuite).
--
-- Les tâches planifiées de GitHub Actions (.github/workflows/render-keepalive.yml)
-- ne sont pas ponctuelles : médiane de 14,7 min entre deux exécutions pour un
-- cron à 10 min, trous de plusieurs heures. pg_cron, lui, tourne dans la base
-- Supabase à l'heure exacte ; pg_net émet la requête HTTP depuis la base.
-- Les deux mécanismes sont conservés (redondance).
--
-- Une requête toutes les 5 min sur `GET /` (route publique, sans
-- authentification, ne touche pas la base) : bien sous le seuil de 15 min.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- `cron.schedule` avec un nom existant met le job à jour : migration rejouable.
select cron.schedule(
  'render-keepalive',
  '*/5 * * * *',
  $$select net.http_get(
      url := 'https://chez-yasmine-api.onrender.com/',
      timeout_milliseconds := 60000
    )$$
);

-- Hygiène : cron.job_run_details grossit à chaque exécution (288 lignes/jour).
-- (net._http_response est purgée automatiquement par pg_net après quelques heures.)
select cron.schedule(
  'render-keepalive-cleanup',
  '17 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '2 days'$$
);
