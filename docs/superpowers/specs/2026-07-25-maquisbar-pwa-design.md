# Conception — MaquisBar PWA locale

*Version : 1 (première itération, mono-établissement, hors ligne)*
*Dérivée de : `PROMPT/prompt-developpement-maquisbar-v3.md`*

## Objectif

Livrer une application de gestion simple pour un maquis-bar mono-site, installable comme PWA et entièrement utilisable hors ligne sur ordinateur, tablette et téléphone.

## Périmètre de la première version

L'application couvre les opérations quotidiennes essentielles :

- tableau de bord des ventes, du stock et des alertes ;
- catalogue de produits illustrés, catégories, prix, stock et seuil d'alerte ;
- caisse tactile : panier, recherche, remises, paiements espèces, Mobile Money, carte ou mixte, reçu imprimable ;
- service à table : plan de salle, ouverture d'addition, commandes, transfert et encaissement ;
- clients et ventes à crédit avec suivi du solde ;
- mouvements de stock, dépenses et pertes ;
- rapports journaliers et exports de sauvegarde/import JSON ;
- paramètres de l'établissement, devise FCFA et code PIN administrateur.

Les services distants du cahier des charges initial (NestJS, PostgreSQL, SMS, WhatsApp, authentification biométrique, multi-site, synchronisation cloud, rôles granulaires) sont explicitement hors périmètre de cette première version locale. L'architecture restera découplée afin qu'ils puissent être ajoutés ultérieurement.

Sont également reportés à une phase ultérieure (non traités dans cette version) : fournisseurs et achats, fidélité client, comptabilité simplifiée (journal/bilan), commissions serveur, notifications multi-canal.

## Architecture

La PWA sera une application front-end statique organisée par fonctionnalités. Un service de stockage encapsule IndexedDB et expose les opérations métier : produits, ventes, tables, stock, crédits et rapports. Les calculs de caisse et de stock résident dans des services purs, testables sans navigateur.

Un service worker met en cache les fichiers de l'application et les images intégrées afin que l'application se charge sans réseau après sa première installation. Les données restent sur l'appareil de l'utilisateur. Une sauvegarde JSON, exportable et réimportable depuis les paramètres, protège contre la perte de données du navigateur.

## Expérience utilisateur

La navigation latérale donne accès aux modules principaux. La caisse privilégie de grandes tuiles tactiles avec image, nom et prix. Le plan de salle représente les tables par statut : libre, occupée ou à encaisser. Les montants affichés sont en francs CFA et les écrans mobiles passent à une navigation compacte.

Au premier lancement, des données de démonstration sont créées (boissons, plats, tables et clients). Elles permettent de prendre l'application en main immédiatement et peuvent être remplacées depuis le catalogue.

## Données et règles métier

- Une vente validée crée un paiement et diminue le stock des lignes vendues.
- Une addition de table reste ouverte jusqu'à son encaissement ; elle peut recevoir plusieurs commandes.
- Une vente à crédit exige un client et augmente son encours ; un remboursement le diminue.
- Une perte ou une sortie de stock est justifiée et historisée.
- Les indicateurs et rapports sont calculés à partir des transactions enregistrées localement.
- Un code PIN local protège l'accès administratif ; ce n'est pas une sécurité multi-utilisateur de niveau serveur.

## Gestion des erreurs

Les opérations refusent les quantités invalides, le stock insuffisant et les paiements incomplets. Les actions sensibles demandent confirmation. L'import vérifie le format du fichier avant de remplacer les données locales et conseille d'exporter une sauvegarde préalable.

## Tests et validation

Les règles métier pures sont couvertes par des tests unitaires : total de panier, ventilation de paiement, stock, crédit et agrégats de rapport. La construction de production, le manifeste PWA et le service worker sont vérifiés avant livraison. Le parcours de démonstration comprend l'ouverture d'une table, l'ajout d'articles, l'encaissement et le contrôle de la décrémentation du stock.

## Décisions explicites

- **Périmètre** : mono-établissement uniquement — pas de Super Administrateur / Administrateur / abonnement (confirmé par l'utilisateur, en écart avec le cahier des charges SaaS multi-organisations initial).
- **Technologie** : application web statique moderne (React + TypeScript + Vite) plutôt que Flutter/NestJS, car la priorité est une PWA locale simple et immédiatement exploitable.
- **Stockage** : IndexedDB (via une couche d'accès dédiée) plutôt que PostgreSQL, car aucun serveur ne doit être installé.
- **Identité** : code PIN local plutôt que comptes, JWT et OTP, car la version est mono-poste/multi-usage local. Pas de rôles granulaires (Propriétaire/Gérant/Caissier/Serveur/Magasinier/Comptable) dans cette version — un seul niveau d'accès protégé par PIN pour les actions sensibles.
- **Installation** : manifeste web et service worker, compatibles avec l'installation depuis un navigateur récent.

## Hors périmètre (rappel)

Pour éviter toute ambiguïté lors de l'implémentation : pas de backend NestJS, pas de PostgreSQL, pas de Redis, pas de S3 (les photos sont stockées localement, ex. en Blob/DataURL dans IndexedDB), pas d'OTP SMS, pas de biométrie, pas de WhatsApp/SMS/e-mail, pas de multi-établissement, pas de rôles RBAC, pas de synchronisation cloud.
