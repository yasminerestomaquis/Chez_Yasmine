# Chez Yasmine

Plateforme de gestion de maquis/bar/restaurant — Flutter Web (PWA) + NestJS + Supabase.

Voir [`CLAUDE.md`](./CLAUDE.md) pour les règles et conventions du projet, [`ARCHITECTURE.md`](./ARCHITECTURE.md) pour l'architecture technique, et [`PROJECT_PLAN.md`](./PROJECT_PLAN.md) pour l'état d'avancement.

## Structure

```
apps/
  web/flutter/   Application Flutter Web (PWA)
  api/nestjs/    API NestJS
packages/
  shared/        Logique partagée
  types/         Types partagés front/back
  config/        Configuration partagée
supabase/
  migrations/    Migrations SQL versionnées
  functions/     Edge Functions Supabase
  seed/          Données de seed
docs/            Documentation (architecture, base de données, API, sécurité, PWA, offline, déploiement, décisions)
docker/          Dockerfiles
scripts/         Scripts d'exploitation
```

## Démarrage rapide

### API (NestJS)

```bash
cd apps/api/nestjs
npm install
npm run start:dev
```

### Front-end (Flutter Web)

```bash
cd apps/web/flutter
flutter pub get
flutter run -d chrome
```

Copier `.env.example` en `.env` à la racine et renseigner les valeurs Supabase avant de démarrer l'API.
