import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chez_yasmine/catalog/catalog_cache.dart';
import 'package:chez_yasmine/catalog/models.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('les photos de chaque produit (id, principale, position) survivent à un aller-retour hors ligne', () async {
    final cache = CatalogCache('est-1');
    await cache.save(
      [Category(id: 'c1', name: 'Bières')],
      [
        Product(
          id: 'p1',
          name: 'Celtia',
          status: 'active',
          stockQuantity: 12,
          salePrice: 500,
          categoryId: 'c1',
          images: [
            ProductImage(id: 'img-a', isPrimary: false, position: 1),
            ProductImage(id: 'img-b', isPrimary: true, position: 0),
          ],
        ),
        Product(id: 'p2', name: 'Sans photo', status: 'active', stockQuantity: 0),
      ],
    );

    final (_, products) = (await cache.load())!;

    expect(products.first.images.map((i) => i.id), ['img-a', 'img-b']);
    expect(products.first.images.last.isPrimary, isTrue);
    expect(products.first.images.first.position, 1);
    expect(products.last.images, isEmpty);
  });

  test('un ancien cache sans clé « images » reste lisible', () async {
    SharedPreferences.setMockInitialValues({
      'chez_yasmine_catalog_cache_est-1':
          '{"categories":[],"products":[{"id":"p1","name":"X","categoryId":null,"salePrice":100,"stockQuantity":3,"status":"active"}]}',
    });

    final (_, products) = (await CatalogCache('est-1').load())!;

    expect(products.single.images, isEmpty);
  });
}
