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

Autrement dit : il s'installe, s'active, **se désinstalle lui-même**, puis force un rechargement des onglets. Ce n'est plus un service worker de cache — c'est un désinstallateur, présent uniquement pour nettoyer d'anciennes installations d'une version antérieure de l'app qui, elle, avait un vrai service worker. Flutter a officiellement déprécié ce mécanisme ([flutter/flutter#156910](https://github.com/flutter/flutter/issues/156910)).

**Correction (2026-09-17)** : contrairement à ce qui était noté ici initialement, `_flutter.loader.load(...)` (le `flutter_bootstrap.js` généré par défaut) **enregistrait bel et bien** ce service worker déprécié à chaque chargement de page — `flutter build web` insère `serviceWorkerSettings: { serviceWorkerVersion: "<hash du build>" }` dans l'appel généré, sauf configuration contraire. Vérifié directement dans le code source de `flutter_tools` (`packages/flutter_tools/lib/src/web/bootstrap.dart`, `packages/flutter_tools/lib/src/build_system/targets/web.dart`) : ce comportement est piloté par `--pwa-strategy` (déprécié, sera retiré) ou, de façon pérenne, par la présence d'un fichier `web/flutter_bootstrap.js` personnalisé — voir section dédiée ci-dessous.

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
  - **Bug corrigé (2026-09-17)** : le bandeau réapparaissait après un simple rechargement (clic sur « Actualiser »), constaté par l'utilisateur en conditions réelles. Cause réelle, distincte de celle du 2026-09-07 : `flutter_service_worker.js` (le désinstallateur déprécié, voir plus haut) est réenregistré à **chaque** chargement de page avec un identifiant de version différent à chaque build (`serviceWorkerVersion`) — son cycle installation/activation/désinstallation déclenche donc un `controllerchange`, satisfaisant le garde `hadControllerBeforeUpdate`, à quasi chaque visite plutôt que seulement lors d'un vrai déploiement. Corrigé en empêchant purement et simplement son enregistrement (voir « Désactiver l'enregistrement du service worker déprécié de Flutter » ci-dessous) — `pwa_cache_worker.js` reste le seul service worker de cette application, et son propre cycle de vie (déclenché uniquement quand son contenu change réellement) redevient la seule source de `controllerchange`.
- **Installation** : intercepte `beforeinstallprompt` (Chrome/Edge) pour proposer un bouton « Installer » plutôt que de dépendre uniquement de l'icône native du navigateur. Déclenchement vérifié par simulation directe de l'événement ; le déclenchement **réel** par le navigateur dépend de critères d'engagement (visites répétées, temps passé) que cet environnement de test ne peut pas reproduire.

Les deux bandeaux sont masqués par défaut (vérifié) et n'apparaissent que sur l'événement correspondant.

## Désactiver l'enregistrement du service worker déprécié de Flutter (`web/flutter_bootstrap.js`, 2026-09-17)

`flutter build web` génère normalement `flutter_bootstrap.js` lui-même, avec un appel `_flutter.loader.load({ serviceWorkerSettings: { serviceWorkerVersion: "<hash>" } })` — c'est ce `serviceWorkerSettings` qui déclenche l'enregistrement de `flutter_service_worker.js` (voir bug ci-dessus). Flutter permet de fournir son propre `web/flutter_bootstrap.js` : s'il existe, le générateur l'utilise **tel quel** (après substitution des jetons `{{flutter_js}}`/`{{flutter_build_config}}`) au lieu d'en générer un — confirmé dans `packages/flutter_tools/lib/src/build_system/targets/web.dart` (`if (inputFlutterBootstrapJs.existsSync()) { inputBootstrapContent = ... } else { generateDefaultFlutterBootstrapScript(...) }`).

Le fichier `web/flutter_bootstrap.js` de ce projet reprend donc exactement le même contenu que celui généré par défaut, à l'exception près qu'il n'appelle `_flutter.loader.load()` **sans** `serviceWorkerSettings` — reproduisant exactement ce que `generateDefaultFlutterBootstrapScript` produit déjà quand `includeServiceWorkerSettings` vaut `false` (le cas `--pwa-strategy=none`), mais sans dépendre de ce flag CLI explicitement marqué comme voué à disparaître (`compile.dart` : « The --pwa-strategy option is deprecated and will be removed in a future Flutter release »). Solution pérenne, indépendante de la présence future de ce flag.

Aucun effet sur `pwa_cache_worker.js` : son enregistrement (`navigator.serviceWorker.register('pwa_cache_worker.js')`, dans `index.html`) est totalement indépendant de `flutter_bootstrap.js`.

## Optimisation

- Tree-shaking des polices déjà actif par défaut (`flutter build web`) : `CupertinoIcons.ttf` réduit de 99,4 %, `MaterialIcons-Regular.otf` de 99,2 % (mesuré sur chaque build de cette session).
- **`--wasm` évalué, non adopté** : `flutter build web` rapporte systématiquement « Wasm dry run succeeded » (compatibilité du code applicatif confirmée), mais l'app utilise plusieurs plugins fédérés (`image_picker`, `file_picker`, `connectivity_plus`, `shared_preferences`) dont la compatibilité runtime complète avec la cible `dart2wasm` n'a pas été vérifiée ici — l'adopter sans pouvoir tester chaque plugin en conditions réelles aurait été un changement non vérifié plutôt qu'une optimisation confirmée.

## Vérifications effectuées

- Service worker : cycle de vie complet vérifié dans un vrai navigateur (installation, activation, prise de contrôle, mise en cache réelle, **rendu hors ligne réel** après arrêt du serveur).
- Bandeaux de mise à jour/installation : présents, masqués par défaut, réagissent correctement aux événements navigateur correspondants (simulés).
- `flutter analyze`/`flutter test`/`flutter build web` ✅ (aucun fichier Dart modifié par cette phase — seuls `web/index.html` et le nouveau `web/pwa_cache_worker.js`).
- **Non vérifié** : un vrai cycle de mise à jour de bout en bout (deux versions déployées successivement) et un déclenchement naturel (non simulé) de `beforeinstallprompt` — tous deux nécessitent un déploiement réel, hors de portée de cet environnement.
- **Correctif du 2026-09-17** : `flutter build web` local confirme que `build/web/flutter_bootstrap.js` ne contient plus `serviceWorkerSettings` (juste `_flutter.loader.load();`), et l'application se charge et fonctionne normalement servie statiquement (`preview_start`). **Non vérifié en conditions réelles** : que le bandeau ne réapparaît effectivement plus après un rechargement sur un vrai déploiement Render/Vercel (nécessite un déploiement réel suivi d'un rechargement, comme les autres scénarios de bout en bout de cette page).
