# Prompt — Mettre en place un pinger anti-veille pour l'API Render (Chez Yasmine)

> À coller tel quel dans une session Claude Code ouverte à la racine du dépôt
> `D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT`.

---

## Rôle

Tu es l'ingénieur DevOps/back-end du projet **Chez Yasmine** (PWA Flutter Web
+ API NestJS + Supabase pour un maquis/bar en Côte d'Ivoire). Tu travailles en
autonomie : **build, commit et déploiement sont inclus dans la demande**, sans
redemander la permission pour chaque étape.

## Contexte

- API : NestJS sur **Render, plan gratuit**, `https://chez-yasmine-api.onrender.com`
  (région Oregon ; la migration vers Francfort a été **abandonnée**).
- Base : Supabase, projet `tsebsulvhgttdwtgqfoj` (eu-west-1). Front : Vercel
  `https://chez-yasmine-two.vercel.app`.
- Le plan gratuit Render **met le service en veille après ~15 min sans trafic** ;
  la requête suivante subit un *cold start* de 30 à 60 s (l'utilisateur a déjà
  constaté que l'application est alors difficile à afficher).
- Il existe déjà `.github/workflows/render-keepalive.yml` (cron GitHub
  `*/5 * * * *`). **Il n'est pas fiable** : GitHub n'exécute pas les tâches
  planifiées à l'heure (mesuré le 2026-10-04 : médiane 14,7 min pour un cron à
  10 min, 48 intervalles > 15 min sur 99, maximum 5 h 43).

## Objectif

Maintenir l'API éveillée **de façon ponctuelle et fiable**, sans créer de
compte chez un service tiers, sans coût, et sans toucher au code applicatif.

## Contraintes

1. **Aucune création de compte** externe (UptimeRobot, cron-job.org, etc.) :
   utiliser l'infrastructure déjà en place (Supabase).
2. Cibler uniquement la route publique `GET /` de l'API (aucune authentification,
   ne touche pas la base). Ne **jamais** mettre de secret/jeton dans l'URL ni
   dans la requête.
3. Fréquence : **toutes les 5 minutes** (seuil de veille = 15 min).
4. Migration **additive et rejouable** (`create extension if not exists`,
   `cron.schedule` avec un nom fixe met le job à jour). Aucune table métier
   modifiée.
5. Garder `.github/workflows/render-keepalive.yml` comme redondance (ne pas le
   supprimer).
6. Hygiène : prévoir la purge de `cron.job_run_details` (288 lignes/jour sinon).
7. Les fichiers du dépôt sont en CRLF ou LF selon le cas : préserver les fins de
   ligne existantes.

## Étapes

1. **Lire** `.github/workflows/render-keepalive.yml`, `render.yaml` et
   `supabase/migrations/` (nommage `AAAAMMJJHHMMSS_description.sql`).
2. **Vérifier** via le MCP Supabase que `pg_cron` et `pg_net` sont disponibles
   (`pg_available_extensions`) et lesquels sont déjà installés.
3. **Écrire** `supabase/migrations/<horodatage>_add_render_keepalive_cron.sql` :
   - `create extension if not exists pg_cron;`
   - `create extension if not exists pg_net with schema extensions;`
   - `select cron.schedule('render-keepalive', '*/5 * * * *', $$select net.http_get(url := 'https://chez-yasmine-api.onrender.com/', timeout_milliseconds := 60000)$$);`
   - `select cron.schedule('render-keepalive-cleanup', '17 3 * * *', $$delete from cron.job_run_details where end_time < now() - interval '2 days'$$);`
   - un commentaire d'en-tête expliquant le *pourquoi* (veille Render, GitHub
     Actions non ponctuel).
4. **Appliquer** la migration en production avec `apply_migration` (projet
   `tsebsulvhgttdwtgqfoj`, même nom que le fichier sans l'horodatage).
5. **Vérifier** (attendre au moins un créneau de 5 min) :
   - `select jobname, schedule, active from cron.job;` → les deux jobs, `active = true` ;
   - `select status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;` → `succeeded` ;
   - `select status_code, error_msg, created from net._http_response order by created desc limit 5;` → `200`, aucun `error_msg`.
6. **Documenter** : entrée dans `CHANGELOG.md` (section `[Unreleased]`) et
   mise à jour du commentaire de `.github/workflows/render-keepalive.yml`
   (mentionner que `pg_cron` est désormais le pinger principal).
7. **Commit** (`feat(infra): pinger anti-veille Render via pg_cron/pg_net`) et
   **push** sur `origin/main`.

## Critères d'acceptation

- [ ] Les extensions `pg_cron` et `pg_net` sont installées ; le job
  `render-keepalive` est actif, au rythme `*/5 * * * *`.
- [ ] Au moins deux exécutions consécutives espacées de ~5 min, statut
  `succeeded`, réponses HTTP 200 dans `net._http_response`.
- [ ] Mesure de contrôle : après 20 min sans aucun utilisateur, `GET /` répond
  en moins de ~1 s (pas de cold start).
- [ ] Aucun secret dans la migration ; migration rejouable sans erreur.
- [ ] Workflow GitHub conservé ; CHANGELOG et commentaires à jour.

## Pour mémoire (limites à signaler à l'utilisateur)

- Un service gratuit Render éveillé en permanence consomme ~744 h/mois sur les
  750 h gratuites : **ne pas héberger d'autre service gratuit** dans le même
  espace de travail Render.
- Le pinger supprime la veille, **pas la latence** (~3 s par appel
  authentifié : API à Oregon, base en Irlande). Seul un déplacement de région
  ou un plan payant la réduirait.
- Si la base Supabase est mise en pause (inactivité du plan gratuit), `pg_cron`
  s'arrête aussi : le workflow GitHub reste alors le filet de sécurité.
