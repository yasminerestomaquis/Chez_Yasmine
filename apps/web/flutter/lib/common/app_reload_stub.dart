/// Utilisé quand `dart.library.js_interop` n'est pas disponible (tests
/// exécutés sur la VM Dart) — cette app n'a de toute façon aucune cible
/// non-Web (voir CLAUDE.md « Architecture »), donc jamais appelée en dehors
/// des tests, où [reloadApp] n'est pas exercé directement.
void reloadApp() {
  throw UnsupportedError('reloadApp n\'est disponible que sur Flutter Web.');
}
