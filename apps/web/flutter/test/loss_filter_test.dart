import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/losses/loss_filter.dart';
import 'package:chez_yasmine/losses/loss_models.dart';

Loss _loss(String id, DateTime createdAt, double value, {String? by}) => Loss(
      id: id,
      productId: 'p',
      productName: 'Produit',
      quantity: 1,
      estimatedValue: value,
      createdByName: by,
      createdAt: createdAt,
    );

void main() {
  group('canEditLosses (2026-09-20)', () {
    test('Super Administrateur, Gérant et Serveur peuvent modifier/supprimer', () {
      for (final role in ['Super Administrateur', 'Gérant', 'Serveur']) {
        expect(canEditLosses(role), isTrue, reason: role);
      }
    });

    test('les autres rôles ne le peuvent pas', () {
      for (final role in ['Administrateur', 'Propriétaire', 'Caissier', 'Magasinier', 'Comptable']) {
        expect(canEditLosses(role), isFalse, reason: role);
      }
    });
  });

  group('lossesOnDay / lossTotals', () {
    final monday = DateTime(2026, 9, 14, 10);
    final tuesday = DateTime(2026, 9, 15, 23, 30);
    final losses = [_loss('a', monday, 1200), _loss('b', monday, 300), _loss('c', tuesday, 500)];

    test('ne garde que les pertes du jour choisi', () {
      final result = lossesOnDay(losses, DateTime(2026, 9, 14));

      expect(result.map((l) => l.id), ['a', 'b']);
    });

    test('day nul : toutes les dates', () {
      expect(lossesOnDay(losses, null), hasLength(3));
    });

    test('un jour sans perte donne une liste vide', () {
      expect(lossesOnDay(losses, DateTime(2026, 9, 1)), isEmpty);
    });

    test('nombre et montant total portent sur la liste filtrée', () {
      final totals = lossTotals(lossesOnDay(losses, DateTime(2026, 9, 14)));

      expect(totals.count, 2);
      expect(totals.totalValue, 1500);
    });

    test('totaux à zéro pour une liste vide', () {
      final totals = lossTotals(const []);

      expect(totals.count, 0);
      expect(totals.totalValue, 0);
    });
  });

  test('Loss.fromJson lit le nom de l\'auteur, nul si absent', () {
    final base = {
      'id': 'l1',
      'productId': 'p',
      'productName': 'Bière',
      'quantity': 2,
      'estimatedValue': 800,
      'createdAt': '2026-09-14T10:00:00.000Z',
    };

    expect(Loss.fromJson({...base, 'createdByName': 'Awa Koné'}).createdByName, 'Awa Koné');
    expect(Loss.fromJson(base).createdByName, isNull);
  });

  test('Loss.fromJson lit le prix de vente unitaire (0 par défaut)', () {
    final base = {
      'id': 'l1',
      'productId': 'p',
      'productName': 'Gbêlê',
      'quantity': 1.5,
      'estimatedValue': 6000,
      'createdAt': '2026-09-14T10:00:00.000Z',
    };

    expect(Loss.fromJson({...base, 'unitSalePrice': 4000}).unitSalePrice, 4000);
    expect(Loss.fromJson(base).unitSalePrice, 0);
  });
}
