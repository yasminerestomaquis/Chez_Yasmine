import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import 'order_detail_page.dart';
import 'tables_models.dart';
import 'tables_repository.dart';

class FloorPlanPage extends StatefulWidget {
  const FloorPlanPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<FloorPlanPage> createState() => _FloorPlanPageState();
}

const _kAllFilter = 'all';

class _FloorPlanPageState extends State<FloorPlanPage> {
  late final TablesRepository _repository = TablesRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<List<RestaurantTable>> _future = _repository.listTables();
  String _filter = _kAllFilter;

  void _reload() => setState(() => _future = _repository.listTables());

  Future<void> _onTableTap(RestaurantTable table) async {
    try {
      if (table.status == 'free') {
        await _repository.openTable(table.id);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailPage(
            repository: _repository,
            establishmentId: widget.establishmentId,
            tableId: table.id,
          ),
        ),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // Regroupe le statut brut (chaîne libre côté API) dans l'un des 3 filtres
  // affichés — même logique que _statusLabel, seulement pour le filtrage.
  String _statusBucket(String status) {
    switch (status) {
      case 'free':
        return 'free';
      case 'billing':
        return 'billing';
      default:
        return 'occupied';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'free':
        return AppColors.greenLight;
      case 'billing':
        return AppColors.alertLight;
      default:
        return AppColors.orangeLight;
    }
  }

  Color _statusDotColor(String status) {
    switch (status) {
      case 'free':
        return AppColors.green;
      case 'billing':
        return AppColors.alert;
      default:
        return AppColors.orange;
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
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : '${snapshot.error}';
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }

          final allTables = snapshot.data!;
          if (allTables.isEmpty) {
            return const Center(child: Text('Aucune table configurée.'));
          }

          final tables = _filter == _kAllFilter
              ? allTables
              : allTables
                    .where((t) => _statusBucket(t.status) == _filter)
                    .toList();

          final zones = <String, List<RestaurantTable>>{};
          for (final table in tables) {
            zones.putIfAbsent(table.zone ?? 'Sans zone', () => []).add(table);
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Toutes', _kAllFilter),
                      const SizedBox(width: 8),
                      _filterChip('Libres', 'free'),
                      const SizedBox(width: 8),
                      _filterChip('Occupées', 'occupied'),
                      const SizedBox(width: 8),
                      _filterChip('À encaisser', 'billing'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (tables.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Aucune table dans ce filtre.')),
                  ),
                for (final entry in zones.entries) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 130,
                          mainAxisExtent: 90,
                        ),
                    itemCount: entry.value.length,
                    itemBuilder: (context, index) {
                      final table = entry.value[index];
                      return Card(
                        color: _statusColor(table.status),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _onTableTap(table),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  table.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _statusDotColor(table.status),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _statusLabel(table.status),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
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

  Widget _filterChip(String label, String value) {
    // Le statut « occupée » regroupe tout statut hors 'free'/'billing' côté
    // API (raw string) — filtre purement client, sur des données déjà
    // récupérées, comme recommandé par "Nouvel interface.docx".
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.green,
      labelStyle: TextStyle(
        color: selected ? AppColors.white : AppColors.textPrimary,
      ),
    );
  }
}
