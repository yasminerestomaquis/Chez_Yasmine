import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import '../sync/sync_status_bar.dart';
import 'expense_models.dart';
import 'expenses_repository.dart';

/// Valeur spéciale du menu déroulant déclenchant la saisie libre — voir
/// `kPredefinedExpenseCategories` : la liste n'est pas fermée.
const _otherCategoryValue = '__other__';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  late final ExpensesRepository _repository = ExpensesRepository(ApiClient(), widget.establishmentId);
  late final SyncQueueService _syncQueue = SyncQueueService(ApiClient(), widget.establishmentId);
  late Future<List<Expense>> _future = _repository.listExpenses();

  void _reload() => setState(() => _future = _repository.listExpenses());

  Future<void> _addExpense() async {
    final labelController = TextEditingController();
    final customCategoryController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final marketNumberController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedCategory;
    var periodicity = ExpensePeriodicity.oneOff;
    var expenseDate = DateTime.now();
    final dateFieldFormat = DateFormat('dd/MM/yyyy');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Nouvelle dépense'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: labelController,
                      decoration: const InputDecoration(labelText: 'Libellé *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Libellé requis' : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: expenseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            helpText: 'Date de la dépense',
                          );
                          if (picked != null) setDialogState(() => expenseDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text('Date : ${dateFieldFormat.format(expenseDate)}'),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(labelText: 'Nature de la dépense'),
                      items: [
                        for (final category in kPredefinedExpenseCategories)
                          DropdownMenuItem(value: category, child: Text(category)),
                        const DropdownMenuItem(value: _otherCategoryValue, child: Text('Autre…')),
                      ],
                      onChanged: (value) async {
                        setDialogState(() => selectedCategory = value);
                        if (value == 'Marché' && marketNumberController.text.isEmpty) {
                          try {
                            final suggestion = await _repository.nextMarketNumber();
                            marketNumberController.text = '$suggestion';
                            setDialogState(() {});
                          } catch (_) {
                            // Simple suggestion de convenance — jamais bloquant, saisie manuelle toujours possible.
                          }
                        }
                      },
                    ),
                    if (selectedCategory == _otherCategoryValue)
                      TextField(
                        controller: customCategoryController,
                        decoration: const InputDecoration(labelText: 'Préciser la nature'),
                      ),
                    if (selectedCategory == 'Marché')
                      TextFormField(
                        controller: marketNumberController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'N° de marché'),
                      ),
                    TextFormField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Montant *'),
                      validator: (v) {
                        final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                        if (value == null || value <= 0) return 'Montant invalide';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<ExpensePeriodicity>(
                        segments: const [
                          ButtonSegment(value: ExpensePeriodicity.oneOff, label: Text('Ponctuelle')),
                          ButtonSegment(value: ExpensePeriodicity.recurring, label: Text('Récurrente')),
                        ],
                        selected: {periodicity},
                        onSelectionChanged: (selection) => setDialogState(() => periodicity = selection.first),
                      ),
                    ),
                    TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optionnel)')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) Navigator.of(context).pop(true);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true) return;

    final category = selectedCategory == _otherCategoryValue
        ? customCategoryController.text.trim()
        : selectedCategory;
    final expenseId = const Uuid().v4();
    final label = labelController.text.trim();
    final amount = double.parse(amountController.text.trim().replaceAll(',', '.'));
    final note = noteController.text.trim();
    final marketNumber = category == 'Marché' ? int.tryParse(marketNumberController.text.trim()) : null;

    try {
      await _repository.createExpense(
        id: expenseId,
        label: label,
        category: category?.isEmpty == true ? null : category,
        amount: amount,
        periodicity: periodicity,
        note: note,
        expenseDate: expenseDate,
        marketNumber: marketNumber,
      );
      _reload();
    } on ApiException catch (e) {
      // Un vrai rejet métier (validation...) — rejouer plus tard n'aiderait pas.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // Aucune réponse HTTP reçue : hors ligne — file d'attente locale, comme
      // pour les ventes et les mouvements de stock (voir pos_page.dart).
      await _syncQueue.enqueue(PendingOperation(
        id: expenseId,
        entityType: 'expense',
        deviceId: await getDeviceId(),
        payload: {
          'label': label,
          if (category != null && category.isNotEmpty) 'category': category,
          'amount': amount,
          'periodicity': periodicity.value,
          if (note.isNotEmpty) 'note': note,
          'expenseDate':
              '${expenseDate.year.toString().padLeft(4, '0')}-${expenseDate.month.toString().padLeft(2, '0')}-${expenseDate.day.toString().padLeft(2, '0')}',
          'marketNumber': ?marketNumber,
        },
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hors ligne : dépense enregistrée localement, elle sera synchronisée automatiquement.')),
      );
    }
  }

  Future<void> _deleteExpense(Expense expense) async {
    try {
      await _repository.deleteExpense(expense.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de supprimer la dépense.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      body: Column(
        children: [
          SyncStatusBar(syncQueue: _syncQueue),
          Expanded(
            child: FutureBuilder<List<Expense>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
                  return Center(child: Text(message));
                }
                final expenses = snapshot.data!;
                if (expenses.isEmpty) {
                  return const Center(child: Text('Aucune dépense — ajoutez-en une avec le bouton +'));
                }
                final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);
                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Text('Total : ${formatAmount(total)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final expense in expenses)
                            ListTile(
                              title: Text(expense.label),
                              subtitle: Text(
                                '${expense.category != null && expense.category!.isNotEmpty ? '${expense.category}' : ''}'
                                '${expense.marketNumber != null ? ' n°${expense.marketNumber}' : ''}'
                                '${expense.category != null && expense.category!.isNotEmpty ? ' — ' : ''}'
                                '${dateFormat.format(expense.expenseDate.toLocal())} · ${expense.periodicity.label}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${formatAmount(expense.amount)} FCFA'),
                                  IconButton(
                                    tooltip: 'Supprimer',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _deleteExpense(expense),
                                  ),
                                ],
                              ),
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
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addExpense, child: const Icon(Icons.add)),
    );
  }
}
