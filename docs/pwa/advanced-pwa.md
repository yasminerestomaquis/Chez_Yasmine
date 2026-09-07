# PWA avancée — Chez Yasmine

## Découverte de départ : le service worker généré par Flutter ne fait plus rien

L'hypothèse de départ pour cette phase était que `flutter build web` fournissait déjà un vrai cache applicatif hors ligne via `flutter_service_worker.js` (comportement historique de Flutter Web). **Vérifié directement dans le navigateur : ce n'est plus le cas dans ce SDK.** Le fichier généré est désormais :

```js
self.addEventListener('install', () => { self.skipWaiting(); });
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    await self.registration.unregister();
    // force un rechargement de tous les onglets ouverts
  })());
});
```

Autrement dit : il s'installe, s'active, **se désinstalle lui-même**, puis force un rechargement des onglets. Ce n'est plus un service worker de cache — c'est un désinstallateur, présent uniquement pour nettoyer d'anciennes installations d'une version antérieure de l'app qui, elle, avait un vrai service worker. Flutter a officiellement déprécié ce mécanisme ([flutter/flutter#156910](https://github.com/flutter/flutter/issues/156910)) et `_flutter.loader.load(...)` (`flutter_bootstrap.js`) ne l'enregistre même plus automatiquement sur une première visite — confirmé par un test direct (`navigator.serviceWorker.getRegistration()` restait vide après un chargement complet, sans intervention).

Conséquence : le cache hors ligne pour cette PWA devait être **écrit à la main**, il n'existe plus « gratuitement ».

## Service worker de cache (`web/pwa_cache_worker.js`)

Stratégie « cache au fil de l'eau » (runtime caching) plutôt qu'une liste de préchargement figée :

- Flutter ne publie plus de manifeste des fichiers de build (l'ancien service worker listait chaque ressource avec son hash — disparu avec lui) ; il n'y a donc plus de source fiable pour une liste exhaustive à précharger.
- `canvaskit/` fait ~37 Mo à lui seul, avec plusieurs variantes selon le moteur du navigateur (chromium/webparagraph/skwasm/wimp) — tout précharger gaspillerait de la bande passante pour des variantes jamais utilisées par un visiteur donné.

Fonctionnement : toute requête **même origine** en GET réussie est mise en cache après coup (`chez-yasmine-shell-v1`) ; hors ligne, la réponse vient du cache ; pour une navigation sans version en cache, on retombe sur `index.html` (coquille de l'app). Les requêtes vers l'API NestJS (autre origine) ne sont jamais interceptées — seuls les fichiers statiques du build le sont.

À l'activation, tout cache d'un nom différent de `CACHE_NAME` est supprimé — bumper `CACHE_NAME` (ex. `-v2`) est le mécanisme de purge en cas de changement de structure du cache.

**Vérifié en conditions réelles**, dans le navigateur, contre un vrai build (`flutter build web` servi statiquement) :
1. Première visite : le service worker s'enregistre, s'active, prend le contrôle (`clients.claim()`), et met déjà en cache les premières ressources (polices, assets, logo).
2. Deuxième visite : `main.dart.js`, `flutter_bootstrap.js` et `index.html` sont désormais aussi en cache (le premier chargement les avait obtenus avant que le service worker ne prenne le contrôle — comportement standard des service workers, pas un bug).
3. **Test hors ligne réel** : le serveur statique a été arrêté (origine réellement injoignable, pas une simulation), puis la page rechargée — l'application s'est chargée et affichée normalement (écran de connexion complet), entièrement servie depuis le cache. Seule trace dans la console : une tentative interne de Flutter de mettre à jour son propre `flutter_service_worker.js` (déprécié) qui échoue proprement en `catch`, sans impact sur l'app.

## Bandeau de mise à jour et bouton d'installation (`web/index.html`)

En JavaScript brut dans `index.html`, pas en Dart (`package:web`/`dart:js_interop`) : ce dernier choix aurait fait dépendre `main.dart` (importé par `widget_test.dart`) de bindings web, alors que `flutter test` compile et exécute sur la VM, pas dans un navigateur — un risque de casser toute la suite de tests pour une fonctionnalité qui n'a pas besoin d'être en Dart.

- **Mise à jour** : écoute `navigator.serviceWorker.addEventListener('controllerchange', ...)`, affiche un bandeau « Nouvelle version disponible » avec un bouton qui recharge la page. Déclenchement vérifié par simulation directe de l'événement dans le navigateur (un vrai scénario de bout en bout demanderait de déployer deux versions successives, non réalisable dans cet environnement).
  - **Bug corrigé (2026-09-07)** : le bandeau s'affichait dès la toute première visite, jamais seulement sur une vraie mise à jour. Cause — confirmée par le point 1 ci-dessus (« prend le contrôle (`clients.claim()`) ») : `controllerchange` se déclenche aussi quand le service worker prend le contrôle pour la première fois, pas seulement quand il en remplace un précédent. Corrigé en ne montrant le bandeau que si `navigator.serviceWorker.controller` était déjà défini juste avant l'événement (`hadControllerBeforeUpdate`) — signature d'un contrôleur remplacé, donc d'une vraie mise à jour, absente lors d'une première installation.
- **Installation** : intercepte `beforeinstallprompt` (Chrome/Edge) pour proposer un bouton « Installer » plutôt que de dépendre uniquement de l'icône native du navigateur. Déclenchement vérifié par simulation directe de l'événement ; le déclenchement **réel** par le navigateur dépend de critères d'engagement (visites répétées, temps passé) que cet environnement de test ne peut pas reproduire.

Les deux bandeaux sont masqués par défaut (vérifié) et n'apparaissent que sur l'événement correspondant.

## Optimisation

- Tree-shaking des polices déjà actif par défaut (`flutter build web`) : `CupertinoIcons.ttf` réduit de 99,4 %, `MaterialIcons-Regular.otf` de 99,2 % (mesuré sur chaque build de cette session).
- **`--wasm` évalué, non adopté** : `flutter build web` rapporte systématiquement « Wasm dry run succeeded » (compatibilité du code applicatif confirmée), mais l'app utilise plusieurs plugins fédérés (`image_picker`, `file_picker`, `connectivity_plus`, `shared_preferences`) dont la compatibilité runtime complète avec la cible `dart2wasm` n'a pas été vérifiée ici — l'adopter sans pouvoir tester chaque plugin en conditions réelles aurait été un changement non vérifié plutôt qu'une optimisation confirmée.

## Vérifications effectuées

- Service worker : cycle de vie complet vérifié dans un vrai navigateur (installation, activation, prise de contrôle, mise en cache réelle, **rendu hors ligne réel** après arrêt du serveur).
- Bandeaux de mise à jour/installation : présents, masqués par défaut, réagissent correctement aux événements navigateur correspondants (simulés).
- `flutter analyze`/`flutter test`/`flutter build web` ✅ (aucun fichier Dart modifié par cette phase — seuls `web/index.html` et le nouveau `web/pwa_cache_worker.js`).
- **Non vérifié** : un vrai cycle de mise à jour de bout en bout (deux versions déployées successivement) et un déclenchement naturel (non simulé) de `beforeinstallprompt` — tous deux nécessitent un déploiement réel, hors de portée de cet environnement.
