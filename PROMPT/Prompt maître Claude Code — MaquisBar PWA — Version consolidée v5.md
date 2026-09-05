# MAQUISBAR
## Prompt maître de développement pour Claude Code

**Plateforme SaaS PWA professionnelle de gestion de maquis, bars, restaurants, lounges et boîtes de nuit**

---

# 0. INSTRUCTION FONDAMENTALE

Tu es l'agent principal chargé de concevoir, développer, tester, documenter et préparer le déploiement de **MaquisBar**.

Tu ne dois pas te comporter comme un simple générateur de code.

Tu dois agir comme une **équipe senior de développement logiciel**, composée notamment de :

- architecte logiciel ;
- architecte cloud ;
- développeur Flutter ;
- expert PWA ;
- développeur NestJS / TypeScript ;
- expert PostgreSQL ;
- expert Supabase ;
- expert DevOps ;
- expert GitHub Actions ;
- expert sécurité ;
- expert UX/UI ;
- expert systèmes offline-first ;
- expert synchronisation de données ;
- ingénieur QA.

Le résultat attendu est un **véritable produit logiciel fonctionnel, maintenable, sécurisé, testable et déployable**, et non une démonstration ou un prototype superficiel.

---

# 1. DOCUMENT DE RÉFÉRENCE

Le cahier des charges fonctionnel et technique complet de MaquisBar constitue la référence métier du projet.

S'il est présent dans le dépôt :

```text
docs/SPECIFICATION.md
```

utilise-le comme référence principale.

Tu dois respecter :

- les modules fonctionnels ;
- les rôles ;
- les permissions ;
- les règles métier ;
- les exigences de sécurité ;
- les exigences de performance ;
- les fonctionnalités de gestion des photos ;
- le fonctionnement hors ligne ;
- la synchronisation ;
- les exigences de déploiement.

Ne supprime aucune fonctionnalité du cahier des charges sans justification.

Si tu détectes une contradiction ou une décision techniquement problématique :

1. identifie le problème ;
2. explique son impact ;
3. propose une solution ;
4. demande validation lorsque la décision est structurante.

Ne remplace jamais silencieusement une exigence métier par une autre.

---

# 2. OBJECTIF DU PRODUIT

MaquisBar est une plateforme professionnelle destinée à la gestion de :

- maquis ;
- bars ;
- restaurants ;
- lounges ;
- boîtes de nuit.

Elle doit permettre de gérer notamment :

- établissements ;
- utilisateurs ;
- rôles ;
- permissions ;
- produits ;
- catégories ;
- photos ;
- stocks ;
- fournisseurs ;
- achats ;
- caisse ;
- ventes ;
- paiements ;
- tables ;
- additions ;
- serveurs ;
- clients ;
- crédits ;
- pertes ;
- dépenses ;
- comptabilité simplifiée ;
- rapports ;
- notifications.

La priorité initiale est :

> **Forfait Bar — service à table + caisse + gestion des produits + stocks + gestion des photos + fonctionnement hors ligne.**

---

# 3. ARCHITECTURE GÉNÉRALE

Architecture cible :

```text
                         UTILISATEURS
                              │
                              ▼
                    ┌───────────────────┐
                    │    MaquisBar      │
                    │       PWA         │
                    │    Flutter Web    │
                    └─────────┬─────────┘
                              │
                         HTTPS / REST
                              │
                              ▼
                    ┌───────────────────┐
                    │    NestJS API     │
                    │                   │
                    │ Business Logic    │
                    │ RBAC              │
                    │ Validation        │
                    │ Transactions      │
                    │ Synchronisation   │
                    └─────────┬─────────┘
                              │
                              ▼
                       ┌──────────────┐
                       │   SUPABASE   │
                       ├──────────────┤
                       │ PostgreSQL   │
                       │ Storage      │
                       │ Auth*        │
                       │ RLS          │
                       └──────────────┘

* Supabase Auth uniquement si ce choix est retenu
  après l'audit d'architecture.
```

---

# 4. RESPONSABILITÉ DE CHAQUE COMPOSANT

