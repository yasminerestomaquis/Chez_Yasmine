import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/catalog/catalog_repository.dart';
import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/catalog/photo_cache.dart';
import 'package:chez_yasmine/catalog/photo_store.dart';
import 'package:chez_yasmine/catalog/product_photo.dart';
import 'package:chez_yasmine/catalog/product_photo_service.dart';

// PNG 1x1 valide, pour que Image.memory puisse réellement le décoder.
final Uint8List _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
  0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakeCatalogRepository extends CatalogRepository {
  FakeCatalogRepository({this.failWith}) : super(ApiClient(), 'est-1');

  Object? failWith;
  final List<String> urlRequests = [];

  @override
  Future<String> getImageUrl(String productId, String imageId, {String variant = 'medium'}) async {
    urlRequests.add('$productId:$imageId:$variant');
    if (failWith != null) throw failWith!;
    return 'https://storage.test/$imageId.webp?token=abc';
  }
}

Product product(String id, List<String> imageIds) => Product(
      id: id,
      name: id,
      status: 'active',
      stockQuantity: 1,
      images: [
        for (var i = 0; i < imageIds.length; i++) ProductImage(id: imageIds[i], isPrimary: i == 0, position: i),
      ],
    );

void main() {
  late PhotoCache cache;
  late FakeCatalogRepository repository;
  late List<String> downloads;
  late bool online;
  late DateTime clock;

  ProductPhotoService buildService({Future<Uint8List> Function(String url)? download}) => ProductPhotoService(
        cache: cache,
        isOnline: () async => online,
        download: download ??
            (url) async {
              downloads.add(url);
              return _png;
            },
        now: () => clock,
      );

  setUp(() {
    cache = PhotoCache(MemoryPhotoStore());
    repository = FakeCatalogRepository();
    downloads = [];
    online = true;
    clock = DateTime(2026, 10, 3, 8);
  });

  group('ProductPhotoService.load', () {
    test('copie locale : renvoyée sans appel réseau, même hors ligne', () async {
      await cache.put('est-1', 'img-1', _png);
      online = false;
      final service = buildService();

      expect(await service.load(repository, 'p1', 'img-1'), _png);
      expect(repository.urlRequests, isEmpty);
      expect(downloads, isEmpty);
    });

    test('en ligne sans copie : télécharge la variante small puis la conserve', () async {
      final service = buildService();

      expect(await service.load(repository, 'p1', 'img-1'), _png);
      expect(repository.urlRequests, ['p1:img-1:small']);
      expect(downloads, ['https://storage.test/img-1.webp?token=abc']);

      final again = buildService();
      expect(await again.load(repository, 'p1', 'img-1'), _png);
      expect(downloads, hasLength(1), reason: 'la seconde lecture vient de la copie locale');
    });

    test('hors ligne sans copie : null, sans aucun appel à l\'endpoint d\'URL signée', () async {
      online = false;
      final service = buildService();

      expect(await service.load(repository, 'p1', 'img-1'), isNull);
      expect(repository.urlRequests, isEmpty);
    });

    test('après un échec réseau, plus aucun appel pendant la période de repli, puis reprise', () async {
      final service = buildService(download: (url) async => throw const SocketLikeException());

      expect(await service.load(repository, 'p1', 'a'), isNull);
      expect(repository.urlRequests, hasLength(1));

      expect(await service.load(repository, 'p1', 'b'), isNull);
      expect(await service.load(repository, 'p1', 'c'), isNull);
      expect(repository.urlRequests, hasLength(1), reason: 'aucun appel pendant le repli');

      clock = clock.add(const Duration(seconds: 31));
      expect(await service.load(repository, 'p1', 'd'), isNull);
      expect(repository.urlRequests, hasLength(2));
    });

    test('une réponse HTTP du serveur (ex. image supprimée) n\'enclenche pas le repli hors ligne', () async {
      repository.failWith = ApiException(404, 'Image introuvable');
      final service = buildService();

      expect(await service.load(repository, 'p1', 'a'), isNull);
      expect(await service.load(repository, 'p1', 'b'), isNull);
      expect(repository.urlRequests, hasLength(2));
    });

    test('deux demandes simultanées de la même image ne téléchargent qu\'une fois', () async {
      final completer = Completer<Uint8List>();
      final service = buildService(download: (url) {
        downloads.add(url);
        return completer.future;
      });

      final first = service.load(repository, 'p1', 'img-1');
      final second = service.load(repository, 'p1', 'img-1');
      await Future<void>.delayed(Duration.zero);
      completer.complete(_png);

      expect(await first, _png);
      expect(await second, _png);
      expect(downloads, hasLength(1));
    });
  });

  group('ProductPhotoService.prefetch / onCatalogLoaded', () {
    test('télécharge les photos principales manquantes, 3 en parallèle au maximum', () async {
      await cache.put('est-1', 'deja', _png);
      var running = 0;
      var maxRunning = 0;
      final service = buildService(download: (url) async {
        running++;
        if (running > maxRunning) maxRunning = running;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        downloads.add(url);
        return _png;
      });

      await service.prefetch(repository, [
        product('p0', ['deja']),
        for (var i = 1; i <= 8; i++) product('p$i', ['img-$i', 'secondaire-$i']),
      ]);

      expect(downloads, hasLength(8), reason: 'la photo déjà en cache et les photos secondaires sont ignorées');
      expect(maxRunning, lessThanOrEqualTo(3));
      expect(maxRunning, greaterThan(1));
      expect(await cache.cachedImageIds('est-1'), containsAll(['img-1', 'img-8', 'deja']));
      expect(await cache.cachedImageIds('est-1'), isNot(contains('secondaire-1')));
    });

    test('coupure en cours de route : le préchargement s\'arrête, sans exception', () async {
      var calls = 0;
      final service = buildService(download: (url) async {
        calls++;
        throw const SocketLikeException();
      });

      await service.prefetch(repository, [for (var i = 0; i < 10; i++) product('p$i', ['img-$i'])]);

      expect(calls, lessThanOrEqualTo(3), reason: 'seuls les téléchargements déjà lancés ont échoué');
    });

    test('onCatalogLoaded purge d\'abord les images qui ne sont plus au catalogue', () async {
      await cache.put('est-1', 'remplacee', _png);
      await cache.put('est-1', 'supprimee', _png);
      await cache.put('est-1', 'toujours-la', _png);
      final service = buildService();

      service.onCatalogLoaded(repository, [
        product('p1', ['nouvelle', 'toujours-la']),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await cache.cachedImageIds('est-1'), {'nouvelle', 'toujours-la'});
    });

    test('désactivé : onCatalogLoaded et prefetch ne font rien', () async {
      final service = ProductPhotoService(cache: cache, enabled: false, isOnline: () async => true, download: (_) async => _png);

      service.onCatalogLoaded(repository, [product('p1', ['a'])]);
      await service.prefetch(repository, [product('p1', ['a'])]);

      expect(repository.urlRequests, isEmpty);
    });
  });

  test('clearAll vide le cache et lève le repli hors ligne', () async {
    await cache.put('est-1', 'img-1', _png);
    final service = buildService(download: (url) async => throw const SocketLikeException());
    await service.load(repository, 'p1', 'autre');

    await service.clearAll();

    expect(await cache.cachedImageIds('est-1'), isEmpty);
    expect(cache.peek('est-1', 'img-1'), isNull);
  });

  group('ProductPhoto (widget)', () {
    late ProductPhotoService previous;

    setUp(() => previous = ProductPhotoService.instance);
    tearDown(() => ProductPhotoService.instance = previous);

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 80,
                height: 80,
                child: ProductPhoto(
                  repository: repository,
                  productId: 'p1',
                  imageId: 'img-1',
                  backgroundColor: Colors.green,
                  fallback: const Icon(Icons.local_drink_outlined),
                ),
              ),
            ),
          ),
        );

    testWidgets('copie locale : la photo s\'affiche hors ligne, sans icône de remplacement', (tester) async {
      await tester.runAsync(() => cache.put('est-1', 'img-1', _png));
      online = false;
      ProductPhotoService.instance = buildService();

      await pump(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.local_drink_outlined), findsNothing);
      expect(repository.urlRequests, isEmpty);
    });

    testWidgets('hors ligne sans copie : icône de remplacement, sans attente', (tester) async {
      online = false;
      ProductPhotoService.instance = buildService();

      await pump(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(find.byIcon(Icons.local_drink_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('en ligne sans copie : télécharge, affiche, et stocke pour la prochaine fois', (tester) async {
      ProductPhotoService.instance = buildService();

      await pump(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(await tester.runAsync(() => cache.cachedImageIds('est-1')), {'img-1'});
    });
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}
