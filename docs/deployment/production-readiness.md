# Production — Chez Yasmine (Phase 17)

Cette phase referme les écarts entre ce que le prompt maître attend d'un pipeline de production (§36-38, §49) et l'état réel du dépôt après 16 phases de développement métier — sans fabriquer de déploiement qui n'existe pas.

## Bug réel trouvé et corrigé dans la CI

Le workflow `.github/workflows/ci.yml` (écrit en Phase 2, jamais exécuté faute de push possible vers `origin`) ne définissait pas `DATABASE_URL` pour le job `api`. Or `prisma.config.ts` (Phase 3) exige de pouvoir résoudre cette variable même sans connexion réelle — chaque `npm run build` de ce projet, tout au long des 17 phases, a été lancé avec `DATABASE_URL="postgresql://user:pass@localhost:5432/db"` en préfixe pour cette seule raison. Sans cette variable, le job `api` aurait échoué au tout premier `npm run build` une fois la CI enfin exécutable. Corrigé : la même valeur factice est maintenant définie au niveau du job. Vérifié en local avec exactement la même séquence que la CI (`npm ci` non refait, mais `lint`/`test`/`build` rejoués avec cette variable) : les trois passent.

## Pipeline de production ajouté (inerte)

Le prompt maître (§36) distingue le pipeline de Pull Request (Lint → Tests → Analyse → Build, déjà en place) du pipeline de la branche de production (Tests → Build → Build PWA → Déploiement). Un job `deploy` a été ajouté, déclenché sur une branche `production` dédiée et dépendant (`needs`) des jobs `api`/`web` — donc structurellement conforme — mais avec `if: false` : **aucun hébergeur n'a été choisi**, il n'y a donc ni secrets ni cible à configurer, et un déploiement fabriqué qui ne déploierait nulle part n'aurait été qu'un mensonge vert dans l'interface GitHub. Activer ce job se limite à retirer `if: false` et écrire l'étape propre à l'hébergeur choisi.

## `.env.example` réconcilié avec l'usage réel

Trois des variables listées par le prompt maître (§37) ne sont en réalité lues par aucun code de ce projet — chacune pour une raison déjà actée dans `ARCHITECTURE.md` :

| Variable | Pourquoi elle n'est pas utilisée |
|---|---|
| `JWT_SECRET` | JWT Supabase vérifiés via JWKS (Phase 4), pas un secret partagé |
| `SUPABASE_SERVICE_ROLE_KEY` | Upload/URL signée avec le jeton utilisateur, pas `service_role` (Phase 5) |
| `STORAGE_BUCKET` | Nom de bucket fixé en constante (`PRODUCT_IMAGES_BUCKET`) — le rendre configurable serait trompeur puisque les policies RLS de `storage.objects` (Phase 5) sont écrites pour ce bucket précis |

Plutôt que les supprimer (elles font partie de la liste explicite du prompt maître, les retirer aurait pu passer pour un oubli) ou les laisser sans explication (un futur développeur pourrait croire qu'il faut les renseigner), chacune est annotée dans `.env.example` avec la raison et un renvoi vers la décision d'architecture correspondante.

`API_URL`, en revanche, était listée mais **non branchée** côté Flutter (`ApiConfig.baseUrl` était une constante figée à `http://localhost:3000`, jamais lue depuis l'environnement). Corrigé : `ApiConfig.baseUrl` utilise maintenant `String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000')`, configurable au build/run via `flutter build web --dart-define=API_URL=https://api.exemple.com` sans toucher au code — ce qui satisfait réellement le besoin multi-environnement (development/staging/production, §37) que la variable était censée couvrir.

## Nettoyage : script `deploy` mort

`apps/api/nestjs/package.json` contenait encore `"deploy": "nest deploy"`, un script fourni par `@nestjs/mau` — désinstallé dès la Phase 2 (non utilisé, source de 5 des 9 vulnérabilités `npm audit` initiales). Ce script aurait échoué à l'exécution depuis 15 phases sans que personne ne l'appelle. Supprimé.

## Ce qui reste bloqué (inchangé depuis les phases précédentes)

- **Docker** : toujours pas installé sur cette machine — `docker build`/`docker-compose up` n'ont jamais pu être testés localement. Re-vérifié en Phase 17 (`docker --version` → commande introuvable).
- **Push GitHub** : le compte `gh` authentifié (`Autocad-Qgis`) n'a toujours pas les droits d'écriture sur `yasminerestomaquis/Chez_Yasmine` — rien n'a jamais été poussé, donc la CI elle-même n'a jamais tourné en conditions réelles (GitHub Actions), seulement rejouée localement commande par commande.
- **`DATABASE_URL` réel** : toujours absent. C'est la dépendance commune à presque tous les « non vérifié en conditions réelles » listés depuis la Phase 4 (round-trips HTTP complets, `PermissionsGuard` contre une vraie base, E2E de la Phase 16).
- **Hébergeur de production** : aucun choisi — condition préalable au job `deploy`.

## Vérifications effectuées

- CI rejouée localement, commande par commande, dans le même ordre et avec les mêmes variables que le workflow : `npm ci` (implicite, déjà installé), `npm run lint` (exit 0), `npm run test` (161 tests), `npm run build` (succès) côté API ; `flutter analyze`/`flutter test`/`flutter build web` côté Flutter (30 tests, build réussi).
- Syntaxe YAML du workflow validée (`yaml.safe_load`), jobs et clé `if` du job `deploy` confirmés.
- `grep` sur tout `apps/api/nestjs/src` pour confirmer quelles variables d'environnement sont réellement lues par le code, avant d'annoter `.env.example` — pas une supposition.