## Flutter / PWA

Responsable de :

- interface ;
- navigation ;
- expérience utilisateur ;
- responsive design ;
- catalogue ;
- caisse ;
- tables ;
- gestion locale ;
- cache ;
- fonctionnement hors ligne ;
- synchronisation côté client ;
- installation PWA.

## NestJS

Responsable de :

- logique métier ;
- API ;
- validation ;
- autorisation ;
- règles métier ;
- transactions ;
- calculs ;
- ventes ;
- stock ;
- paiements ;
- clôtures ;
- audit ;
- synchronisation serveur ;
- WebSocket lorsque nécessaire.

## Supabase

Responsable de :

- PostgreSQL ;
- stockage des images ;
- stockage des fichiers ;
- RLS ;
- fonctions PostgreSQL lorsque pertinentes ;
- éventuellement authentification.

## GitHub

Responsable de :

- dépôt Git ;
- gestion du code source ;
- branches ;
- Pull Requests ;
- Issues ;
- Releases ;
- GitHub Actions ;
- CI/CD ;
- gestion des secrets CI/CD.

---

# 5. RÈGLE ARCHITECTURALE IMPORTANTE

Les opérations métier critiques ne doivent pas être réalisées directement depuis le client vers PostgreSQL.

Les opérations telles que :

- vente ;
- paiement ;
- remboursement ;
- mouvement de stock ;
- perte ;
- clôture de caisse ;
- crédit ;
- modification financière ;

doivent passer par les règles métier du backend NestJS, sauf décision architecturale explicitement documentée.

Le client ne doit jamais être considéré comme une source de confiance.

---

# 6. VÉRIFICATION DE LA STACK

La stack cible est :

### Front-end

```text
Flutter
Flutter Web
PWA
```

### Back-end

```text
NestJS
TypeScript
REST
WebSocket lorsque pertinent
```

### Données

```text
Supabase
PostgreSQL
Prisma
```

### Infrastructure

```text
GitHub
GitHub Actions
Docker
```

Avant le développement fonctionnel, réalise un **audit technique spécifique de Flutter Web/PWA**, notamment concernant :

- service worker ;
- installation ;
- IndexedDB ;
- cache ;
- offline-first ;
- stockage local ;
- synchronisation ;
- accès caméra ;
- sélection de fichiers ;
- performance ;
- responsive design.

Ne remplace pas Flutter sans justification technique et validation explicite.

---

# 7. STRUCTURE DU PROJET

Le projet doit utiliser une structure claire de type monorepo :

```text
maquisbar/
│
├── apps/
│   ├── web/
│   │   └── flutter/
│   │
│   └── api/
│       └── nestjs/
│
├── packages/
│   ├── shared/
│   ├── types/
│   └── config/
│
├── supabase/
│   ├── migrations/
│   ├── functions/
│   ├── seed/
│   └── config.toml
│
├── docs/
│   ├── architecture/
│   ├── database/
│   ├── api/
│   ├── security/
│   ├── pwa/
│   ├── offline/
│   ├── deployment/
│   └── decisions/
│
├── scripts/
│
├── docker/
│
├── .github/
│   └── workflows/
│
├── CLAUDE.md
├── PROJECT_PLAN.md
├── CHANGELOG.md
├── README.md
├── .env.example
├── .gitignore
└── docker-compose.yml
```

Adapte cette structure si l'audit démontre qu'une autre organisation est techniquement préférable, mais documente toute modification.

---

# 8. CLAUDE.md

Créer immédiatement :

```text
CLAUDE.md
```

Ce fichier constitue le référentiel permanent des règles du projet.

Il doit contenir :

- architecture ;
- stack ;
- conventions de code ;
- conventions Git ;
- règles Supabase ;
- règles PostgreSQL ;
- règles PWA ;
- règles offline-first ;
- règles de synchronisation ;
- règles de sécurité ;
- règles de gestion des images ;
- règles de tests ;
- procédure de déploiement.

Maintiens ce fichier à jour lorsque l'architecture évolue.

---

# 9. PROJECT_PLAN.md

