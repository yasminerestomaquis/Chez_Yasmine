// Bootstrap personnalisé (voir la doc citée dans index.html :
// https://docs.flutter.dev/platform-integration/web/initialization) — remplace
// celui généré par défaut pour NE PAS enregistrer le service worker déprécié
// de Flutter (flutter_service_worker.js).
//
// Ce service worker n'a plus qu'un seul comportement dans ce SDK : s'auto-
// désinstaller à l'activation (voir pwa_cache_worker.js). Comme il est
// réenregistré à CHAQUE chargement de page (identifiant de version différent
// à chaque build), son cycle installation/activation/désinstallation déclenche
// un évènement "controllerchange" quasi à chaque visite — pas seulement lors
// d'un vrai déploiement — ce que index.html interprétait à tort comme "une
// nouvelle version est disponible", d'où le bandeau qui réapparaissait après
// un simple rechargement (constaté par l'utilisateur, 2026-09-17). En omettant
// `serviceWorkerSettings` ici, `_flutter.loader.load()` ne tente plus du tout
// cet enregistrement — tout le cache hors-ligne réel passe déjà uniquement
// par pwa_cache_worker.js (voir ce fichier), qui n'est pas affecté.
{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load();
