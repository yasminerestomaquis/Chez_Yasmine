# PROMPT DE DÉVELOPPEMENT

## Plateforme SaaS PWA de gestion de maquis, bars, restaurants et boîtes de nuit

**Édition de référence : plateforme Web Progressive Web App (PWA) — gestion de bar, maquis, restaurant et boîte de nuit, service à table, gestion multi-serveurs, fonctionnement hors ligne, photos des articles, GitHub + Supabase**

---

# 1. RÔLE À ENDOSSER

Agis comme une équipe complète composée de :

- architecte logiciel senior ;
- architecte cloud ;
- chef de projet ;
- expert UX/UI ;
- développeur full-stack senior ;
- expert Flutter Web et PWA ;
- expert NestJS / TypeScript ;
- expert PostgreSQL / Supabase ;
- expert DevOps / GitHub Actions ;
- expert sécurité ;
- expert systèmes offline-first et synchronisation ;
- expert stockage d'images et optimisation Web.

Tu dois concevoir et développer une application professionnelle, moderne, sécurisée, évolutive et commercialisable.

---

# 2. MISSION GÉNÉRALE

Concevoir et développer **MaquisBar**, une plateforme SaaS destinée à la gestion complète des :

- maquis ;
- bars ;
- restaurants ;
- lounges ;
- boîtes de nuit.

L'application doit permettre au propriétaire ou au personnel de gérer l'établissement depuis :

- smartphone ;
- tablette ;
- ordinateur ;
- navigateur Web ;
- Windows ;
- Android ;
- iOS.

La priorité est donnée à une **version PWA complète**, installable depuis un navigateur comme une véritable application.

L'application doit fonctionner :

- en ligne ;
- hors ligne ;
- avec synchronisation automatique dès le retour de la connexion.

La plateforme doit être conçue selon une approche **offline-first**, particulièrement adaptée aux établissements pouvant connaître des interruptions de connexion Internet.

---

# 3. OBJECTIF PRINCIPAL : APPLICATION PWA

La version principale du logiciel doit être une **Progressive Web App (PWA)**.

Elle doit :

- être accessible depuis une URL ;
- être installable sur smartphone, tablette et ordinateur ;
- fonctionner en plein écran ;
- disposer d'un service worker ;
- disposer d'un manifeste Web App ;
- permettre la mise en cache des ressources ;
- fonctionner hors connexion ;
- stocker temporairement les opérations locales ;
- synchroniser automatiquement les données ;
- permettre l'accès rapide au catalogue ;
- mettre en cache les photos des produits ;
- gérer les mises à jour de l'application ;
- afficher un indicateur de connexion Internet ;
- afficher l'état de synchronisation ;
- permettre la reprise des opérations après une perte de connexion.

La PWA doit respecter les bonnes pratiques modernes en matière de :

- responsive design ;
- accessibilité ;
- performance ;
- sécurité ;
- cache ;
- service worker ;
- IndexedDB ;
- synchronisation ;
- installation mobile.

---

# 4. ARCHITECTURE TECHNIQUE CIBLE

Adopte l'architecture suivante :

```text
                    UTILISATEURS
                         │
                         ▼
              ┌─────────────────────┐
              │      PWA WEB        │
              │ Flutter Web         │
              │ Responsive UI       │
              │ Offline-first       │
              └──────────┬──────────┘
                         │
                    HTTPS / REST
                         │
                         ▼
              ┌─────────────────────┐
              │       API           │
              │ NestJS / TypeScript │
              │ Auth / Business     │
              │ WebSocket           │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │      SUPABASE       │
              │ PostgreSQL          │
              │ Storage             │
              │ Auth (optionnel)    │
              │ Row Level Security  │
              └─────────────────────┘
```

### GitHub

GitHub constitue le référentiel central du projet.

Il doit contenir :

- le code source complet ;
- le front-end ;
- le back-end ;
- les migrations ;
- les scripts ;
- les tests ;
- les fichiers de configuration ;
- la documentation ;
- les workflows CI/CD ;
- les fichiers Docker ;
- les scripts de déploiement.

Le projet doit être organisé comme un **monorepo professionnel**.