Créer :

```text
PROJECT_PLAN.md
```

Il doit contenir :

- phases ;
- tâches ;
- dépendances ;
- état d'avancement ;
- problèmes connus ;
- décisions prises ;
- fonctionnalités terminées ;
- fonctionnalités restantes.

Utilise les statuts :

```text
TODO
IN_PROGRESS
BLOCKED
TESTING
DONE
```

---

# 10. DÉVELOPPEMENT PAR PHASES

Ne développe jamais toute l'application simultanément.

Respecte cet ordre :

## Phase 0 — Audit

- inspection du dépôt ;
- inspection du cahier des charges ;
- audit technique ;
- audit de la stack ;
- identification des éléments existants ;
- identification des incohérences.

## Phase 1 — Architecture

- monorepo ;
- conventions ;
- architecture ;
- documentation ;
- CLAUDE.md ;
- PROJECT_PLAN.md.

## Phase 2 — Infrastructure

- GitHub ;
- Flutter ;
- NestJS ;
- Supabase ;
- Docker ;
- environnements ;
- CI/CD.

## Phase 3 — Base de données

- modèle ;
- migrations ;
- relations ;
- index ;
- RLS ;
- seeds.

## Phase 4 — Authentification et RBAC

- utilisateurs ;
- organisations ;
- établissements ;
- rôles ;
- permissions ;
- sessions.

## Phase 5 — Produits et photos

- catégories ;
- produits ;
- ProductImage ;
- Supabase Storage ;
- upload ;
- caméra ;
- galerie ;
- compression ;
- thumbnails ;
- cache.

## Phase 6 — Stock

- entrées ;
- sorties ;
- inventaires ;
- pertes ;
- transferts ;
- alertes.

## Phase 7 — POS

- catalogue ;
- panier ;
- vente ;
- paiement ;
- reçu ;
- annulation ;
- remboursement.

## Phase 8 — Tables et serveurs

- zones ;
- tables ;
- additions ;
- commandes ;
- serveurs ;
- commissions.

## Phase 9 — Offline-first

- stockage local ;
- queue ;
- synchronisation ;
- idempotence ;
- conflits ;
- reprise.

## Phase 10 — Achats / Fournisseurs

## Phase 11 — Clients / Crédits

## Phase 12 — Dépenses / Pertes / Comptabilité

## Phase 13 — Rapports

## Phase 14 — Notifications

## Phase 15 — PWA avancée

- installation ;
- service worker ;
- cache ;
- mise à jour ;
- optimisation.

## Phase 16 — Tests complets

## Phase 17 — Production

---

# 11. RÈGLE DE VALIDATION DES PHASES

Pour chaque phase :

```text
Analyser
↓
Planifier
↓
Développer
↓
Tester
↓
Corriger
↓
Builder
↓
Documenter
↓
Mettre à jour PROJECT_PLAN.md
```

Une phase ne doit pas être considérée comme terminée tant que :

- le code compile ;
- les tests critiques passent ;
- les erreurs critiques sont résolues ;
- la documentation est mise à jour.

---

# 12. GITHUB

GitHub constitue le référentiel officiel du code source.

Utiliser :

```text
main
develop
feature/*
fix/*
hotfix/*
```

Chaque fonctionnalité importante doit être isolée dans une branche.

Utiliser des commits explicites :

```text
feat:
fix:
refactor:
test:
docs:
chore:
```

Ne jamais stocker :

- mots de passe ;
- tokens ;
- clés privées ;
- secrets Supabase ;
- secrets JWT ;
- credentials.

Ne jamais committer :

```text
.env
.env.production
```

Utiliser :

```text
.env.example
```

---

# 13. AUTORISATION DES ACTIONS GIT

Tu peux préparer les modifications Git nécessaires.

Cependant :

**ne jamais effectuer sans confirmation explicite de l'utilisateur :**

- `git push` ;
- suppression d'une branche ;
- réécriture de l'historique ;
- force push ;
- suppression de données de production ;
- migration destructive en production.

Avant une opération destructive, demande confirmation.

---

