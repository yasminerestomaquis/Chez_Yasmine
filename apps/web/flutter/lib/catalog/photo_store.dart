import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

class PhotoEntry {
  PhotoEntry({required this.key, required this.size, required this.lastUsed});

  final String key;
  final int size;
  final DateTime lastUsed;
}

/// Stockage local des octets d'une photo, indexé par clé
/// `<établissement>/<imageId>/<variante>` — voir [PhotoCache].
abstract class PhotoStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes, DateTime lastUsed);
  Future<void> touch(String key, DateTime lastUsed);
  Future<List<PhotoEntry>> entries();
  Future<void> remove(Iterable<String> keys);
  Future<void> clear();
}

/// Stockage factice (tests, ou plateforme sans IndexedDB).
class MemoryPhotoStore implements PhotoStore {
  final Map<String, Uint8List> _bytes = {};
  final Map<String, DateTime> _lastUsed = {};

  @override
  Future<Uint8List?> read(String key) async => _bytes[key];

  @override
  Future<void> write(String key, Uint8List bytes, DateTime lastUsed) async {
    _bytes[key] = bytes;
    _lastUsed[key] = lastUsed;
  }

  @override
  Future<void> touch(String key, DateTime lastUsed) async {
    if (_bytes.containsKey(key)) _lastUsed[key] = lastUsed;
  }

  @override
  Future<List<PhotoEntry>> entries() async => [
        for (final e in _bytes.entries) PhotoEntry(key: e.key, size: e.value.length, lastUsed: _lastUsed[e.key]!),
      ];

  @override
  Future<void> remove(Iterable<String> keys) async {
    for (final key in keys) {
      _bytes.remove(key);
      _lastUsed.remove(key);
    }
  }

  @override
  Future<void> clear() async {
    _bytes.clear();
    _lastUsed.clear();
  }
}

const _photosStore = 'photos';
const _metaStore = 'meta';

/// IndexedDB : deux object stores, `photos` (octets) et `meta` (taille et
/// dernière utilisation) — la liste des entrées pour l'éviction ne relit
/// ainsi jamais les images elles-mêmes.
class IdbPhotoStore implements PhotoStore {
  IdbPhotoStore({IdbFactory? factory, this.dbName = 'chez_yasmine_photos'}) : _factory = factory ?? idbFactoryBrowser;

  final IdbFactory _factory;
  final String dbName;
  Future<Database>? _db;

  Future<Database> get _database {
    return _db ??= _factory
        .open(
          dbName,
          version: 1,
          onUpgradeNeeded: (event) {
            event.database.createObjectStore(_photosStore);
            event.database.createObjectStore(_metaStore);
          },
        )
        .catchError((Object error) {
      _db = null;
      throw error;
    });
  }

  static Map<String, Object?> _meta(String key, int size, DateTime lastUsed) => {
        'key': key,
        'size': size,
        'lastUsed': lastUsed.millisecondsSinceEpoch,
      };

  @override
  Future<Uint8List?> read(String key) async {
    final db = await _database;
    final txn = db.transaction(_photosStore, idbModeReadOnly);
    final value = await txn.objectStore(_photosStore).getObject(key);
    await txn.completed;
    return _toBytes(value);
  }

  static Uint8List? _toBytes(Object? value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is ByteBuffer) return value.asUint8List();
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  @override
  Future<void> write(String key, Uint8List bytes, DateTime lastUsed) async {
    final db = await _database;
    final txn = db.transaction([_photosStore, _metaStore], idbModeReadWrite);
    await txn.objectStore(_photosStore).put(bytes, key);
    await txn.objectStore(_metaStore).put(_meta(key, bytes.length, lastUsed), key);
    await txn.completed;
  }

  @override
  Future<void> touch(String key, DateTime lastUsed) async {
    final db = await _database;
    final txn = db.transaction(_metaStore, idbModeReadWrite);
    final store = txn.objectStore(_metaStore);
    final existing = await store.getObject(key);
    if (existing is Map) {
      await store.put(_meta(key, (existing['size'] as num).toInt(), lastUsed), key);
    }
    await txn.completed;
  }

  @override
  Future<List<PhotoEntry>> entries() async {
    final db = await _database;
    final txn = db.transaction(_metaStore, idbModeReadOnly);
    final all = await txn.objectStore(_metaStore).getAll();
    await txn.completed;
    return [
      for (final raw in all)
        if (raw is Map)
          PhotoEntry(
            key: raw['key'] as String,
            size: (raw['size'] as num).toInt(),
            lastUsed: DateTime.fromMillisecondsSinceEpoch((raw['lastUsed'] as num).toInt()),
          ),
    ];
  }

  @override
  Future<void> remove(Iterable<String> keys) async {
    final list = keys.toList();
    if (list.isEmpty) return;
    final db = await _database;
    final txn = db.transaction([_photosStore, _metaStore], idbModeReadWrite);
    final photos = txn.objectStore(_photosStore);
    final meta = txn.objectStore(_metaStore);
    for (final key in list) {
      await photos.delete(key);
      await meta.delete(key);
    }
    await txn.completed;
  }

  @override
  Future<void> clear() async {
    final db = await _database;
    final txn = db.transaction([_photosStore, _metaStore], idbModeReadWrite);
    await txn.objectStore(_photosStore).clear();
    await txn.objectStore(_metaStore).clear();
    await txn.completed;
  }
}
