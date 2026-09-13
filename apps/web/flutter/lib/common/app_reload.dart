// Recharge la page — PWA Web uniquement, même raisonnement que
// browser_download.dart : un rechargement complet du navigateur est le seul
// moyen fiable de récupérer une nouvelle version déployée de l'application
// (nouveau `main.dart.js`), en plus de rafraîchir les données affichées.
//
// Import conditionnel : `package:web` n'est disponible que sous compilation
// Web (`dart.library.js_interop`) — sans ça, `flutter test` (VM Dart, pas un
// navigateur) échoue à charger tout fichier qui en dépend, même
// transitivement.
export 'app_reload_stub.dart'
    if (dart.library.js_interop) 'app_reload_web.dart';
