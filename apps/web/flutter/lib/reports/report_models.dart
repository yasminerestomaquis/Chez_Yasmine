class TopProduct {
  TopProduct({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.revenue,
    required this.cost,
    required this.profit,
  });

  final String productId;
  final String name;
  final double quantity;
  final double revenue;
  final double cost;
  final double profit;

  factory TopProduct.fromJson(Map<String, dynamic> json) => TopProduct(
        productId: json['productId'] as String,
        name: json['name'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        revenue: (json['revenue'] as num).toDouble(),
        cost: (json['cost'] as num).toDouble(),
        profit: (json['profit'] as num).toDouble(),
      );
}

class ServerPerformance {
  ServerPerformance({required this.userId, required this.name, required this.total, required this.salesCount});

  final String userId;
  final String name;
  final double total;
  final int salesCount;

  factory ServerPerformance.fromJson(Map<String, dynamic> json) => ServerPerformance(
        userId: json['userId'] as String,
        name: json['name'] as String,
        total: (json['total'] as num).toDouble(),
        salesCount: json['salesCount'] as int,
      );
}

/// Correspond à `ReportsService.paymentCategoryBreakdown` — voir
/// `docs/api/reports.md`. Boissons = Bières/Vins/Sucreries
/// (`Category.hasCasePricing`), Plats = Poulets/Poissons/Plats africains
/// (`Category.hasVariablePricing`).
class PaymentCategoryBreakdown {
  PaymentCategoryBreakdown({
    required this.totalRevenue,
    required this.cashRevenue,
    required this.mobileMoneyRevenue,
    required this.boissonsRevenue,
    required this.platsRevenue,
    required this.boissonsCash,
    required this.boissonsMobileMoney,
    required this.platsCash,
    required this.platsMobileMoney,
  });

  final double totalRevenue;
  final double cashRevenue;
  final double mobileMoneyRevenue;
  final double boissonsRevenue;
  final double platsRevenue;
  final double boissonsCash;
  final double boissonsMobileMoney;
  final double platsCash;
  final double platsMobileMoney;

  factory PaymentCategoryBreakdown.fromJson(Map<String, dynamic> json) => PaymentCategoryBreakdown(
        totalRevenue: (json['totalRevenue'] as num).toDouble(),
        cashRevenue: (json['cashRevenue'] as num).toDouble(),
        mobileMoneyRevenue: (json['mobileMoneyRevenue'] as num).toDouble(),
        boissonsRevenue: (json['boissonsRevenue'] as num).toDouble(),
        platsRevenue: (json['platsRevenue'] as num).toDouble(),
        boissonsCash: (json['boissonsCash'] as num).toDouble(),
        boissonsMobileMoney: (json['boissonsMobileMoney'] as num).toDouble(),
        platsCash: (json['platsCash'] as num).toDouble(),
        platsMobileMoney: (json['platsMobileMoney'] as num).toDouble(),
      );
}

class ReportSummary {
  ReportSummary({
    required this.from,
    required this.to,
    required this.revenue,
    required this.salesCount,
    required this.discountTotal,
    required this.cogs,
    required this.grossMargin,
    required this.expenses,
    required this.losses,
    required this.netProfit,
    required this.receivables,
    required this.lowStockCount,
    required this.topProducts,
    required this.productProfitability,
    required this.serverPerformance,
  });

  final DateTime from;
  final DateTime to;
  final double revenue;
  final int salesCount;
  final double discountTotal;
  final double cogs;
  final double grossMargin;
  final double expenses;
  final double losses;
  final double netProfit;
  final double receivables;
  final int lowStockCount;
  final List<TopProduct> topProducts;
  final List<TopProduct> productProfitability;
  final List<ServerPerformance> serverPerformance;

  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
        from: DateTime.parse(json['from'] as String),
        to: DateTime.parse(json['to'] as String),
        revenue: (json['revenue'] as num).toDouble(),
        salesCount: json['salesCount'] as int,
        discountTotal: (json['discountTotal'] as num).toDouble(),
        cogs: (json['cogs'] as num).toDouble(),
        grossMargin: (json['grossMargin'] as num).toDouble(),
        expenses: (json['expenses'] as num).toDouble(),
        losses: (json['losses'] as num).toDouble(),
        netProfit: (json['netProfit'] as num).toDouble(),
        receivables: (json['receivables'] as num).toDouble(),
        lowStockCount: json['lowStockCount'] as int,
        topProducts: (json['topProducts'] as List<dynamic>)
            .map((e) => TopProduct.fromJson(e as Map<String, dynamic>))
            .toList(),
        productProfitability: (json['productProfitability'] as List<dynamic>)
            .map((e) => TopProduct.fromJson(e as Map<String, dynamic>))
            .toList(),
        serverPerformance: (json['serverPerformance'] as List<dynamic>)
            .map((e) => ServerPerformance.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
