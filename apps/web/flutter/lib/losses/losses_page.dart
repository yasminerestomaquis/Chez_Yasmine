import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../common/formatting.dart';
import 'edit_loss_dialog.dart';
import 'loss_filter.dart';
import 'loss_models.dart';
import 'losses_repository.dart';
import 'record_loss_dialog.dart';

class LossesPage extends StatefulWidget {
  const LossesPage({super.key, required this.establishmentId, required this.roleName});

  final String establishmentId;
  final String roleName;

  @override
  State<LossesPage> createState() => _LossesPageState();
}

class _LossesPageState extends State<LossesPage> {
  late final LossesRepository _repository = LossesRepository(ApiClient(), widget.establishmentId);
  late final CatalogRepository _catalog = CatalogRepository(ApiClient(), widget.establishmentId);
  late Future<List<Loss>> _future = _repository.listLosses();

  /// Jour dont on liste les pertes (demande utilisateur du 2026-09-20) —
  /// aujourd'hui par défaut, `null` = toutes les dates.
  DateTime? _day = _today();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _canEdit => canEditLosses(widget.roleName);

  void _reload() => setState(() => _future = _repository.listLosses());

  Future<void> _openRecordDialog() async {
    final recorded = await showRecordLossDialog(context, repository: _repository, catalogRepository: _catalog);
    if (recorded == true) _reload();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? _today(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Date des pertes à afficher',
    );
    if (picked == null) return;
    setState(() => _day = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _edit(Loss loss) async {
    final edited = await showEditLossDialog(
      context,
      repository: _repository,
      catalogRepository: _catalog,
      loss: loss,
    );
    if (edited == true) _reload();
  }

  Future<void> _delete(Loss loss) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette perte ?'),
        content: Text(
          '${loss.productName} — ${_formatQuantity(loss.quantity)} sera supprimée et cette quantité sera remise en stock.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteLoss(loss.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur réseau — perte non supprimée')));
    }
  }

  String _formatQuantity(double quantity) =>
      quantity == quantity.roundToDouble() ? quantity.toStringAsFixed(0) : '$quantity';

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final dayFormat = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pertes'),
        actions: [
          IconButton(tooltip: 'Changer la date', icon: const Icon(Icons.calendar_month_outlined), onPressed: _pickDay),
        ],
      ),
      body: FutureBuilder<List<Loss>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }
          final all = snapshot.data!;
          final losses = lossesOnDay(all, _day);
          final totals = lossTotals(losses);
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          _day == null ? 'Toutes les dates' : 'Pertes du ${dayFormat.format(_day!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_day != null)
                          TextButton(
                            onPressed: () => setState(() => _day = null),
                            child: const Text('Toutes les dates'),
                          ),
                      ],
                    ),
                    Text(
                      'Nombre total de pertes : ${totals.count}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Montant total des pertes : ${formatAmount(totals.totalValue)} FCFA',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: losses.isEmpty
                    ? Center(
                        child: Text(
                          all.isEmpty
                              ? 'Aucune perte enregistrée — utilisez le bouton +'
                              : 'Aucune perte enregistrée pour cette date.',
                        ),
                      )
                    : ListView(
                        children: [
                          for (final loss in losses)
                            ListTile(
                              title: Text('${loss.productName} — ${_formatQuantity(loss.quantity)}'),
                              subtitle: Text(
                                '${loss.reason != null && loss.reason!.isNotEmpty ? '${loss.reason} — ' : ''}'
                                '${dateFormat.format(loss.createdAt.toLocal())}\n'
                                'Par ${loss.createdByName ?? 'auteur inconnu'}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${formatAmount(loss.estimatedValue)} FCFA'),
                                  if (_canEdit) ...[
                                    IconButton(
                                      tooltip: 'Modifier la perte',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _edit(loss),
                                    ),
                                    IconButton(
                                      tooltip: 'Supprimer la perte',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(loss),
                                    ),
                                  ],
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
      floatingActionButton: FloatingActionButton(onPressed: _openRecordDialog, child: const Icon(Icons.add)),
    );
  }
}
