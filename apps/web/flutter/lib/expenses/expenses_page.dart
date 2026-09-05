import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import 'expense_models.dart';
import 'expenses_repository.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  late final ExpensesRepository _repository = ExpensesRepository(ApiClient(), widget.establishmentId);
  late Future<List<Expense>> _future = _repository.listExpenses();

  void _reload() => setState(() => _future = _repository.listExpenses());

  Future<void> _addExpense() async {
    final labelController = TextEditingController();
    final categoryController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle dépense'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Libellé *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Libellé requis' : null,
              ),
              TextField(controller: categoryController, decoration: const InputDecoration(labelText: 'Catégorie (optionnel)')),
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
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optionnel)')),
            ],
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
      ),
    );
    if (saved != true) return;
    try {
      await _repository.createExpense(
        label: labelController.text.trim(),
        category: categoryController.text.trim(),
        amount: double.parse(amountController.text.trim().replaceAll(',', '.')),
        note: noteController.text.trim(),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // Not queued offline (unlike sales/stock movements, Phase 9) — expenses
      // aren't part of the sync architecture yet. Just report the failure.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'enregistrer la dépense.")));
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
      body: FutureBuilder<List<Expense>>(
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
                child: Text('Total : ${total.toStringAsFixed(0)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final expense in expenses)
                      ListTile(
                        title: Text(expense.label),
                        subtitle: Text(
                          '${expense.category != null && expense.category!.isNotEmpty ? '${expense.category} — ' : ''}${dateFormat.format(expense.expenseDate.toLocal())}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${expense.amount.toStringAsFixed(0)} FCFA'),
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
      floatingActionButton: FloatingActionButton(onPressed: _addExpense, child: const Icon(Icons.add)),
    );
  }
}