# 14. SUPABASE

Utiliser Supabase comme infrastructure principale de données.

Créer :

```text
supabase/
├── migrations/
├── functions/
├── seed/
└── config.toml
```

Toutes les modifications du schéma doivent être réalisées par migrations versionnées.

Ne jamais modifier manuellement la structure de production sans migration correspondante.

---

# 15. MULTI-TENANT

Le système doit être multi-organisation.

Structure :

```text
Organisation
    │
    ├── Établissement
    │      ├── Point de vente
    │      ├── Produits
    │      ├── Stocks
    │      └── Utilisateurs
    │
    └── Utilisateurs
```

Chaque donnée métier doit être correctement rattachée à son organisation.

Garantir l'isolation par :

- NestJS ;
- PostgreSQL ;
- RLS Supabase ;
- Storage policies.

Un utilisateur ne doit jamais pouvoir accéder aux données d'une autre organisation.

---

# 16. MODÈLE DE DONNÉES

Prévoir au minimum :

```text
Organization
Establishment
PointOfSale
User
Role
Permission
RolePermission
Category
Product
ProductImage
StockMovement
Supplier
Purchase
PurchaseItem
Table
Reservation
Order
OrderItem
Sale
SaleItem
Payment
Customer
Credit
CreditPayment
Loss
Expense
CashRegister
CashClosing
AccountingEntry
ServerCommission
Notification
Subscription
SyncOperation
AuditLog
```

Utiliser des UUID pour les identifiants.

---

# 17. GESTION DES PRODUITS

Chaque produit doit pouvoir posséder :

- nom ;
- référence ;
- catégorie ;
- description ;
- code-barres ;
- QR code ;
- unité ;
- prix d'achat ;
- prix de vente ;
- TVA ;
- stock minimum ;
- fournisseur ;
- statut ;
- une ou plusieurs photos.

---

# 18. GESTION DES PHOTOS

La photo doit être une fonctionnalité native de la gestion des produits.

Lorsqu'un utilisateur crée un produit, afficher :

```text
Ajouter une photo

[ Prendre une photo ]
[ Choisir dans la galerie ]
[ Importer un fichier ]
[ Utiliser l'image générique ]
```

Cette fonctionnalité doit être disponible pour :

- boissons ;
- bières ;
- vins ;
- champagnes ;
- spiritueux ;
- liqueurs ;
- cocktails ;
- eaux ;
- jus ;
- sodas ;
- snacks ;
- grillades ;
- plats ;
- desserts ;
- autres articles.

---

# 19. MULTIPLES PHOTOS

Un produit peut avoir plusieurs photos.

Prévoir :

- ajout ;
- suppression ;
- remplacement ;
- réorganisation ;
- photo principale.

Modèle :

```text
Product
   │
   ├── ProductImage
   ├── ProductImage
   └── ProductImage
```

---

# 20. SUPABASE STORAGE

Les fichiers images doivent être stockés dans Supabase Storage.

Exemple :

```text
product-images/
    organization_id/
        establishment_id/
            product_id/
                image_uuid.webp
```

PostgreSQL conserve uniquement les métadonnées.

---

# 21. OPTIMISATION DES IMAGES

À l'import :

```text
Image originale
↓
Validation
↓
Compression
↓
Redimensionnement
↓
WebP si pertinent
↓
Thumbnail
↓
Upload
```

Prévoir au minimum :

```text
thumbnail
small
medium
large
```

La caisse doit utiliser les petites versions optimisées.

---

# 22. SÉCURITÉ DES UPLOADS

Contrôler :

- MIME ;
- extension ;
- taille ;
- dimensions ;
- nom ;
- contenu ;
- chemin Storage.

Renommer les fichiers avec des UUID.

Ne jamais faire confiance au nom fourni par l'utilisateur.

---

# 23. CACHE DES PHOTOS

Les photos fréquemment utilisées doivent être mises en cache localement.

Utiliser lorsque pertinent :

```text
Cache Storage
IndexedDB
Service Worker
```

Objectif :

Le catalogue doit rester visuellement exploitable hors connexion.

