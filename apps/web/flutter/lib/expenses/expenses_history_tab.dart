import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../common/browser_download.dart';
import '../common/formatting.dart';
import 'expense_models.dart';
import 'expense_summary_models.dart';
import 'expenses_repository.dart';

const _monthLabels = [
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

final _isoDateFormat = DateFormat('yyyy-MM-dd');

/// Historique paginé/filtré (demande utilisateur du 2026-09-12) — filtres
/// Période/Nature/Statut/Mode de paiement, export Excel respectant les
/// filtres actifs. « Toutes les périodes » par défaut : contrairement à
/// l'onglet Vue d'ensemble (toujours borné à Année/Mois/Semaine),
/// l'Historique doit pouvoir lister l'intégralité des dépenses sans filtre
/// de date imposé — la période reste un filtre optionnel parmi d'autres.
class ExpensesHistoryTab extends StatefulWidget {
  const ExpensesHistoryTab({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ExpensesHistoryTab> createState() => _ExpensesHistoryTabState();
}

class _ExpensesHistoryTabState extends State<ExpensesHistoryTab> {
  late final ExpensesRepository _repository = ExpensesRepository(
    ApiClient(),
    widget.establishmentId,
  );

  String? _period;
  int? _periodYear;
  int? _periodMonth;
  String? _periodWeekOf;
  String? _category;
  String? _status;
  String? _paymentMethod;
  var _page = 1;
  static const _pageSize = 8;

  late Future<ExpenseHistoryPage> _future = _load();

  Future<ExpenseHistoryPage> _load() {
    return _repository.listHistory(
      period: _period,
      year: _periodYear,
      month: _periodMonth,
      weekOf: _periodWeekOf,
      category: _category,
      status: _status,
      paymentMethod: _paymentMethod,
      page: _page,
      pageSize: _pageSize,
    );
  }

  void _reload() {
    final future = _load();
    future.ignore();
    setState(() => _future = future);
  }

  Future<void> _openFilters() async {
    var period = _period;
    var periodYear = _periodYear ?? DateTime.now().year;
    var periodMonth = _periodMonth ?? DateTime.now().month;
    var periodWeekOf = _periodWeekOf;
    var category = _category;
    var status = _status;
    var paymentMethod = _paymentMethod;

    final applied = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Filtrer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: period,
                  decoration: const InputDecoration(labelText: 'Période'),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Toutes les périodes'),
                    ),
                    DropdownMenuItem(value: 'year', child: Text('Année')),
                    DropdownMenuItem(value: 'month', child: Text('Mois')),
                    DropdownMenuItem(value: 'week', child: Text('Semaine')),
                  ],
                  onChanged: (v) => setDialogState(() => period = v),
                ),
                if (period == 'year' || period == 'month') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: periodYear,
                    decoration: const InputDecoration(labelText: 'Année'),
                    items: [
                      for (
                        var y = DateTime.now().year;
                        y >= DateTime.now().year - 5;
                        y--
                      )
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => periodYear = v ?? periodYear),
                  ),
                ],
                if (period == 'month') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: periodMonth,
                    decoration: const InputDecoration(labelText: 'Mois'),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(
                          value: m,
                          child: Text(_monthLabels[m - 1]),
                        ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => periodMonth = v ?? periodMonth),
                  ),
                ],
                if (period == 'week') ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: periodWeekOf != null
                            ? DateTime.parse(periodWeekOf!)
                            : DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        helpText: 'Un jour de la semaine visée',
                      );
                      if (picked != null) {
                        setDialogState(
                          () => periodWeekOf = _isoDateFormat.format(picked),
                        );
                      }
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      periodWeekOf == null
                          ? 'Choisir une semaine'
                          : 'Semaine du ${DateFormat('dd/MM/yyyy').format(DateTime.parse(periodWeekOf!))}',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Nature'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Toutes')),
                    for (final c in kPredefinedExpenseCategories)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setDialogState(() => category = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Statut'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous')),
                    for (final s in ExpenseStatus.values)
                      DropdownMenuItem(value: s.value, child: Text(s.label)),
                  ],
                  onChanged: (v) => setDialogState(() => status = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Mode de paiement',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tous')),
                    for (final m in ExpensePaymentMethod.values)
                      DropdownMenuItem(value: m.value, child: Text(m.label)),
                  ],
                  onChanged: (v) => setDialogState(() => paymentMethod = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              // Bloque l'application tant que "Semaine" est choisi sans
              // qu'une semaine ait été réellement sélectionnée — sans cette
              // garde, `_periodWeekOf` resterait `null` malgré
              // `period == 'week'`, envoyant un filtre de période
              // incohérent au serveur.
              onPressed: (period == 'week' && periodWeekOf == null)
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
    if (applied != true) return;
    setState(() {
      _period = period;
      _periodYear = (period == 'year' || period == 'month') ? periodYear : null;
      _periodMonth = period == 'month' ? periodMonth : null;
      _periodWeekOf = period == 'week' ? periodWeekOf : null;
      _category = category;
      _status = status;
      _paymentMethod = paymentMethod;
      _page = 1;
    });
    _reload();
  }

  Future<void> _export() async {
    try {
      final result = await _repository.exportHistoryExcel(
        period: _period,
        year: _periodYear,
        month: _periodMonth,
        weekOf: _periodWeekOf,
        category: _category,
        status: _status,
        paymentMethod: _paymentMethod,
      );
      downloadBytes(
        result.bytes,
        result.filename ?? 'Historique depenses.xlsx',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _openFilters,
                icon: const Icon(Icons.filter_list),
                label: const Text('Filtrer'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exporter Excel'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<ExpenseHistoryPage>(
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
              final page = snapshot.data!;
              if (page.items.isEmpty) {
                return const Center(
                  child: Text('Aucune dépense pour ce filtre.'),
                );
              }
              final lastPage = (page.total / page.pageSize).ceil().clamp(
                1,
                1 << 30,
              );
              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('N°')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Libellé')),
                          DataColumn(label: Text('Nature')),
                          DataColumn(label: Text('Montant'), numeric: true),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Mode de paiement')),
                          DataColumn(label: Text('Statut')),
                        ],
                        rows: [
                          for (var i = 0; i < page.items.length; i++)
                            DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    '${(page.page - 1) * page.pageSize + i + 1}',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    dateFormat.format(
                                      page.items[i].expenseDate,
                                    ),
                                  ),
                                ),
                                DataCell(Text(page.items[i].label)),
                                DataCell(
                                  Text(page.items[i].category ?? 'Autre'),
                                ),
                                DataCell(
                                  Text(
                                    '${formatAmount(page.items[i].amount)} F',
                                  ),
                                ),
                                DataCell(Text(page.items[i].periodicity.label)),
                                DataCell(
                                  Text(page.items[i].paymentMethod.label),
                                ),
                                DataCell(Text(page.items[i].status.label)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Affichage de ${(page.page - 1) * page.pageSize + 1} à '
                          '${((page.page - 1) * page.pageSize + page.items.length)} sur ${page.total} enregistrements',
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: page.page > 1
                              ? () {
                                  setState(() => _page--);
                                  _reload();
                                }
                              : null,
                        ),
                        Text('${page.page} / $lastPage'),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: page.page < lastPage
                              ? () {
                                  setState(() => _page++);
                                  _reload();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
