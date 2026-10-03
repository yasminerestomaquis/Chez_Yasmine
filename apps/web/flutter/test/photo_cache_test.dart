import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';

import 'package:chez_yasmine/catalog/photo_cache.dart';
import 'package:chez_yasmine/catalog/photo_store.dart';

Uint8List bytes(int length, [int fill = 1]) => Uint8List.fromList(List.filled(length, fill));

class ThrowingStore extends MemoryPhotoStore {
  @override
  Future<void> write(String key, Uint8List bytes, DateTime lastUsed) => throw StateError('QuotaExceededError');

  @override
  Future<Uint8List?> read(String key) => throw StateError('IndexedDB indisponible');

  @override
  Future<List<PhotoEntry>> entries() => throw StateError('IndexedDB indisponible');
}

void main() {
  group('PhotoCache (stockage factice)', () {
    late DateTime clock;
    late PhotoCache cache;

    setUp(() {
      clock = DateTime(2026, 10, 3, 8);
      cache = PhotoCache(MemoryPhotoStore(), maxBytes: 100, now: () => clock);
    });

    test('écriture puis lecture, clé propre à l\'établissement', () async {
      await cache.put('est-1', 'img-1', bytes(10, 7));

      expect(await cache.get('est-1', 'img-1'), bytes(10, 7));
      expect(await cache.get('est-2', 'img-1'), isNull);
      expect(await cache.get('est-1', 'img-inconnue'), isNull);
    });

    test('éviction : au-delà du plafond, les images les moins récemment utilisées partent d\'abord', () async {
      await cache.put('est-1', 'ancienne', bytes(40));
      clock = clock.add(const Duration(minutes: 1));
      await cache.put('est-1', 'milieu', bytes(40));
      clock = clock.add(const Duration(minutes: 1));
      // 40 + 40 + 40 = 120 > 100 : « ancienne » est évincée.
      await cache.put('est-1', 'recente', bytes(40));

      expect(await cache.cachedImageIds('est-1'), {'milieu', 'recente'});
    });

    test('éviction : une image relue devient la plus récente et survit', () async {
      final store = MemoryPhotoStore();
      cache = PhotoCache(store, maxBytes: 100, memoryEntries: 0, now: () => clock);
      await cache.put('est-1', 'a', bytes(40));
      clock = clock.add(const Duration(minutes: 1));
      await cache.put('est-1', 'b', bytes(40));
      clock = clock.add(const Duration(minutes: 1));
      await cache.get('est-1', 'a');
      await Future<void>.delayed(Duration.zero);
      clock = clock.add(const Duration(minutes: 1));
      await cache.put('est-1', 'c', bytes(40));

      expect(await cache.cachedImageIds('est-1'), {'a', 'c'});
    });

    test('retainOnly supprime les images plus référencées, de cet établissement seulement', () async {
      await cache.put('est-1', 'garde', bytes(5));
      await cache.put('est-1', 'orpheline', bytes(5));
      await cache.put('est-2', 'orpheline', bytes(5));

      await cache.retainOnly('est-1', {'garde'});

      expect(await cache.cachedImageIds('est-1'), {'garde'});
      expect(await cache.cachedImageIds('est-2'), {'orpheline'});
      expect(await cache.get('est-1', 'orpheline'), isNull);
    });

    test('clear vide tout (déconnexion), mémoire comprise', () async {
      await cache.put('est-1', 'a', bytes(5));
      await cache.put('est-2', 'b', bytes(5));

      await cache.clear();

      expect(cache.peek('est-1', 'a'), isNull);
      expect(await cache.get('est-1', 'a'), isNull);
      expect(await cache.cachedImageIds('est-2'), isEmpty);
    });

    test('un stockage en erreur (quota, IndexedDB indisponible) est ignoré sans exception', () async {
      final broken = PhotoCache(ThrowingStore());

      await broken.put('est-1', 'a', bytes(5));
      expect(await broken.get('est-1', 'a'), bytes(5), reason: 'gardée en mémoire pour la session');
      expect(await broken.get('est-1', 'b'), isNull);
      expect(await broken.cachedImageIds('est-1'), isEmpty);
      await broken.retainOnly('est-1', {});
    });
  });

  group('IdbPhotoStore (IndexedDB, implémentation mémoire)', () {
    late IdbPhotoStore store;

    setUp(() => store = IdbPhotoStore(factory: newIdbFactoryMemory(), dbName: 'test_${DateTime.now().microsecondsSinceEpoch}'));

    test('écriture, lecture, entrées, touch, suppression et vidage', () async {
      final t0 = DateTime(2026, 10, 3, 8);
      await store.write('est-1/a/small', bytes(30, 3), t0);
      await store.write('est-1/b/small', bytes(20, 4), t0);

      expect(await store.read('est-1/a/small'), bytes(30, 3));
      expect(await store.read('est-1/zzz/small'), isNull);

      final entries = await store.entries();
      expect({for (final e in entries) e.key: e.size}, {'est-1/a/small': 30, 'est-1/b/small': 20});
      expect(entries.first.lastUsed, t0);

      final t1 = t0.add(const Duration(hours: 1));
      await store.touch('est-1/a/small', t1);
      final touched = (await store.entries()).firstWhere((e) => e.key == 'est-1/a/small');
      expect(touched.lastUsed, t1);
      expect(touched.size, 30);

      await store.remove(['est-1/a/small']);
      expect(await store.read('est-1/a/small'), isNull);
      expect((await store.entries()).map((e) => e.key), ['est-1/b/small']);

      await store.clear();
      expect(await store.entries(), isEmpty);
    });

    test('PhotoCache fonctionne de bout en bout par-dessus IndexedDB', () async {
      final cache = PhotoCache(store, maxBytes: 50, memoryEntries: 0);
      await cache.put('est-1', 'a', bytes(30, 9));
      await cache.put('est-1', 'b', bytes(30, 8));

      expect((await cache.cachedImageIds('est-1')).length, 1, reason: 'plafond respecté');
      expect(await cache.get('est-1', 'b'), bytes(30, 8));
    });
  });
}
