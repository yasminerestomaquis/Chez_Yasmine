import 'package:web/web.dart' as web;

/// Recharge la page depuis le serveur — récupère un nouveau `main.dart.js`
/// s'il a été déployé depuis le dernier chargement (même effet que le
/// bouton « Actualiser » du bandeau « Nouvelle version disponible », voir
/// web/index.html, mais déclenchable à la demande depuis l'app elle-même).
void reloadApp() {
  web.window.location.reload();
}
