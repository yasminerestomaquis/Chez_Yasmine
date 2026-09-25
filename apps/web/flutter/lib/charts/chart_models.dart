class WeeklyPoint {
  WeeklyPoint({required this.day, required this.value});

  final String day;
  final double value;

  factory WeeklyPoint.fromJson(Map<String, dynamic> json) => WeeklyPoint(
    day: json['day'] as String,
    value: (json['value'] as num).toDouble(),
  );
}

class WeeklySeries {
  WeeklySeries({required this.id, required this.name, required this.points});

  final String? id;
  final String name;
  final List<WeeklyPoint> points;

  factory WeeklySeries.fromJson(Map<String, dynamic> json) => WeeklySeries(
    id: json['id'] as String?,
    name: json['name'] as String,
    points: (json['points'] as List<dynamic>)
        .map((e) => WeeklyPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class WeeklyChart {
  WeeklyChart({
    required this.weekStart,
    required this.weekEnd,
    required this.series,
  });

  final String weekStart;
  final String weekEnd;
  final List<WeeklySeries> series;

  /// Total de la semaine affichée, toutes séries confondues (ex. toutes les
  /// catégories sélectionnées) — affiché en tête de graphique.
  double get total => series
      .expand((s) => s.points)
      .fold(0.0, (sum, p) => sum + p.value);

  factory WeeklyChart.fromJson(Map<String, dynamic> json) => WeeklyChart(
    weekStart: json['weekStart'] as String,
    weekEnd: json['weekEnd'] as String,
    series: (json['series'] as List<dynamic>)
        .map((e) => WeeklySeries.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class MonthlyPoint {
  MonthlyPoint({required this.month, required this.value});

  final String month;
  final double value;

  factory MonthlyPoint.fromJson(Map<String, dynamic> json) => MonthlyPoint(
    month: json['month'] as String,
    value: (json['value'] as num).toDouble(),
  );
}

class MonthlyChart {
  MonthlyChart({required this.year, required this.months});

  final int year;
  final List<MonthlyPoint> months;

  /// Total de l'année affichée, tous mois confondus — affiché en tête du
  /// graphique « Top recettes »/« Top bénéfices » (demande utilisateur du
  /// 2026-09-25), même principe que `WeeklyChart.total`.
  double get total => months.fold(0.0, (sum, m) => sum + m.value);

  factory MonthlyChart.fromJson(Map<String, dynamic> json) => MonthlyChart(
    year: json['year'] as int,
    months: (json['months'] as List<dynamic>)
        .map((e) => MonthlyPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class RankingItem {
  RankingItem({required this.id, required this.name, required this.value});

  final String? id;
  final String name;
  final double value;

  factory RankingItem.fromJson(Map<String, dynamic> json) => RankingItem(
    id: json['id'] as String?,
    name: json['name'] as String,
    value: (json['value'] as num).toDouble(),
  );
}

class RankingChart {
  RankingChart({
    required this.from,
    required this.to,
    required this.groupBy,
    required this.items,
  });

  final String from;
  final String to;
  final String groupBy;
  final List<RankingItem> items;

  factory RankingChart.fromJson(Map<String, dynamic> json) => RankingChart(
    from: json['from'] as String,
    to: json['to'] as String,
    groupBy: json['groupBy'] as String,
    items: (json['items'] as List<dynamic>)
        .map((e) => RankingItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 'actif' | 'epuise' — voir apps/api/nestjs/src/stock/stock-lots.ts.
class StockLot {
  StockLot({
    required this.code,
    required this.productId,
    required this.productName,
    required this.receivedAt,
    required this.receivedQuantity,
    required this.consumedQuantity,
    required this.lossQuantity,
    required this.remainingQuantity,
    required this.status,
  });

  final String code;
  final String productId;
  final String productName;
  final DateTime receivedAt;
  final double receivedQuantity;
  final double consumedQuantity;
  final double lossQuantity;
  final double remainingQuantity;
  final String status;

  bool get isActive => status == 'actif';

  factory StockLot.fromJson(Map<String, dynamic> json) => StockLot(
    code: json['code'] as String,
    productId: json['productId'] as String,
    productName: json['productName'] as String,
    receivedAt: DateTime.parse(json['receivedAt'] as String),
    receivedQuantity: (json['receivedQuantity'] as num).toDouble(),
    consumedQuantity: (json['consumedQuantity'] as num).toDouble(),
    lossQuantity: (json['lossQuantity'] as num).toDouble(),
    remainingQuantity: (json['remainingQuantity'] as num).toDouble(),
    status: json['status'] as String,
  );
}

class StockLotsChart {
  StockLotsChart({
    required this.productIds,
    required this.productNames,
    required this.activeLots,
    required this.historyLots,
    required this.totalActiveUnits,
  });

  final List<String> productIds;
  final List<String> productNames;
  final List<StockLot> activeLots;
  final List<StockLot> historyLots;
  final double totalActiveUnits;

  factory StockLotsChart.fromJson(Map<String, dynamic> json) => StockLotsChart(
    productIds: (json['productIds'] as List<dynamic>).cast<String>(),
    productNames: (json['productNames'] as List<dynamic>).cast<String>(),
    activeLots: (json['activeLots'] as List<dynamic>)
        .map((e) => StockLot.fromJson(e as Map<String, dynamic>))
        .toList(),
    historyLots: (json['historyLots'] as List<dynamic>)
        .map((e) => StockLot.fromJson(e as Map<String, dynamic>))
        .toList(),
    totalActiveUnits: (json['totalActiveUnits'] as num).toDouble(),
  );
}

/// "Top des produits épuisés" (sous-module Stock) — voir ChartsService.outOfStockProducts.
class OutOfStockProduct {
  OutOfStockProduct({
    required this.id,
    required this.name,
    required this.categoryName,
    required this.stockQuantity,
  });

  final String id;
  final String name;
  final String categoryName;
  final double stockQuantity;

  factory OutOfStockProduct.fromJson(Map<String, dynamic> json) =>
      OutOfStockProduct(
        id: json['id'] as String,
        name: json['name'] as String,
        categoryName: json['categoryName'] as String,
        stockQuantity: (json['stockQuantity'] as num).toDouble(),
      );
}

/// Listing "Stock actif" (module Stock) — un produit = une ligne, agrégée sur
/// ses seuls lots FIFO actifs — voir `ChartsService.activeStockListing`.
class ActiveStockListingRow {
  ActiveStockListingRow({
    required this.productId,
    required this.productName,
    required this.receivedQuantity,
    required this.purchaseValue,
    required this.receivedRevenue,
    required this.consumedQuantity,
    required this.consumedRevenue,
    required this.lossQuantity,
    required this.lossRevenue,
    required this.remainingQuantity,
    required this.remainingRevenue,
    required this.profit,
  });

  final String productId;
  final String productName;
  final double receivedQuantity;
  final double purchaseValue;
  final double receivedRevenue;
  final double consumedQuantity;
  final double consumedRevenue;
  final double lossQuantity;
  final double lossRevenue;
  final double remainingQuantity;
  final double remainingRevenue;
  final double profit;

  factory ActiveStockListingRow.fromJson(Map<String, dynamic> json) =>
      ActiveStockListingRow(
        productId: json['productId'] as String,
        productName: json['productName'] as String,
        receivedQuantity: (json['receivedQuantity'] as num).toDouble(),
        purchaseValue: (json['purchaseValue'] as num).toDouble(),
        receivedRevenue: (json['receivedRevenue'] as num).toDouble(),
        consumedQuantity: (json['consumedQuantity'] as num).toDouble(),
        consumedRevenue: (json['consumedRevenue'] as num).toDouble(),
        lossQuantity: (json['lossQuantity'] as num).toDouble(),
        lossRevenue: (json['lossRevenue'] as num).toDouble(),
        remainingQuantity: (json['remainingQuantity'] as num).toDouble(),
        remainingRevenue: (json['remainingRevenue'] as num).toDouble(),
        profit: (json['profit'] as num).toDouble(),
      );
}
