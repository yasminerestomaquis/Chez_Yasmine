import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../common/formatting.dart';
import 'loss_models.dart';
import 'losses_repository.dart';
import 'record_loss_dialog.dart';

class LossesPage extends StatefulWidget {
  const LossesPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<LossesPage> createState() => _LossesPageState();
}

class _LossesPageState extends State<LossesPage> {
  late final LossesRepository _repository = LossesRepository(ApiClient(), widget.establishmentId);
  late final CatalogRepository _catalog = CatalogRepository(ApiClient(), widget.establishmentId);
  late Future<List<Loss>> _future = _repository.listLosses();

  void _reload() => setState(() => _future = _repository.listLosses());

  Future<void> _openRecordDialog() async {
    final recorded = await showRecordLossDialog(context, repository: _repository, catalogRepository: _catalog);
    if (recorded == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Pertes')),
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
          final losses = snapshot.data!;
          if (losses.isEmpty) {
            return const Center(child: Text('Aucune perte enregistrée — utilisez le bouton +'));
          }
          final totalValue = losses.fold<double>(0, (sum, l) => sum + l.estimatedValue);
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text('Valeur estimée totale : ${formatAmount(totalValue)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final loss in losses)
                      ListTile(
                        title: Text('${loss.productName} — ${loss.quantity.toStringAsFixed(0)}'),
                        subtitle: Text(
                          '${loss.reason != null && loss.reason!.isNotEmpty ? '${loss.reason} — ' : ''}${dateFormat.format(loss.createdAt.toLocal())}',
                        ),
                        trailing: Text('${formatAmount(loss.estimatedValue)} FCFA'),
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
