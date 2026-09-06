/// Base URL de l'API NestJS.
///
/// Configurable par environnement (prompt maître §37 : development/staging/
/// production) via `--dart-define=API_URL=...` au moment du build/run,
/// sans avoir à modifier ce fichier ni le committer avec une valeur figée.
/// Par défaut `http://localhost:3000` (développement local) — pas d'instance
/// déployée accessible pour l'instant (voir PROJECT_PLAN.md : `DATABASE_URL`
/// réel manquant dans l'environnement de développement).
class ApiConfig {
  static const String baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');
}