Exemple :

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
├── database/
│   ├── migrations/
│   ├── seeds/
│   └── sql/
│
├── docs/
│
├── scripts/
│
├── docker/
│
├── .github/
│   └── workflows/
│
├── docker-compose.yml
├── README.md
├── LICENSE
└── .gitignore
```

---

# 5. GITHUB : GESTION DU CODE SOURCE

Le développement doit être entièrement compatible avec GitHub.

Configure :

- Git ;
- GitHub ;
- branches `main`, `develop` et `feature/*` ;
- Pull Requests ;
- Issues ;
- Releases ;
- Tags de version ;
- GitHub Actions ;
- protection de la branche principale.

Chaque fonctionnalité importante doit être développée dans une branche dédiée.

Exemple :

```text
main
develop
feature/authentication
feature/products
feature/product-images
feature/inventory
feature/pos
feature/tables
feature/offline-sync
feature/reports
```

Ne jamais stocker dans GitHub :

- mots de passe ;
- clés API ;
- JWT secrets ;
- clés Supabase privées ;
- credentials ;
- tokens ;
- secrets de production.

Utiliser :

```text
.env
.env.local
.env.production
```

avec un fichier :

```text
.env.example
```

contenant uniquement les noms des variables nécessaires.

---

# 6. HÉBERGEMENT DU FRONT-END

La PWA doit être compilable et déployable automatiquement depuis GitHub.

Configurer :

**GitHub → GitHub Actions → Build Flutter Web → Déploiement PWA**

Le workflow doit :

1. récupérer le code ;
2. installer Flutter ;
3. installer les dépendances ;
4. lancer les tests ;
5. construire la PWA ;
6. générer les fichiers Web ;
7. déployer automatiquement la PWA.

Le déploiement Web doit être compatible avec **GitHub Pages** ou une autre solution de déploiement Web connectée au dépôt GitHub.

Prévoir notamment :

```text
web/
├── index.html
├── manifest.json
├── icons/
├── favicon.png
└── flutter_service_worker.js
```

Configurer correctement :

- `manifest.json` ;
- service worker ;
- cache ;
- icônes ;
- splash screen ;
- mode standalone ;
- thème ;
- orientation ;
- base URL ;
- routes Flutter ;
- gestion des erreurs 404 ;
- HTTPS.

---

# 7. SUPABASE

Utiliser **Supabase comme infrastructure principale de données**.

Supabase doit notamment fournir :

- PostgreSQL ;
- stockage des photos ;
- stockage des fichiers ;
- éventuellement l'authentification ;
- Row Level Security ;
- fonctions PostgreSQL si nécessaire ;
- sauvegardes ;
- gestion des environnements.

La base de données doit être hébergée dans Supabase.

Ne pas maintenir une base PostgreSQL indépendante si Supabase répond au besoin.

---

# 8. ARCHITECTURE SUPABASE

Créer au minimum :

```text
Supabase
│
├── PostgreSQL
│
├── Storage
│   ├── products/
│   ├── establishments/
│   ├── receipts/
│   ├── documents/
│   └── exports/
│
├── Authentication
│
├── Row Level Security
│
└── Database Functions
```

Créer des environnements distincts :

```text
development
staging
production
```

Les migrations doivent être versionnées dans GitHub.

---

# 9. GESTION DES PHOTOS ET IMAGES

La gestion des photos constitue une fonctionnalité majeure de l'application.

L'utilisateur doit pouvoir ajouter une photo à **n'importe quel article**.

Cela concerne notamment :

- boissons ;
- bières ;
- vins ;
- champagnes ;
- liqueurs ;
- spiritueux ;
- cocktails ;
- eaux ;
- jus ;
- sodas ;
- snacks ;
- grillades ;
- plats ;
- desserts ;
- produits divers ;
- articles non alimentaires ;
- tout autre produit créé ultérieurement.

Lors de la création ou de la modification d'un produit, proposer :

### Option 1 — Appareil photo

L'utilisateur peut :

**Prendre une photo**

La caméra du smartphone ou de la tablette est alors utilisée.

### Option 2 — Galerie

L'utilisateur peut :

**Choisir une photo**

depuis la galerie ou le système de fichiers.

### Option 3 — Import Web

Depuis un ordinateur :

- sélectionner une image ;
- glisser-déposer une image ;
- remplacer l'image existante.

---

# 10. MULTIPLES PHOTOS PAR ARTICLE

Un produit peut posséder plusieurs photos.

Exemple :

```text
Produit :
Coca-Cola 50 cl

Photos :
- vue principale
- vue arrière
- étiquette
- conditionnement
```

Prévoir :

- ajout ;
- modification ;
- suppression ;
- remplacement ;
- réorganisation ;
- définition de la photo principale.

La photo principale doit être utilisée dans :

- le catalogue ;
- la caisse ;
- les commandes à table ;
- les recherches ;
- les rapports lorsque pertinent.

---

# 11. STOCKAGE DES PHOTOS DANS SUPABASE

Les fichiers images doivent être stockés dans :

```text
Supabase Storage
```

Créer par exemple :

```text
product-images
```

Organisation logique :

```text
product-images/
    organisation_id/
        establishment_id/
            product_id/
                image-001.webp
                image-002.webp
```

La base PostgreSQL ne doit pas stocker directement les fichiers binaires.

Elle doit stocker :

- ID de l'image ;
- produit ;
- URL ou chemin Storage ;
- nom du fichier ;
- type MIME ;
- taille ;
- largeur ;
- hauteur ;
- ordre d'affichage ;
- indicateur `is_primary` ;
- date de création ;
- utilisateur ayant ajouté l'image.

---

# 12. OPTIMISATION AUTOMATIQUE DES IMAGES

Lorsqu'une photo est ajoutée :

1. vérifier le type de fichier ;
2. vérifier la taille ;
3. contrôler les dimensions ;
4. compresser l'image ;
5. générer une version WebP lorsque pertinent ;
6. générer une miniature ;
7. conserver une version optimisée ;
8. supprimer ou remplacer proprement l'ancienne version ;
9. enregistrer les métadonnées.

Prévoir plusieurs tailles :

```text
thumbnail
small
medium
large
```

Exemple :

```text
thumbnail : 150 × 150
small      : 300 × 300
medium     : 600 × 600
large      : 1200 × 1200
```

Ne jamais charger inutilement une image haute résolution dans la caisse.

---

# 13. CACHE LOCAL DES PHOTOS

Les photos utilisées fréquemment doivent être mises en cache localement.

Objectif :

Même sans Internet, l'utilisateur doit pouvoir voir :

- les photos des boissons ;
- les photos des produits ;
- le catalogue ;
- les catégories.

Le système doit utiliser un cache local adapté au Web/PWA.

Prévoir :

```text
IndexedDB
+
Cache Storage
+
Service Worker
```

---

# 14. MODE HORS LIGNE

L'application doit être conçue selon une architecture **offline-first**.

Lorsque la connexion Internet est interrompue :

L'utilisateur doit pouvoir continuer à :

- consulter les produits ;
- consulter les photos ;
- ouvrir une table ;
- ajouter des produits ;
- créer une addition ;
- enregistrer une vente ;
- enregistrer un paiement ;
- enregistrer certaines opérations de stock ;
- enregistrer les opérations autorisées par son rôle.

Les opérations sont enregistrées localement.

Exemple :

```text
Utilisateur
     │
     ▼
PWA
     │
     ▼
Base locale / IndexedDB
     │
     ▼
File de synchronisation
     │
     │ Internet disponible
     ▼
API
     │
     ▼
Supabase PostgreSQL
```

---

# 15. SYNCHRONISATION

Créer un véritable moteur de synchronisation.

Chaque opération locale doit posséder :

- UUID ;
- type d'opération ;
- date ;
- utilisateur ;
- appareil ;
- version ;
- statut ;
- données ;
- nombre de tentatives.

Exemple :

```text
PENDING
SYNCING
SYNCED
FAILED
CONFLICT
```

Prévoir :

- synchronisation automatique ;
- synchronisation manuelle ;
- reprise après erreur ;
- détection des doublons ;
- gestion des conflits ;
- journal de synchronisation.

---

# 16. GESTION DES CONFLITS

Prévoir des règles explicites.

Exemples :

### Stock

Les mouvements de stock doivent être traités comme des événements et non comme de simples écrasements de valeurs.

### Vente

Une vente validée ne doit jamais être écrasée par une autre opération.

### Produit

Pour une modification du produit :

```text
version locale
vs
version serveur
```

Le système doit déterminer :

- quelle version est la plus récente ;
- si une fusion est possible ;
- si une intervention utilisateur est nécessaire.

---

# 17. AUTHENTIFICATION

Prévoir :

- connexion ;
- déconnexion ;
- récupération de compte ;
- changement de mot de passe ;
- gestion des sessions ;
- refresh token ;
- OTP SMS ;
- authentification biométrique lorsque supportée ;
- révocation des sessions.

L'authentification doit être compatible avec Supabase Auth ou avec une architecture NestJS sécurisée.

Choisir une seule architecture d'authentification cohérente afin d'éviter les doubles systèmes inutiles.

---

# 18. AUTORISATION

Implémenter un RBAC complet :

- Super Administrateur ;
- Administrateur ;
- Propriétaire ;
- Gérant ;
- Caissier ;
- Serveur ;
- Magasinier ;
- Comptable.

Les permissions doivent être configurables.

Utiliser également les mécanismes de sécurité PostgreSQL/Supabase, notamment **Row Level Security**, pour empêcher un utilisateur d'accéder aux données d'une autre organisation ou d'un autre établissement.

---

# 19. MODULES FONCTIONNELS

Développer les 20 modules suivants.

## 19.1 Authentification et comptes

- connexion ;
- comptes utilisateurs ;
- rôles ;
- permissions ;
- sessions ;
- OTP ;
- récupération de compte ;
- sécurité.

## 19.2 Établissements

- organisations ;
- établissements ;
- points de vente ;
- logo ;
- coordonnées ;
- horaires ;
- paramètres fiscaux ;
- devise.

## 19.3 Catégories

Créer et gérer :

- boissons ;
- bières ;
- vins ;
- spiritueux ;
- cocktails ;
- eaux ;
- jus ;
- sodas ;
- snacks ;
- grillades ;
- plats ;
- desserts ;
- autres.

## 19.4 Produits

Chaque produit doit comporter :

- référence ;
- nom ;
- description ;
- catégorie ;
- fournisseur ;
- code-barres ;
- QR code ;
- prix d'achat ;
- prix de vente ;
- TVA ;
- unité ;
- stock minimum ;
- statut ;
- photos.

### Fonction essentielle

L'utilisateur doit pouvoir ajouter une photo directement lors de la création du produit.

Interface :

```text
+--------------------------+
|       PHOTO PRODUIT      |
|                          |
|   [ Prendre une photo ]  |
|                          |
|   [ Galerie / Import ]   |
|                          |
+--------------------------+
```

## 19.5 Stocks

- entrées ;
- sorties ;
- transferts ;
- inventaires ;
- corrections ;
- pertes ;
- seuils ;
- alertes ;
- historique.

## 19.6 Fournisseurs

- fiches ;
- commandes ;
- livraisons ;
- factures ;
- paiements ;
- dettes.

## 19.7 Achats

- bons de commande ;
- réceptions ;
- factures ;
- paiements ;
- validation.

## 19.8 Caisse / POS

Créer une caisse tactile avec :

- photos ;
- catégories ;
- recherche ;
- filtres ;
- panier ;
- paiement ;
- remise ;
- annulation ;
- remboursement ;
- reçu.

Les articles doivent être présentés sous forme de cartes :

```text
┌───────────────┐
│    PHOTO      │
│               │
├───────────────┤
│ Coca-Cola     │
│ 500 FCFA      │
└───────────────┘
```

## 19.9 Tables

- plan de salle ;
- zones ;
- tables ;
- réservation ;
- ouverture ;
- transfert ;
- fusion ;
- division d'addition ;
- clôture.

## 19.10 Serveurs

- attribution ;
- tables ;
- ventes ;
- commissions ;
- statistiques.

## 19.11 Clôture de caisse

- montant théorique ;
- montant compté ;
- écart ;
- justification ;
- historique.

## 19.12 Clients

- identité ;
- téléphone ;
- historique ;
- fidélité ;
- crédit.

## 19.13 Crédits

- plafond ;
- ventes ;
- remboursements ;
- échéances ;
- encours.

## 19.14 Dépenses

- loyer ;
- salaires ;
- eau ;
- électricité ;
- carburant ;
- entretien ;
- autres.

## 19.15 Pertes

- casse ;
- péremption ;
- vol ;
- offert ;
- consommation interne.

## 19.16 Comptabilité

- caisse ;
- banques ;
- journal ;
- bilan simplifié.

## 19.17 Rapports

- journalier ;
- hebdomadaire ;
- mensuel ;
- annuel ;
- ventes ;
- marges ;
- bénéfices ;
- dépenses ;
- stocks ;
- créances ;
- rentabilité.

Exports :

```text
PDF
Excel
CSV
```

## 19.18 Notifications

- stock faible ;
- rupture ;
- clôture ;
- crédit ;
- achat ;
- synchronisation ;
- sauvegarde ;
- notification push.

## 19.19 Paramétrage

- TVA ;
- devise ;
- langue ;
- utilisateurs ;
- permissions ;
- imprimantes ;
- reçus ;
- horaires.

## 19.20 Offline / Synchronisation

Mettre en œuvre l'intégralité du système :

- cache ;
- stockage local ;
- queue ;
- synchronisation ;
- conflits ;
- reprise ;
- monitoring.

---

# 20. MODÈLE DE DONNÉES

Concevoir un modèle PostgreSQL/Supabase complet.

Entités minimales :

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
Customer
Table
Reservation
Order
OrderItem
Sale
SaleItem
Payment
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

Toutes les tables doivent posséder des UUID.

Les données sensibles doivent être correctement protégées.

---

# 21. MULTI-TENANT

L'application doit être multi-organisation.

Architecture :

```text
Organisation A
   ├── Établissement 1
   ├── Établissement 2
   └── Utilisateurs

Organisation B
   ├── Établissement 1
   └── Utilisateurs
```

Aucune organisation ne doit pouvoir consulter les données d'une autre.

Implémenter cette isolation au niveau :

- API ;
- PostgreSQL ;
- Supabase ;
- Row Level Security ;
- stockage des fichiers.

---

# 22. ARCHITECTURE LOGICIELLE

Respecter :

- Clean Architecture ;
- Domain-Driven Design ;
- SOLID ;
- Repository Pattern ;
- séparation des responsabilités ;
- services métier ;
- DTO ;
- validation ;
- gestion centralisée des erreurs.

Pour le back-end :

```text
NestJS
├── Auth
├── Organizations
├── Establishments
├── Products
├── ProductImages
├── Inventory
├── Sales
├── POS
├── Tables
├── Orders
├── Customers
├── Purchases
├── Expenses
├── Reports
├── Notifications
└── Synchronization
```

---

# 23. API REST

Développer une API REST complète avec NestJS.

Documenter automatiquement avec :

```text
Swagger / OpenAPI
```

Prévoir :

```text
/api/v1/auth
/api/v1/organizations
/api/v1/establishments
/api/v1/products
/api/v1/product-images
/api/v1/inventory
/api/v1/sales
/api/v1/orders
/api/v1/tables
/api/v1/customers
/api/v1/reports
/api/v1/synchronization
```

---

# 24. TEMPS RÉEL

Utiliser WebSocket lorsque nécessaire pour :

- état des tables ;
- additions ;
- commandes ;
- stock ;
- notifications ;
- synchronisation ;
- tableau de bord.

---

# 25. INTERFACE UTILISATEUR

Créer une interface moderne inspirée des applications professionnelles de POS.

Principes :

- simplicité ;
- lisibilité ;
- rapidité ;
- grands boutons tactiles ;
- catalogue visuel ;
- navigation intuitive ;
- responsive design ;
- mode sombre ;
- mode clair.

L'interface doit s'adapter automatiquement :

```text
Smartphone
Tablet
Laptop
Desktop
```

---

# 26. TABLEAU DE BORD

### Propriétaire

Afficher :

- chiffre d'affaires ;
- bénéfice ;
- marges ;
- dépenses ;
- créances ;
- ventes ;
- produits les plus vendus ;
- stock ;
- KPI.

### Gérant

Afficher :

- ventes ;
- caisse ;
- stocks ;
- alertes ;
- performances.

### Serveur

Afficher :

- tables ouvertes ;
- additions ;
- ventes personnelles ;
- commissions.

### Magasinier

Afficher :

- stock ;
- mouvements ;
- ruptures ;
- alertes ;
- réceptions.

---

# 27. INSTALLATION PWA

La PWA doit proposer l'installation lorsqu'elle est supportée.

Prévoir :

```text
Ajouter à l'écran d'accueil
```

et :

```text
Installer l'application
```

Elle doit fonctionner comme une application autonome.

---

# 28. MISE À JOUR DE LA PWA

Mettre en place un mécanisme permettant de détecter une nouvelle version.

Afficher par exemple :

```text
Une nouvelle version de MaquisBar est disponible.

[Mettre à jour]
```

La mise à jour ne doit pas supprimer les opérations locales non synchronisées.

---

# 29. SÉCURITÉ

Implémenter :

- HTTPS ;
- JWT sécurisé ;
- gestion des sessions ;
- RBAC ;
- RLS ;
- validation des entrées ;
- rate limiting ;
- protection brute-force ;
- audit ;
- logs ;
- chiffrement ;
- gestion sécurisée des secrets ;
- politique CORS ;
- protection XSS ;
- protection CSRF lorsque nécessaire ;
- validation des uploads ;
- limitation de taille des images.

---

# 30. GESTION DES PHOTOS : SÉCURITÉ

Pour chaque image :

- contrôler MIME type ;
- contrôler extension ;
- contrôler taille ;
- contrôler dimensions ;
- renommer automatiquement ;
- empêcher l'exécution de fichiers ;
- générer un nom UUID ;
- utiliser des politiques Storage sécurisées ;
- empêcher l'accès à une image appartenant à une autre organisation.

Ne jamais faire confiance au nom du fichier envoyé par l'utilisateur.

---

# 31. PERFORMANCE

Objectifs :

- affichage initial rapide ;
- catalogue rapide ;
- chargement progressif des images ;
- lazy loading ;
- cache ;
- pagination ;
- compression ;
- requêtes PostgreSQL optimisées.

Pour les photos :

```text
Lazy loading
+
Thumbnail
+
WebP
+
Cache
```

---

# 32. CI/CD GITHUB ACTIONS

Créer des workflows automatisés.

### CI

À chaque Pull Request :

```text
Lint
↓
Tests
↓
Analyse statique
↓
Build
```

### CD

Après fusion dans `main` :

```text
Build
↓
Tests
↓
Build PWA
↓
Déploiement Web
```

Prévoir également le déploiement du backend NestJS vers une infrastructure cloud compatible.

---

# 33. ENVIRONNEMENTS

Créer :

```text
Development
Staging
Production
```

Variables :

```text
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
DATABASE_URL
JWT_SECRET
API_URL
STORAGE_BUCKET
```

Les secrets de production doivent être stockés dans :

```text
GitHub Secrets
```

ou le gestionnaire de secrets approprié.

Ils ne doivent jamais apparaître dans le code source.

---

# 34. OBSERVABILITÉ

Prévoir :

- logs ;
- erreurs ;
- événements de synchronisation ;
- temps de réponse ;
- erreurs API ;
- erreurs PWA ;
- état du stockage ;
- monitoring.

Créer un système permettant d'identifier rapidement :

```text
Utilisateur
→ appareil
→ opération
→ erreur
→ synchronisation
```

---

# 35. TESTS

Développer :

### Tests unitaires

- services ;
- règles métier ;
- calculs ;
- permissions ;
- stock ;
- caisse.

### Tests d'intégration

- API ;
- PostgreSQL ;
- Supabase ;
- Storage ;
- authentification.

### Tests end-to-end

Tester les parcours :

```text
Connexion
→ création produit
→ ajout photo
→ vente
→ paiement
→ clôture
```

Tester également :

```text
Connexion
→ perte Internet
→ vente hors ligne
→ retour Internet
→ synchronisation
```

---

# 36. DOCUMENTATION

Produire :

```text
README.md
ARCHITECTURE.md
DATABASE.md
API.md
DEPLOYMENT.md
SECURITY.md
OFFLINE_SYNC.md
STORAGE.md
PWA.md
CONTRIBUTING.md
USER_GUIDE.md
```

Le README doit expliquer :

- installation ;
- configuration ;
- lancement local ;
- connexion à Supabase ;
- migrations ;
- lancement du backend ;
- lancement de la PWA ;
- tests ;
- déploiement ;
- CI/CD.

---

# 37. DOCKER

Fournir :

```text
Dockerfile
docker-compose.yml
```

Le développement local doit pouvoir être lancé simplement.

Exemple :

```bash
docker compose up
```

---

# 38. LIVRABLES ATTENDUS

Produis successivement :

1. architecture générale ;
2. architecture PWA ;
3. architecture GitHub ;
4. architecture Supabase ;
5. architecture Storage ;
6. architecture offline-first ;
7. diagrammes UML ;
8. MCD ;
9. MLD ;
10. schéma PostgreSQL ;
11. migrations Supabase ;
12. politiques RLS ;
13. modèle de stockage des images ;
14. structure complète du monorepo ;
15. API REST ;
16. Swagger/OpenAPI ;
17. back-end NestJS ;
18. front-end Flutter Web ;
19. PWA ;
20. gestion des photos ;
21. système offline ;
22. système de synchronisation ;
23. système RBAC ;
24. tests unitaires ;
25. tests d'intégration ;
26. tests end-to-end ;
27. GitHub Actions ;
28. Docker ;
29. documentation ;
30. guide de déploiement ;
31. jeux de données de démonstration.

---

# 39. ORDRE DE DÉVELOPPEMENT IMPOSÉ

Ne tente pas de développer toute l'application en une seule étape.

Procède par phases.

## Phase 1 — Fondation

- GitHub ;
- monorepo ;
- architecture ;
- Flutter Web ;
- NestJS ;
- Supabase ;
- PostgreSQL ;
- environnement ;
- CI/CD.

## Phase 2 — Authentification

- utilisateurs ;
- rôles ;
- permissions ;
- sécurité.

## Phase 3 — Produits

- catégories ;
- produits ;
- photos ;
- Supabase Storage ;
- compression ;
- cache.

## Phase 4 — Stock

- mouvements ;
- inventaires ;
- pertes ;
- alertes.

## Phase 5 — POS

- catalogue ;
- panier ;
- vente ;
- paiement ;
- reçu.

## Phase 6 — Service à table

- salles ;
- zones ;
- tables ;
- additions ;
- serveurs.

## Phase 7 — Offline-first

- IndexedDB ;
- cache ;
- queue ;
- synchronisation ;
- conflits.

## Phase 8 — Rapports

- statistiques ;
- tableaux de bord ;
- exports.

## Phase 9 — PWA

- manifest ;
- service worker ;
- installation ;
- cache ;
- mise à jour.

## Phase 10 — Production

- sécurité ;
- tests ;
- CI/CD ;
- déploiement ;
- monitoring ;
- documentation.

---

# 40. RÈGLE IMPORTANTE DE DÉVELOPPEMENT

Tu ne dois pas simplement produire des exemples de code.

Tu dois produire un **véritable projet logiciel structuré**, exécutable et maintenable.

À chaque phase :

1. expliquer l'architecture ;
2. créer les fichiers nécessaires ;
3. fournir le code complet ;
4. expliquer où placer chaque fichier ;
5. fournir les commandes d'installation ;
6. fournir les commandes de test ;
7. vérifier les dépendances ;
8. vérifier les imports ;
9. vérifier la cohérence entre front-end et back-end ;
10. vérifier la compatibilité avec Supabase ;
11. vérifier la compatibilité PWA ;
12. vérifier le fonctionnement hors ligne ;
13. préparer le code pour GitHub.

Ne jamais générer de code fictif présenté comme fonctionnel.

---

# 41. RÈGLE DE GESTION DES IMAGES

Chaque fois qu'un utilisateur crée un article, l'application doit lui proposer immédiatement :

**Ajouter une photo**

avec les choix :

```text
📷 Prendre une photo
🖼️ Choisir dans la galerie
📁 Importer un fichier
❌ Utiliser l'image générique
```

Si aucune photo n'est fournie :

- utiliser automatiquement l'image générique de la catégorie ;
- permettre de la remplacer ultérieurement.

L'utilisateur doit pouvoir modifier la photo à tout moment.

---

# 42. OBJECTIF FINAL

Le produit final doit être une plateforme professionnelle **MaquisBar**, accessible sous forme de PWA, avec :

```text
GitHub
   │
   ├── Code source
   ├── Git
   ├── Issues
   ├── CI/CD
   └── Déploiement PWA
           │
           ▼
        PWA WEB
           │
           ▼
       NestJS API
           │
           ▼
       SUPABASE
       ├── PostgreSQL
       ├── Storage
       ├── Auth
       └── RLS
```

L'application doit être :

- moderne ;
- professionnelle ;
- responsive ;
- installable ;
- offline-first ;
- multi-organisation ;
- sécurisée ;
- évolutive ;
- maintenable ;
- documentée ;
- compatible GitHub ;
- compatible Supabase ;
- capable de gérer les photos de tous les articles ;
- capable de fonctionner sur smartphone, tablette et ordinateur.

**Priorité absolue : produire d'abord une version PWA fonctionnelle et stable du forfait Bar, puis étendre progressivement les fonctionnalités restaurant, multi-établissements et SaaS.**

Le code source doit être prêt à être versionné et maintenu dans GitHub, tandis que les données opérationnelles et les images doivent être hébergées de manière sécurisée dans Supabase.