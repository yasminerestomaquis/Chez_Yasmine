# Prompt de développement

**Plateforme SaaS et mobile de gestion de maquis, bars, restaurants et boîtes de nuit**
*Édition de référence : module Bar / Boîte de nuit — service à table et gestion multi-serveurs*
*Basé sur le Cahier des charges fonctionnel et technique v2.0 — avec gestion des photos par article*

---

## Rôle à endosser

Agis comme une équipe complète composée d'un architecte logiciel, d'un chef de projet, d'un UX/UI designer, d'un expert DevOps, d'un développeur full stack senior, d'un expert PostgreSQL et d'un expert en sécurité informatique.

## Mission

Concevoir et développer une plateforme professionnelle de gestion de bars, maquis, restaurants et lounges, avec un niveau de qualité adapté à une commercialisation. Le développement doit être évolutif, sécurisé, modulaire et documenté.

## Contrainte d'originalité

L'application doit être entièrement originale dans son architecture, son code et son interface. Elle peut s'inspirer des fonctionnalités généralement proposées par les solutions modernes de gestion d'établissements de restauration, mais ne doit reproduire aucun code, élément graphique ou contenu propriétaire d'une solution existante.

## Contexte métier

Les maquis, bars, restaurants et boîtes de nuit font face à des pertes de stock difficiles à détecter, des écarts de caisse récurrents, une traçabilité insuffisante des ventes, une gestion manuelle sur cahiers, une absence de statistiques fiables et une impossibilité de contrôler l'activité à distance. L'application doit permettre une gestion complète de l'établissement depuis un smartphone, une tablette, un ordinateur (Windows) ou un navigateur web, en mode comptoir, en mode bar / boîte de nuit avec service à table, et à terme en mode restaurant complet. La réalisation est **priorisée sur l'édition Bar** (service à table, plan de salle, additions ouvertes, équipe complète de l'établissement).

---

## 1. Technologies imposées

**Front-end**
- Flutter (base de code unique) : Android, iOS, Windows, Responsive Web

**Back-end**
- NestJS en TypeScript

**Base de données**
- PostgreSQL
- Prisma ORM (accès aux données et migrations)

**Authentification**
- JWT avec jeton de rafraîchissement (refresh token)
- OTP par SMS
- Authentification biométrique sur mobile (empreinte digitale, Face ID)

**Infrastructure**
- Docker et Docker Compose
- Nginx en reverse proxy, HTTPS
- CI/CD via GitHub Actions

**Stockage**
- Amazon S3 ou service compatible (photos et images des articles, exports)
- Formats acceptés JPEG, PNG, WebP ; compression et génération automatique de vignettes (thumbnails) à l'upload, pour un affichage rapide dans le catalogue et en caisse
- Sauvegarde automatique régulière

**Cache**
- Redis, pour les données à forte fréquence de lecture (tableau de bord, stock, disponibilité des tables)

## 2. Principes d'architecture logicielle

Construis une architecture propre respectant :
- Clean Architecture et Domain-Driven Design (DDD)
- Repository Pattern pour l'accès aux données
- CQRS lorsque c'est pertinent (flux à forte charge en lecture/écriture)
- Principes SOLID sur l'ensemble du code back-end
- API REST intégralement documentée au format Swagger / OpenAPI
- Canal WebSocket pour la mise à jour en temps réel (état des tables et additions, niveau de stock, notifications, tableau de bord)

## 3. Rôles utilisateurs et permissions

Prévoir un système de rôles avec permissions individuellement configurables (RBAC), selon la configuration par défaut suivante.

**Rôles de plateforme (niveau SaaS)**
- **Super Administrateur** : supervise l'ensemble des organisations clientes, les abonnements, la facturation globale, la configuration technique et la sécurité de la solution.
- **Administrateur** : représente une organisation cliente pouvant regrouper plusieurs établissements ; crée et configure les établissements, gère les comptes Propriétaire, consulte les rapports consolidés.

**Rôles d'établissement**
- **Propriétaire** : tous les droits sur son ou ses établissements — utilisateurs et permissions, ensemble des rapports et des bénéfices, abonnement. Peut opérer lui-même la caisse.
- **Gérant** : ventes, stock, achats, inventaires, pertes, clôture de caisse. Ne voit pas, par défaut, le bénéfice net, les charges, ni les autres établissements.
- **Caissier** : caisse comptoir exclusivement — vente, encaissement, remises autorisées, ventes à crédit. Ne voit pas le stock, les pertes, ni les rapports financiers.
- **Serveur** : ouvre ses propres tables, y ajoute des articles, encaisse la clôture de ses propres additions. Ne voit ni les ventes des autres serveurs, ni la recette globale, ni le stock ou les prix d'achat.
- **Magasinier** : gère les stocks (entrées, sorties, transferts, inventaires, alertes) ; consulte les prix d'achat pour la valorisation, mais pas les ventes ni les données financières globales.
- **Comptable** : données financières consolidées (recette, marges, charges, créances) et module de comptabilité simplifiée. Aucun droit d'administration opérationnelle.

Implémente la matrice de permissions par défaut suivante (à rendre configurable via un module dédié) :

| Donnée / fonction | Propriétaire | Gérant | Caissier | Serveur | Magasinier | Comptable |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Caisse comptoir (vente et encaissement) | ✓ | ✓ | ✓ | — | — | — |
| Tables et additions personnelles | ✓ | ✓ | — | ✓ | — | — |
| Vue globale des ventes de l'établissement | ✓ | ✓ | — | — | — | ✓ |
| Bénéfice net et marges | ✓ | — | — | — | — | ✓ |
| Prix d'achat des produits | ✓ | — | — | — | ✓ | ✓ |
| Charges et dépenses d'exploitation | ✓ | — | — | — | — | ✓ |
| Stock — consultation et mouvements | ✓ | ✓ | — | — | ✓ | — |
| Achats — bons de commande et réceptions | ✓ | ✓ | — | — | ✓ | — |
| Fournisseurs et dettes fournisseurs | ✓ | ✓ | — | — | ✓ | ✓ |
| Clôture de caisse | ✓ | ✓ | ✓ | — | — | ✓ |
| Comptabilité (journal, banques, bilan) | ✓ | — | — | — | — | ✓ |
| Crédits et encours clients | ✓ | — | ✓ | — | — | ✓ |
| Fidélité clients | ✓ | ✓ | ✓ | — | — | — |
| Gestion de l'équipe et des permissions | ✓ | — | — | — | — | — |
| Rapports et exports | ✓ | ✓ | — | — | — | ✓ |
| Paramétrage général de l'établissement | ✓ | — | — | — | — | — |

## 4. Modules fonctionnels à développer

Développe l'intégralité des 20 modules suivants.

1. **Authentification et gestion des comptes** — connexion propriétaire, création directe des comptes du personnel, JWT + refresh token, OTP SMS, biométrie mobile, récupération de mot de passe, révocation instantanée, gestion des rôles/permissions.
2. **Établissements et points de vente** — création/modification/suppression, multi-établissements et multi-organisations, logo, horaires, paramètres fiscaux, changement de mode (comptoir / bar / restaurant).
3. **Catégories de produits** — CRUD des catégories (boissons, bières, vins, liqueurs, spiritueux, cocktails, eaux, snacks, grillades, autres).
4. **Produits** — référence, code-barres, QR code, catégorie, fournisseur, prix d'achat, prix de vente, TVA, unité, stock minimum, description ; **gestion des photos par article** : ajout d'une ou plusieurs photos par prise de vue directe (caméra) ou import depuis la galerie, remplacement et suppression, recadrage simple, affectation d'une photo principale par article ; image générique par catégorie utilisée par défaut tant qu'aucune photo n'est affectée.
5. **Stocks** — entrées, sorties automatiques, transferts, inventaires et corrections avec écart calculé, ruptures, alertes de stock faible configurables, historique des mouvements.
6. **Fournisseurs** — fiches, commandes, livraisons, achats, dettes, historique.
7. **Achats** — bons de commande, réceptions, factures, paiements, historique, circuit de validation.
8. **Caisse et ventes** — caisse tactile avec catalogue en vignettes illustrées (photo, nom et prix de chaque article), recherche instantanée, filtres par catégorie, paiement espèces / Mobile Money / carte bancaire / mixte, vente à crédit, remises (% ou montant fixe), annulation, remboursement, impression et réimpression du reçu.
9. **Tables** — plan de salle par zone, ouverture, réservation (créneau, couverts), transfert, fusion, division de facture, décrémentation du stock en temps réel à l'ajout d'article, clôture de l'addition ; sélecteur d'articles illustré par les photos produits lors de la prise de commande, pour une identification visuelle rapide en salle.
10. **Serveurs** — attribution des tables, suivi des ventes, statistiques, calcul des commissions selon un taux paramétrable.
11. **Clôture de caisse** — calcul automatique du montant en espèces attendu, saisie du montant compté, écart calculé et justification requise si écart significatif, historique par établissement/date/auteur.
12. **Clients** — nom, téléphone, adresse, historique, programme de fidélité, plafond de crédit.
13. **Crédits** — ventes à crédit dans la limite du plafond, remboursements, échéances, historique, solde restant (encours).
14. **Dépenses** — loyer, salaires, carburant, eau, électricité, entretien, divers, périodicité, prise en compte dans le bénéfice net.
15. **Pertes** — casse, offert, péremption, vol, consommation interne ; produit, quantité, auteur et justification obligatoires ; déduction automatique du stock.
16. **Comptabilité simplifiée** — caisse, banques, journal de caisse, bilan simplifié par période.
17. **Rapports et statistiques** — journalier/hebdomadaire/mensuel/annuel ; ventes par serveur/produit/catégorie ; bénéfices, marges, dépenses, mouvements de stock, créances, rentabilité ; envoi automatique du bilan quotidien par WhatsApp ; export PDF/Excel/CSV.
18. **Notifications** — alertes de stock, clôture de caisse, rapport quotidien, rappels de crédits, nouveaux achats, sauvegarde terminée ; canaux SMS, e-mail, WhatsApp, push.
19. **Paramétrage** — TVA, devise, langues, imprimantes, sauvegardes, utilisateurs et permissions, horaires, modèles de reçus.
20. **Fonctionnement hors ligne et synchronisation** — base locale SQLite sur mobile/desktop, file d'attente des opérations hors connexion, synchronisation automatique et résolution des conflits au retour du réseau, sans perte ni doublon.

## 5. Tableau de bord (par rôle)

- **Propriétaire / Comptable** : chiffre d'affaires du jour, ventes en cours, ventes du mois, bénéfice estimé, marges, dépenses, créances clients, évolution des ventes, produits les plus vendus, KPI, alertes de stock.
- **Gérant / Caissier** : ventes et caisse du jour (sans bénéfice ni charges), état du stock, alertes, suivi de la clôture de caisse.
- **Serveur** : ses tables ouvertes, montant de ses additions en cours, total de ses ventes personnelles, commissions du jour.
- **Magasinier** : état du stock, mouvements récents, alertes et ruptures, suivi des réceptions.

## 6. Modèle de données à concevoir

Modélise au minimum les entités suivantes, avec leurs relations (à formaliser en diagrammes UML puis en MCD/MLD PostgreSQL) : Organisation, Établissement, Point de vente, Utilisateur, Rôle/Permission, Catégorie, Produit, Photo produit (une ou plusieurs par article, avec photo principale), Mouvement de stock, Fournisseur, Achat (commande/réception/facture/paiement), Table, Réservation, Addition, Vente, Paiement, Client, Mouvement de crédit, Perte, Dépense, Clôture de caisse, Écriture comptable, Commission serveur, Notification, Abonnement.

## 7. Exigences non fonctionnelles

- Interface moderne, simple et intuitive, cohérente sur mobile, tablette, web et Windows ; ergonomie tactile adaptée à un usage rapide en caisse.
- Identification visuelle rapide de chaque article grâce à sa photo, aussi bien en caisse qu'en prise de commande à table, y compris hors ligne (photos mises en cache localement).
- Fonctionnement hors ligne complet avec synchronisation automatique.
- Sauvegarde automatique et régulière des données.
- Disponibilité cible de 99,5 %.
- Documentation technique complète et guide utilisateur.
- Code source propre, modulaire, commenté, maintenable, conforme aux bonnes pratiques industrielles.

## 8. Exigences de sécurité

- Chiffrement des données sensibles au repos (AES) et en transit (HTTPS/TLS).
- Authentification forte : JWT + refresh token, OTP SMS, biométrie mobile.
- Limitation du nombre de tentatives de connexion (protection contre les attaques par force brute).
- Permissions par rôle configurables (RBAC).
- Journalisation exhaustive et audit des actions sensibles (ventes, annulations, remboursements, pertes, clôtures, modifications de compte et de permission).
- Sauvegardes automatiques et procédure de restauration documentée.
- Sécurisation des API REST et des échanges WebSocket.

## 9. Exigences de performance

- Temps de réponse inférieur à 2 secondes pour les opérations courantes.
- Support d'au moins 500 utilisateurs simultanés.
- Architecture horizontalement scalable, conteneurisée.
- Mise en cache Redis des données à forte fréquence de lecture.

## 10. Livrables attendus

Produis successivement :

1. Architecture complète
2. Diagrammes UML
3. Modèle Entité-Association
4. Modèle relationnel PostgreSQL
5. Scripts SQL
6. Structure complète du projet
7. API REST documentée (Swagger)
8. Développement complet du back-end
9. Développement complet du front-end Flutter
10. Interfaces modernes
11. Module d'authentification
12. Tests unitaires
13. Tests d'intégration
14. Documentation technique
15. Guide utilisateur
16. Procédure de déploiement Docker
17. Configuration CI/CD
18. Jeux de données de démonstration

---

*Le code produit doit être propre, commenté, modulaire, maintenable et conforme aux bonnes pratiques industrielles. Priorise la réalisation du forfait Bar (modules 1 à 20 dans leur usage établissement mono-site) avant d'étendre au forfait Réseau (multi-établissements, rôles Super Administrateur et Administrateur).*
