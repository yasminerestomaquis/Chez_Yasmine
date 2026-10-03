import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'photo_store.dart';

/// Cache local des photos produits (variante `small`, 400 px) pour qu'elles
/// restent affichables hors ligne.
///
/// La clé contient l'`imageId`, qui change dès qu'une photo est remplacée :
/// une entrée n'est donc jamais périmée, il suffit de purger celles que le
/// catalogue ne référence plus ([retainOnly]). Toute erreur du stockage
/// (quota dépassé, IndexedDB indisponible en navigation privée) est ignorée :
/// le cache est une optimisation, jamais une condition d'affichage.
class PhotoCache {
  PhotoCache(
    this._store, {
    this.maxBytes = 30 * 1024 * 1024,
    this.memoryEntries = 120,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PhotoStore _store;
  final int maxBytes;
  final int memoryEntries;
  final DateTime Function() _now;

  // Copie en mémoire des octets récemment lus : évite un aller-retour
  // IndexedDB à chaque reconstruction d'une vignette de la Caisse.
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();

  static String keyFor(String establishmentId, String imageId) => '$establishmentId/$imageId/small';

  void _remember(String key, Uint8List bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > memoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  Uint8List? peek(String establishmentId, String imageId) => _memory[keyFor(establishmentId, imageId)];

  Future<Uint8List?> get(String establishmentId, String imageId) async {
    final key = keyFor(establishmentId, imageId);
    final inMemory = _memory[key];
    if (inMemory != null) return inMemory;
    try {
      final bytes = await _store.read(key);
      if (bytes == null) return null;
      _remember(key, bytes);
      unawaited(_store.touch(key, _now()).catchError((Object _) {}));
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String establishmentId, String imageId, Uint8List bytes) async {
    final key = keyFor(establishmentId, imageId);
    try {
      await _store.write(key, bytes, _now());
      _remember(key, bytes);
      await _evictIfNeeded();
    } catch (_) {
      // Quota dépassé ou stockage indisponible : on garde l'image en mémoire
      // pour la session, sans copie locale durable.
      _remember(key, bytes);
    }
  }

  /// Identifiants d'images déjà stockées pour cet établissement.
  Future<Set<String>> cachedImageIds(String establishmentId) async {
    try {
      final prefix = '$establishmentId/';
      return {
        for (final e in await _store.entries())
          if (e.key.startsWith(prefix)) _imageIdOf(e.key),
      };
    } catch (_) {
      return {};
    }
  }

  static String _imageIdOf(String key) => key.split('/')[1];

  /// Supprime les photos de cet établissement dont l'image n'est plus
  /// référencée par le catalogue (produit supprimé, photo remplacée).
  Future<void> retainOnly(String establishmentId, Set<String> imageIds) async {
    try {
      final prefix = '$establishmentId/';
      final stale = [
        for (final e in await _store.entries())
          if (e.key.startsWith(prefix) && !imageIds.contains(_imageIdOf(e.key))) e.key,
      ];
      await _store.remove(stale);
      stale.forEach(_memory.remove);
    } catch (_) {}
  }

  Future<void> clear() async {
    _memory.clear();
    try {
      await _store.clear();
    } catch (_) {}
  }

  Future<void> _evictIfNeeded() async {
    final all = await _store.entries();
    var total = all.fold<int>(0, (sum, e) => sum + e.size);
    if (total <= maxBytes) return;
    all.sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    final toRemove = <String>[];
    for (final entry in all) {
      if (total <= maxBytes) break;
      toRemove.add(entry.key);
      total -= entry.size;
    }
    await _store.remove(toRemove);
    toRemove.forEach(_memory.remove);
  }
}
