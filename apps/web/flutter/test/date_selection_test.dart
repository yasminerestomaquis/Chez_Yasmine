import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/home/date_selection.dart';
import 'package:chez_yasmine/reports/report_models.dart';

PaymentCategoryBreakdown _b(double cash, double mm, double boissons, double plats, {double gbele = 0}) =>
    PaymentCategoryBreakdown(
      totalRevenue: cash + mm,
      cashRevenue: cash,
      mobileMoneyRevenue: mm,
      boissonsSansGbeleRevenue: boissons,
      gbeleRevenue: gbele,
      platsRevenue: plats,
      boissonsSansGbeleCash: boissons,
      boissonsSansGbeleMobileMoney: 0,
      gbeleCash: gbele,
      gbeleMobileMoney: 0,
      platsCash: 0,
      platsMobileMoney: plats,
    );

ReportSummary _s(int sales, int lowStock) => ReportSummary(
      from: DateTime(2026, 9, 20),
      to: DateTime(2026, 9, 20),
      revenue: 0,
      salesCount: sales,
      discountTotal: 0,
      cogs: 0,
      grossMargin: 0,
      expenses: 0,
      losses: 0,
      netProfit: 0,
      receivables: 0,
      lowStockCount: lowStock,
      topProducts: const [],
      productProfitability: const [],
      serverPerformance: const [],
    );

void main() {
  final today = DateTime(2026, 9, 20);

  group('dateFilterLabel / periodPhrase (sélection multiple, 2026-09-20)', () {
    test("aujourd'hui seul", () {
      expect(dateFilterLabel({today}, today), "Aujourd'hui");
      expect(periodPhrase({today}, today), "aujourd'hui");
    });

    test('un autre jour seul', () {
      final d = DateTime(2026, 9, 14);
      expect(dateFilterLabel({d}, today), 'Lundi 14 septembre');
      expect(periodPhrase({d}, today), 'du lundi 14 septembre');
    });

    test('plusieurs jours', () {
      final dates = {today, DateTime(2026, 9, 19), DateTime(2026, 9, 18)};
      expect(dateFilterLabel(dates, today), '3 jours sélectionnés');
      expect(periodPhrase(dates, today), 'sur 3 jours');
    });
  });

  group('mergeBreakdowns / mergeSummaries', () {
    test('additionne chaque ventilation jour par jour', () {
      final merged = mergeBreakdowns([_b(1000, 500, 800, 700), _b(200, 300, 100, 400)]);

      expect(merged.cashRevenue, 1200);
      expect(merged.mobileMoneyRevenue, 800);
      expect(merged.totalRevenue, 2000);
      expect(merged.boissonsSansGbeleRevenue, 900);
      expect(merged.platsRevenue, 1100);
      expect(merged.platsMobileMoney, 1100);
    });

    test('additionne aussi le groupe Gbêlê, séparément de Boissons sans Gbêlê (2026-09-24)', () {
      final merged = mergeBreakdowns([
        _b(1000, 500, 800, 700, gbele: 300),
        _b(200, 300, 100, 400, gbele: 150),
      ]);

      expect(merged.gbeleRevenue, 450);
      expect(merged.boissonsSansGbeleRevenue, 900);
    });

    test('cumule les commandes mais garde les alertes stock (état courant) au maximum', () {
      final merged = mergeSummaries([_s(4, 2), _s(6, 2), _s(1, 3)]);

      expect(merged.salesCount, 11);
      expect(merged.lowStockCount, 3);
    });
  });
}