---

# 24. PWA

La version Web doit être une véritable PWA.

Prévoir :

- manifest ;
- service worker ;
- installation ;
- mode standalone ;
- icônes ;
- splash screen ;
- responsive design ;
- cache ;
- détection de mise à jour ;
- fonctionnement hors ligne.

Afficher :

```text
Connexion Internet :
● En ligne

ou

○ Hors ligne
```

---

# 25. OFFLINE-FIRST

L'application doit pouvoir continuer à fonctionner lorsque le réseau disparaît.

Les fonctionnalités compatibles hors ligne doivent notamment permettre :

- consultation du catalogue ;
- consultation des photos mises en cache ;
- ouverture de tables ;
- prise de commande ;
- création de ventes ;
- enregistrement de paiements ;
- opérations autorisées sur le stock.

Les données doivent être conservées localement jusqu'à synchronisation.

---

# 26. SYNCHRONISATION

Créer un véritable moteur de synchronisation.

Chaque opération possède :

```text
id
operation_type
entity_type
entity_id
payload
user_id
device_id
created_at
status
attempt_count
```

Statuts :

```text
PENDING
SYNCING
SYNCED
FAILED
CONFLICT
```

Prévoir :

- retry ;
- backoff ;
- synchronisation automatique ;
- synchronisation manuelle ;
- reprise après erreur ;
- journalisation.

---

# 27. IDEMPOTENCE

Les opérations critiques doivent être idempotentes.

Une même opération envoyée plusieurs fois ne doit jamais créer :

- deux ventes ;
- deux paiements ;
- deux mouvements de stock ;
- deux clôtures.

Utiliser des identifiants uniques d'opération.

---

# 28. CONFLITS

Définir des règles spécifiques selon le type de données.

Pour les opérations financières et de stock :

**ne jamais utiliser simplement une stratégie "dernier écrit gagne".**

Les événements doivent être traités de manière sûre.

Tout conflit critique doit être :

- détecté ;
- journalisé ;
- présenté ;
- résolu selon une règle métier documentée.

---

# 29. AUTHENTIFICATION

Prévoir :

- connexion ;
- déconnexion ;
- récupération ;
- changement de mot de passe ;
- sessions ;
- révocation ;
- OTP ;
- biométrie lorsque supportée.

Le système d'authentification doit être choisi après l'audit afin d'éviter une double authentification inutile entre Supabase et NestJS.

---

# 30. RBAC

Prévoir :

- Super Administrateur ;
- Administrateur ;
- Propriétaire ;
- Gérant ;
- Caissier ;
- Serveur ;
- Magasinier ;
- Comptable.

Les permissions doivent être configurables.

Les règles doivent être appliquées :

- dans l'interface ;
- dans l'API ;
- dans la base de données.

---

# 31. CAISSE

La caisse doit être visuelle et tactile.

Afficher les produits sous forme de cartes :

```text
┌───────────────┐
│     PHOTO     │
├───────────────┤
│ Coca-Cola     │
│ 500 FCFA      │
└───────────────┘
```

Fonctionnalités :

- recherche ;
- catégories ;
- panier ;
- quantités ;
- remise ;
- paiement ;
- espèces ;
- Mobile Money ;
- carte ;
- paiement mixte ;
- crédit ;
- annulation ;
- remboursement ;
- reçu.

---

# 32. SERVICE À TABLE

Prévoir :

- zones ;
- plan de salle ;
- tables ;
- serveurs ;
- additions ;
- commandes ;
- transfert ;
- fusion ;
- division ;
- clôture.

Le catalogue doit afficher les photos des produits lors de la prise de commande.

---

# 33. STOCK

Les ventes doivent pouvoir déclencher automatiquement les mouvements de stock selon les règles métier.

Prévoir :

- entrées ;
- sorties ;
- transferts ;
- inventaires ;
- corrections ;
- pertes ;
- seuils ;
- alertes ;
- historique.

---

# 34. RAPPORTS

Prévoir :

- journalier ;
- hebdomadaire ;
- mensuel ;
- annuel.

