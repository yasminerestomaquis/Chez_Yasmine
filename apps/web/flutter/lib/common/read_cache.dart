import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Résultat d'une lecture qui peut venir du cache : [cachedAt] est nul pour une
/// donnée fraîche du serveur, et porte la date d'enregistrement quand le
/// serveur était injoignable et que la dernière copie locale a été servie.
class Cached<T> {
  Cached(this.value, {this.cachedAt});

  final T value;
  final DateTime? cachedAt;

  bool get isStale => cachedAt != null;
}

/// Vrai quand l'échec indique un serveur injoignable (aucune réponse HTTP, ou
/// passerelle indisponible — ex. démarrage à froid de Render), et non un rejet
/// métier du serveur : seul cas où servir une copie locale est légitime.
bool isNetworkFailure(Object error) {
  if (error is! ApiException) return true;
  return error.statusCode == 502 || error.statusCode == 503 || error.statusCode == 504;
}

/// Copie locale de lectures du serveur (tables, additions ouvertes, clients…)
/// pour qu'elles restent consultables hors ligne. Une entrée = le JSON brut de
/// la réponse + sa date d'enregistrement. Les entrées sont rangées par
/// établissement et effacées à la déconnexion ([clearAll]) : elles contiennent
/// des données personnelles (téléphones, soldes de crédit des clients).
class ReadCache {
  ReadCache(this.establishmentId, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _prefix = 'chez_yasmine_read_cache_';

  final String establishmentId;
  final DateTime Function() _now;

  String _key(String name) => '$_prefix${establishmentId}_$name';

  /// [savedAt] : à fournir pour modifier une copie SANS la faire passer pour
  /// plus récente qu'elle n'est (ex. retirer localement une addition encaissée).
  Future<void> save(String name, Object json, {DateTime? savedAt}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(name), jsonEncode({'savedAt': (savedAt ?? _now()).toIso8601String(), 'data': json}));
  }

  Future<({Object? json, DateTime savedAt})?> load(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(name));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return (json: decoded['data'], savedAt: DateTime.parse(decoded['savedAt'] as String));
    } catch (_) {
      return null;
    }
  }

  /// Efface toutes les copies de lecture, tous établissements confondus.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await prefs.remove(key);
    }
  }

  /// Lit [fetch] en ligne et en garde une copie ; si le serveur est
  /// injoignable, sert la dernière copie (avec sa date), ou relance l'erreur
  /// s'il n'y en a aucune. Un rejet métier du serveur (ApiException hors
  /// 502/503/504) n'est jamais masqué par une copie.
  Future<Cached<T>> read<T>({
    required String name,
    required Future<Object> Function() fetch,
    required T Function(Object json) parse,
  }) async {
    try {
      final json = await fetch();
      try {
        await save(name, json);
      } catch (_) {
        // Stockage plein ou indisponible : la lecture en ligne reste valable.
      }
      return Cached(parse(json));
    } catch (error) {
      if (!isNetworkFailure(error)) rethrow;
      final cached = await load(name);
      if (cached == null || cached.json == null) rethrow;
      return Cached(parse(cached.json!), cachedAt: cached.savedAt);
    }
  }
}
