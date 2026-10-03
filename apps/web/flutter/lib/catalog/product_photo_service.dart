import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../sync/connectivity_status.dart';
import 'catalog_repository.dart';
import 'models.dart';
import 'photo_cache.dart';
import 'photo_store.dart';

typedef PhotoDownloader = Future<Uint8List> Function(String url);

Future<Uint8List> _httpDownload(String url) async {
  final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
  if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
    throw http.ClientException('Téléchargement de la photo impossible (HTTP ${response.statusCode})');
  }
  return response.bodyBytes;
}

/// Photos produits lisibles hors ligne.
///
/// Les octets de la variante `small` sont téléchargés depuis une URL signée
/// (valable 1 h) puis conservés localement : la copie locale ne dépend plus
/// jamais de cette URL. Un produit sans copie locale hors ligne retombe
/// simplement sur l'icône de remplacement, sans attente — après un échec
/// réseau, plus aucun appel n'est tenté pendant [offlineBackoff].
class ProductPhotoService {
  ProductPhotoService({
    required this.cache,
    this.enabled = true,
    Future<bool> Function()? isOnline,
    PhotoDownloader? download,
    this.offlineBackoff = const Duration(seconds: 30),
    this.prefetchConcurrency = 3,
    DateTime Function()? now,
  })  : _isOnline = isOnline ?? ConnectivityStatus.isOnline,
        _download = download ?? _httpDownload,
        _now = now ?? DateTime.now;

  /// Sur les plateformes autres que le web, on garde l'affichage réseau
  /// historique (`Image.network`) : le stockage IndexedDB n'y existe pas.
  static ProductPhotoService instance = ProductPhotoService(cache: PhotoCache(IdbPhotoStore()), enabled: kIsWeb);

  final PhotoCache cache;
  final bool enabled;
  final Duration offlineBackoff;
  final int prefetchConcurrency;
  final Future<bool> Function() _isOnline;
  final PhotoDownloader _download;
  final DateTime Function() _now;

  final Map<String, Future<Uint8List?>> _inFlight = {};
  DateTime? _offlineUntil;
  bool _prefetching = false;

  bool get _inBackoff => _offlineUntil != null && _now().isBefore(_offlineUntil!);

  void _markOffline() => _offlineUntil = _now().add(offlineBackoff);

  /// Octets déjà en mémoire (aucun accès disque ni réseau) — évite un
  /// clignotement à chaque reconstruction d'une vignette.
  Uint8List? peek(String establishmentId, String imageId) => cache.peek(establishmentId, imageId);

  /// Copie locale d'abord ; sinon téléchargement si l'appareil est en ligne ;
  /// sinon `null` (l'appelant affiche l'icône de remplacement).
  Future<Uint8List?> load(CatalogRepository repository, String productId, String imageId) async {
    final local = await cache.get(repository.establishmentId, imageId);
    if (local != null) return local;
    return _fetch(repository, productId, imageId);
  }

  Future<Uint8List?> _fetch(CatalogRepository repository, String productId, String imageId) {
    final key = PhotoCache.keyFor(repository.establishmentId, imageId);
    return _inFlight[key] ??= _fetchOnce(repository, productId, imageId).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<Uint8List?> _fetchOnce(CatalogRepository repository, String productId, String imageId) async {
    if (_inBackoff) return null;
    try {
      if (!await _isOnline()) {
        _markOffline();
        return null;
      }
      final url = await repository.getImageUrl(productId, imageId, variant: 'small');
      final bytes = await _download(url);
      await cache.put(repository.establishmentId, imageId, bytes);
      return bytes;
    } on ApiException {
      // Le serveur a répondu (image supprimée, permission) : pas une coupure.
      return null;
    } catch (_) {
      _markOffline();
      return null;
    }
  }

  /// À appeler après un chargement réussi du catalogue complet : purge les
  /// photos qui ne sont plus référencées, puis télécharge en arrière-plan
  /// celles qui manquent. Ne bloque jamais l'interface.
  void onCatalogLoaded(CatalogRepository repository, List<Product> products) {
    if (!enabled) return;
    unawaited(_afterCatalogLoad(repository, products).catchError((Object _) {}));
  }

  Future<void> _afterCatalogLoad(CatalogRepository repository, List<Product> products) async {
    final referenced = {
      for (final product in products)
        for (final image in product.images) image.id,
    };
    await cache.retainOnly(repository.establishmentId, referenced);
    await prefetch(repository, products);
  }

  static ProductImage? primaryImageOf(Product product) =>
      product.images.where((i) => i.isPrimary).firstOrNull ?? product.images.firstOrNull;

  Future<void> prefetch(CatalogRepository repository, Iterable<Product> products) async {
    if (!enabled || _prefetching) return;
    _prefetching = true;
    try {
      final have = await cache.cachedImageIds(repository.establishmentId);
      final queue = <(String, String)>[
        for (final product in products)
          if (primaryImageOf(product) case final image? when !have.contains(image.id)) (product.id, image.id),
      ];
      var next = 0;
      Future<void> worker() async {
        while (next < queue.length && !_inBackoff) {
          final (productId, imageId) = queue[next++];
          await _fetch(repository, productId, imageId);
        }
      }

      await Future.wait(List.generate(prefetchConcurrency, (_) => worker()));
    } finally {
      _prefetching = false;
    }
  }

  /// Vide toutes les photos (déconnexion) — l'appareil peut être partagé et
  /// les photos sont privées.
  Future<void> clearAll() async {
    _offlineUntil = null;
    await cache.clear();
  }
}