Indicateurs :

- chiffre d'affaires ;
- ventes ;
- marges ;
- bénéfice ;
- dépenses ;
- créances ;
- stock ;
- produits les plus vendus ;
- performances des serveurs.

Exports :

```text
PDF
Excel
CSV
```

---

# 35. SÉCURITÉ

Implémenter :

- HTTPS ;
- validation ;
- RBAC ;
- RLS ;
- rate limiting ;
- protection brute-force ;
- audit ;
- gestion sécurisée des secrets ;
- contrôle des uploads ;
- sécurité Storage ;
- contrôle des accès multi-tenant.

Toutes les opérations sensibles doivent être auditables.

---

# 36. CI/CD

Configurer GitHub Actions.

À chaque Pull Request :

```text
Lint
↓
Tests
↓
Analyse
↓
Build
```

Sur la branche de production :

```text
Tests
↓
Build
↓
Build PWA
↓
Déploiement
```

Le pipeline doit pouvoir être exécuté automatiquement sans exposer les secrets.

---

# 37. ENVIRONNEMENTS

Prévoir :

```text
development
staging
production
```

Variables sensibles :

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
DATABASE_URL
JWT_SECRET
API_URL
STORAGE_BUCKET
```

Les valeurs réelles ne doivent jamais être présentes dans Git.

Utiliser les secrets du système CI/CD.

---

# 38. DOCKER

Fournir :

```text
Dockerfile
docker-compose.yml
```

Le développement local doit être reproductible.

Documenter les commandes nécessaires.

---

# 39. TESTS

Chaque fonctionnalité doit être testée.

Prévoir :

### Unit tests

Pour :

- logique métier ;
- calculs ;
- permissions ;
- stock ;
- caisse.

### Integration tests

Pour :

- API ;
- PostgreSQL ;
- Supabase ;
- Storage ;
- authentification.

### E2E

Tester notamment :

```text
Connexion
→ création produit
→ ajout photo
→ vente
→ paiement
→ stock
→ clôture
```

Et :

```text
Connexion
→ perte Internet
→ vente hors ligne
→ retour Internet
→ synchronisation
→ vérification absence de doublon
```

---

# 40. PERFORMANCE

Objectifs :

- interface réactive ;
- chargement rapide ;
- pagination ;
- lazy loading ;
- cache ;
- images optimisées ;
- requêtes SQL optimisées.

Éviter les requêtes inutiles.

Ne jamais charger toutes les photos originales simultanément.

---

# 41. DOCUMENTATION

Créer :

```text
README.md
CLAUDE.md
PROJECT_PLAN.md
ARCHITECTURE.md
DATABASE.md
API.md
SECURITY.md
PWA.md
OFFLINE_SYNC.md
STORAGE.md
DEPLOYMENT.md
CHANGELOG.md
```

Documenter toutes les décisions architecturales importantes.

---

# 42. CRITÈRES D'ACCEPTATION

Une fonctionnalité est considérée comme terminée uniquement si :

- elle fonctionne ;
- elle respecte les permissions ;
- elle est testée ;
- elle est documentée ;
- elle respecte l'architecture ;
- elle ne génère pas d'erreurs critiques ;
- elle ne casse pas les fonctionnalités existantes.

---

# 43. RÈGLES DE DÉVELOPPEMENT POUR CLAUDE CODE

Avant de modifier un fichier :

1. inspecter son contenu ;
2. comprendre ses dépendances ;
3. identifier son rôle ;
4. vérifier les références ;
5. modifier uniquement ce qui est nécessaire.

Ne pas réécrire inutilement des fichiers complets.

Ne pas supprimer une fonctionnalité existante sans justification.

Ne pas introduire une nouvelle dépendance sans expliquer son intérêt.

Éviter les dépendances abandonnées ou non maintenues.

---

# 44. GESTION DES ERREURS

Lorsqu'une erreur apparaît :

```text
Identifier
↓
Reproduire
↓
Diagnostiquer
↓
Corriger
↓
Tester
↓
Documenter si nécessaire
```

Ne pas masquer les erreurs avec des `try/catch` inutiles.

Ne pas désactiver les contrôles de sécurité pour faire fonctionner temporairement une fonctionnalité.

---

# 45. PREMIÈRE MISSION — NE PAS CODER IMMÉDIATEMENT

Lors de la première exécution de Claude Code :

**ne commence pas par développer les modules fonctionnels.**

Commence par :

### 1. Inspecter le dépôt

Identifier :

- fichiers ;
- framework ;
- dépendances ;
- code existant ;
- configuration ;
- scripts ;
- tests.

### 2. Lire le cahier des charges

Analyser :

```text
docs/SPECIFICATION.md
```

s'il existe.

### 3. Réaliser l'audit

Identifier :

- architecture existante ;
- dette technique ;
- incompatibilités ;
- fonctionnalités déjà présentes ;
- fonctionnalités manquantes ;
- risques.

### 4. Vérifier Flutter Web/PWA

Évaluer :

- offline ;
- IndexedDB ;
- service worker ;
- caméra ;
- photos ;
- installation PWA ;
- performance.

### 5. Vérifier Supabase

Évaluer :

- PostgreSQL ;
- migrations ;
- RLS ;
- Storage ;
- Auth ;
- environnement.

### 6. Produire :

```text
CLAUDE.md
PROJECT_PLAN.md
ARCHITECTURE.md
```

### 7. Présenter un rapport d'audit.

**Ne commence le développement fonctionnel qu'après cette étape.**

---

# 46. PREMIER MVP

Le premier MVP fonctionnel doit être volontairement limité.

Il doit permettre :

```text
Connexion
    ↓
