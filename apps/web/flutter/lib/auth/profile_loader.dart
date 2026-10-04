import 'me_repository.dart';
import 'profile_cache.dart';

/// Même contenu : sert à ne PAS reconstruire l'écran (et perdre la position de
/// l'utilisateur) quand le rafraîchissement en arrière-plan ne change rien.
bool sameProfile(MyProfile a, MyProfile b) {
  if (a.id != b.id || a.email != b.email || a.fullName != b.fullName) return false;
  if (a.establishments.length != b.establishments.length) return false;
  for (var i = 0; i < a.establishments.length; i++) {
    final x = a.establishments[i];
    final y = b.establishments[i];
    if (x.id != y.id || x.name != y.name || x.role != y.role) return false;
  }
  return true;
}

/// Chargement du profil à l'ouverture de l'application (`GET /auth/me`), sans
/// faire attendre l'utilisateur quand une copie existe.
///
/// Avant, l'écran d'accueil restait sur un cercle de chargement jusqu'à la
/// réponse du serveur — jusqu'à 30 à 60 s au démarrage à froid de l'API
/// (Render, plan gratuit), même si le dernier profil connu était déjà sur
/// l'appareil. Maintenant : copie locale d'abord (affichée tout de suite),
/// serveur ensuite, en arrière-plan.
class ProfileLoader {
  ProfileLoader({
    required this.fetch,
    required this.cache,
    required this.currentUserId,
  });

  final Future<MyProfile> Function() fetch;
  final ProfileCache cache;
  final String? Function() currentUserId;

  /// Copie locale du profil, uniquement si elle appartient à l'utilisateur
  /// actuellement connecté : sur un appareil partagé, le profil d'un autre
  /// compte (établissements, rôle) ne doit jamais s'afficher, même une seconde.
  Future<MyProfile?> cachedForCurrentUser() async {
    final userId = currentUserId();
    if (userId == null) return null;
    final cached = await cache.load();
    return cached != null && cached.id == userId ? cached : null;
  }

  /// Lit le serveur et en garde une copie. Lève l'erreur d'origine.
  Future<MyProfile> fetchAndCache() async {
    final profile = await fetch();
    await cache.save(profile);
    return profile;
  }

  /// Rafraîchissement en arrière-plan : `null` si le serveur est injoignable
  /// ou lent à répondre — la copie déjà affichée reste valable.
  Future<MyProfile?> refresh() async {
    try {
      return await fetchAndCache();
    } catch (_) {
      return null;
    }
  }
}
