import '../reports/report_models.dart';

const frenchWeekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
const frenchMonths = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String frenchDate(DateTime date) {
  final weekday = frenchWeekdays[date.weekday - 1];
  final month = frenchMonths[date.month - 1];
  final weekdayCapitalized = weekday[0].toUpperCase() + weekday.substring(1);
  return '$weekdayCapitalized ${date.day} $month';
}

/// Libellé du filtre "Date" de l'accueil (sélection multiple, demande
/// utilisateur du 2026-09-20) : "Aujourd'hui", le jour choisi, ou le nombre
/// de jours cochés.
String dateFilterLabel(Set<DateTime> dates, DateTime today) {
  if (dates.length == 1) {
    final only = dates.first;
    return only == today ? "Aujourd'hui" : frenchDate(only);
  }
  return '${dates.length} jours sélectionnés';
}

/// Complément des libellés de cartes ("Ventes aujourd'hui" -> "Ventes du
/// lundi 8 septembre" / "Ventes sur 3 jours") pour qu'ils restent exacts
/// quelle que soit la sélection.
String periodPhrase(Set<DateTime> dates, DateTime today) {
  if (dates.length == 1) {
    final only = dates.first;
    if (only == today) return "aujourd'hui";
    final weekday = frenchWeekdays[only.weekday - 1];
    final month = frenchMonths[only.month - 1];
    return 'du $weekday ${only.day} $month';
  }
  return 'sur ${dates.length} jours';
}

/// Somme des ventilations Espèces/Mobile Money × Boissons sans Gbêlê/Gbêlê/
/// Plats de chaque date sélectionnée — le serveur ne sait résoudre qu'un
/// intervalle continu, donc une sélection de dates non contiguës se calcule
/// jour par jour.
PaymentCategoryBreakdown mergeBreakdowns(List<PaymentCategoryBreakdown> items) {
  double sum(double Function(PaymentCategoryBreakdown) pick) =>
      items.fold(0.0, (total, b) => total + pick(b));
  return PaymentCategoryBreakdown(
    totalRevenue: sum((b) => b.totalRevenue),
    cashRevenue: sum((b) => b.cashRevenue),
    mobileMoneyRevenue: sum((b) => b.mobileMoneyRevenue),
    boissonsSansGbeleRevenue: sum((b) => b.boissonsSansGbeleRevenue),
    gbeleRevenue: sum((b) => b.gbeleRevenue),
    platsRevenue: sum((b) => b.platsRevenue),
    boissonsSansGbeleCash: sum((b) => b.boissonsSansGbeleCash),
    boissonsSansGbeleMobileMoney: sum((b) => b.boissonsSansGbeleMobileMoney),
    gbeleCash: sum((b) => b.gbeleCash),
    gbeleMobileMoney: sum((b) => b.gbeleMobileMoney),
    platsCash: sum((b) => b.platsCash),
    platsMobileMoney: sum((b) => b.platsMobileMoney),
  );
}

/// Nombre de commandes cumulé sur les dates sélectionnées, et alertes stock
/// (état courant du stock, indépendant de la date : jamais additionné).
({int salesCount, int lowStockCount}) mergeSummaries(List<ReportSummary> items) => (
      salesCount: items.fold(0, (total, s) => total + s.salesCount),
      lowStockCount: items.fold(0, (max, s) => s.lowStockCount > max ? s.lowStockCount : max),
    );
