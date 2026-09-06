'use strict';

// Service worker manuel pour le cache hors ligne (Phase 15 — PWA avancée).
//
// Le service worker généré par Flutter (flutter_service_worker.js) ne fait
// plus ce travail dans ce SDK : vérifié directement dans le navigateur, son
// seul comportement est de s'auto-désinstaller à l'activation
// (self.registration.unregister()) — Flutter a déprécié son mécanisme de
// service worker (https://github.com/flutter/flutter/issues/156910) et ce
// fichier n'existe plus que pour désinstaller d'anciennes installations. Un
// vrai service worker était donc à écrire à la main pour obtenir un cache
// hors ligne réel.
//
// Stratégie « cache au fil de l'eau » plutôt qu'une liste de préchargement
// figée : Flutter ne fournit plus de manifeste des fichiers de build (l'ancien
// flutter_service_worker.js listait chaque ressource avec son hash ; ce
// mécanisme a disparu avec lui), et une bonne partie de canvaskit/ (~37 Mo,
// plusieurs variantes CanvasKit/Skwasm selon le navigateur) ne doit de toute
// façon être mise en cache que pour la variante réellement chargée. Chaque
// requête même origine réussie est donc mise en cache après coup ; hors
// ligne, on retombe sur le cache, et une navigation sans version en cache
// retombe sur `index.html` (coquille de l'app) plutôt que sur une erreur.

const CACHE_NAME = 'chez-yasmine-shell-v1';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)));
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) {
    return; // laisse passer les requêtes vers l'API NestJS (autre origine) et tout ce qui n'est pas un GET.
  }

  event.respondWith(
    (async () => {
      try {
        const response = await fetch(request);
        if (response && response.ok) {
          const cache = await caches.open(CACHE_NAME);
          cache.put(request, response.clone());
        }
        return response;
      } catch (err) {
        const cached = await caches.match(request);
        if (cached) return cached;
        if (request.mode === 'navigate') {
          const shell = await caches.match('index.html');
          if (shell) return shell;
        }
        throw err;
      }
    })(),
  );
});