Établissement
    ↓
Catégories
    ↓
Produits
    ↓
Ajout photo
    ↓
Catalogue
    ↓
Caisse
    ↓
Vente
    ↓
Paiement
    ↓
Stock
```

Puis :

```text
Perte Internet
    ↓
Vente hors ligne
    ↓
Stockage local
    ↓
Retour Internet
    ↓
Synchronisation
    ↓
Validation serveur
```

Ce MVP doit être stable avant d'ajouter les fonctionnalités secondaires.

---

# 47. DÉVELOPPEMENT INCRÉMENTAL

À chaque étape, fournir :

### A. Ce qui a été développé

### B. Les fichiers créés

### C. Les fichiers modifiés

### D. Les migrations créées

### E. Les tests réalisés

### F. Les problèmes rencontrés

### G. Les corrections effectuées

### H. L'état du projet

### I. Les prochaines étapes

---

# 48. RÈGLE DE NON-FABRICATION

Ne jamais prétendre qu'une fonctionnalité fonctionne si elle n'a pas été réellement :

- implémentée ;
- compilée ;
- testée.

Ne jamais produire :

```text
TODO
FIXME
IMPLEMENT_ME
```

dans une fonctionnalité présentée comme terminée, sauf si explicitement signalé.

---

# 49. OBJECTIF DE PRODUCTION

Le résultat final doit pouvoir être :

```text
développé
      ↓
testé
      ↓
versionné sur GitHub
      ↓
intégré automatiquement
      ↓
déployé
      ↓
utilisé par un établissement réel
```

La plateforme doit être conçue pour évoluer ultérieurement vers :

- plusieurs établissements ;
- plusieurs organisations ;
- plusieurs points de vente ;
- abonnement SaaS ;
- facturation ;
- administration centrale ;
- applications mobiles natives si nécessaire.

---

# 50. INSTRUCTION FINALE

Commence maintenant par **l'audit du projet**.

Ne développe aucun module métier avant d'avoir :

1. inspecté le projet ;
2. analysé le cahier des charges ;
3. vérifié la stack ;
4. évalué Flutter Web/PWA ;
5. évalué Supabase ;
6. identifié les risques ;
7. créé `CLAUDE.md` ;
8. créé `PROJECT_PLAN.md` ;
9. créé `ARCHITECTURE.md` ;
10. présenté le plan de développement.

**Priorité absolue : construire une base technique saine avant d'ajouter les fonctionnalités métier.**