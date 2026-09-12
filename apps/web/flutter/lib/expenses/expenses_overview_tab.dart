import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import '../theme/app_theme.dart';
import 'expense_category_donut_chart.dart';
import 'expense_summary_models.dart';
import 'expenses_repository.dart';

// ignore: unused_element
const _weekdayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

DateTime _mondayOf(DateTime date) {
  final weekdayIndex = (date.weekday - 1) % 7; // lundi = 0
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: weekdayIndex));
}

/// Tableau de bord analytique des dépenses (demande utilisateur du
/// 2026-09-12) : filtre Année/Mois/Semaine avec navigation précédent/suivant,
/// 4 KPI, donut de répartition par nature, dernières dépenses.
class ExpensesOverviewTab extends StatefulWidget {
  const ExpensesOverviewTab({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ExpensesOverviewTab> createState() => _ExpensesOverviewTabState();
}

class _ExpensesOverviewTabState extends State<ExpensesOverviewTab> {
  late final ExpensesRepository _repository = ExpensesRepository(
    ApiClient(),
    widget.establishmentId,
  );

  String _period = 'month';
  var _year = DateTime.now().year;
  var _month = DateTime.now().month;
  var _weekOf = _mondayOf(DateTime.now());

  late Future<ExpenseSummary> _future = _load();

  Future<ExpenseSummary> _load() {
    return _repository.getSummary(
      period: _period,
      year: _year,
      month: _period == 'month' ? _month : null,
      weekOf: _period == 'week' ? _weekOf.toIso8601String().slice0to10() : null,
    );
  }

  void _reload() {
    final future = _load();
    future.ignore();
    setState(() => _future = future);
  }

  void _changePeriod(String period) {
    _period = period;
    _reload();
  }

  void _shift(int direction) {
    switch (_period) {
      case 'year':
        _year += direction;
        break;
      case 'month':
        final next = DateTime(_year, _month + direction, 1);
        _year = next.year;
        _month = next.month;
        break;
      case 'week':
        _weekOf = _weekOf.add(Duration(days: 7 * direction));
        break;
    }
    _reload();
  }

  String get _periodLabel {
    switch (_period) {
      case 'year':
        return '$_year';
      case 'month':
        const months = [
          'Janvier',
          'Février',
          'Mars',
          'Avril',
          'Mai',
          'Juin',
          'Juillet',
          'Août',
          'Septembre',
          'Octobre',
          'Novembre',
          'Décembre',
        ];
        return '${months[_month - 1]} $_year';
      default:
        final sunday = _weekOf.add(const Duration(days: 6));
        final fmt = DateFormat('dd/MM/yyyy');
        return 'Du ${fmt.format(_weekOf)} au ${fmt.format(sunday)}';
    }
  }

  Widget _kpiCard(
    String label,
    double value, {
    double? changePercent,
    Color color = AppColors.green,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatAmount(value)} F',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (changePercent != null) ...[
              const SizedBox(height: 2),
              Text(
                '${changePercent >= 0 ? '↑ +' : '↓ '}${changePercent.toStringAsFixed(1)} % vs période précédente',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: changePercent >= 0 ? AppColors.green : AppColors.alert,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'year', label: Text('Année')),
              ButtonSegment(value: 'month', label: Text('Mois')),
              ButtonSegment(value: 'week', label: Text('Semaine')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => _changePeriod(s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _periodLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<ExpenseSummary>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final message = snapshot.error is ApiException
                    ? (snapshot.error as ApiException).message
                    : '${snapshot.error}';
                return Center(child: Text(message));
              }
              final s = snapshot.data!;
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            mainAxisExtent: 92,
                          ),
                      children: [
                        _kpiCard(
                          'Total des dépenses',
                          s.totalAmount,
                          changePercent: s.changePercent,
                          color: AppColors.green,
                        ),
                        _kpiCard(
                          'Total des salaires',
                          s.totalSalaries,
                          color: AppColors.orange,
                        ),
                        _kpiCard(
                          'Achats / Marché',
                          s.totalMarket,
                          color: AppColors.green,
                        ),
                        _kpiCard(
                          'Charges fixes',
                          s.totalFixedCharges,
                          color: AppColors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'RÉPARTITION PAR NATURE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ExpenseCategoryDonutChart(items: s.byCategory),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'DERNIÈRES DÉPENSES',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              DefaultTabController.of(context).animateTo(3),
                          child: const Text('Voir tout →'),
                        ),
                      ],
                    ),
                    if (s.recent.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Aucune dépense sur cette période.'),
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final e in s.recent)
                              ListTile(
                                title: Text(e.label),
                                subtitle: Text(
                                  '${e.category ?? 'Autre'} — ${DateFormat('dd/MM/yyyy').format(e.expenseDate)}',
                                ),
                                trailing: Text(
                                  '${formatAmount(e.amount)} F',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

extension on String {
  String slice0to10() => length > 10 ? substring(0, 10) : this;
}
