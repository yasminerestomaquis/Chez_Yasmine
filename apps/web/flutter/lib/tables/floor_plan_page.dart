import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'order_detail_page.dart';
import 'tables_models.dart';
import 'tables_repository.dart';

class FloorPlanPage extends StatefulWidget {
  const FloorPlanPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<FloorPlanPage> createState() => _FloorPlanPageState();
}

class _FloorPlanPageState extends State<FloorPlanPage> {
  late final TablesRepository _repository = TablesRepository(ApiClient(), widget.establishmentId);
  late Future<List<RestaurantTable>> _future = _repository.listTables();

  void _reload() => setState(() => _future = _repository.listTables());

  Future<void> _onTableTap(RestaurantTable table) async {
    try {
      if (table.status == 'free') {
        await _repository.openTable(table.id);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderDetailPage(repository: _repository, establishmentId: widget.establishmentId, tableId: table.id)),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'free':
        return Colors.green.shade100;
      case 'billing':
        return Colors.red.shade100;
      default:
        return Colors.orange.shade100;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'free':
        return 'Libre';
      case 'billing':
        return 'À encaisser';
      default:
        return 'Occupée';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan de salle')),
      body: FutureBuilder<List<RestaurantTable>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [Text(message), const SizedBox(height: 12), OutlinedButton(onPressed: _reload, child: const Text('Réessayer'))],
              ),
            );
          }

          final tables = snapshot.data!;
          if (tables.isEmpty) {
            return const Center(child: Text('Aucune table configurée.'));
          }

          final zones = <String, List<RestaurantTable>>{};
          for (final table in tables) {
            zones.putIfAbsent(table.zone ?? 'Sans zone', () => []).add(table);
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final entry in zones.entries) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisExtent: 90),
                    itemCount: entry.value.length,
                    itemBuilder: (context, index) {
                      final table = entry.value[index];
                      return Card(
                        color: _statusColor(table.status),
                        child: InkWell(
                          onTap: () => _onTableTap(table),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(table.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(_statusLabel(table.status), style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
