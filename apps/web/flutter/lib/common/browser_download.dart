// Déclenche le téléchargement d'un fichier binaire depuis le navigateur —
// PWA Web uniquement (pas d'accès système de fichiers), voir CLAUDE.md
// « Architecture ». Utilisé pour les exports qui ne sont pas de simples
// dialogues texte (ex. Excel — l'export CSV existant se contente d'un
// `SelectableText`, un binaire ne peut pas se copier-coller).
//
// Import conditionnel : `package:web` (implémentation réelle) n'est
// disponible que sous compilation Web (`dart.library.js_interop`) — sans
// ça, `flutter test` (exécuté sur la VM Dart, pas un navigateur) échoue à
// charger tout fichier qui en dépend, même transitivement.
export 'browser_download_stub.dart'
    if (dart.library.js_interop) 'browser_download_web.dart';
