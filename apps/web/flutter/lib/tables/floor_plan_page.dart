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
  String _search = '';

  void _reload() => setState(() => _future = _repository.listTables());

  // Regroupe le statut brut (chaîne libre côté API) dans l'un des filtres
  // affichés — même logique que _statusLabel, seulement pour le filtrage.
  String _statusBucket(String status) {
    switch (status) {
      case 'free':
        return 'free';
      case 'billing':
        return 'billing';
      case 'reserved':
        return 'reserved';
      default:
        return 'occupied';
    }
  }

  Future<void> _onTableTap(RestaurantTable table) async {
    switch (table.status) {
      case 'free':
        await _showFreeTableActions(table);
        return;
      case 'reserved':
        await _showReservedTableActions(table);
        return;
      default:
        await _goToOrder(table);
    }
  }

  Future<void> _goToOrder(RestaurantTable table) async {
    try {
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

  Future<void> _openTableWithGuestCount(RestaurantTable table) async {
    final guestCount = await _promptGuestCount();
    try {
      await _repository.openTable(table.id, guestCount: guestCount);
      await _goToOrder(table);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<int?> _promptGuestCount() async {
    final controller = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ouvrir la table'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nombre de convives (facultatif)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Passer'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFreeTableActions(RestaurantTable table) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  table.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.event_seat_outlined,
                color: AppColors.green,
              ),
              title: const Text('Ouvrir la table'),
              onTap: () => Navigator.of(sheetContext).pop('open'),
            ),
            ListTile(
              leading: const Icon(
                Icons.event_available_outlined,
                color: AppColors.orange,
              ),
              title: const Text('Réserver'),
              onTap: () => Navigator.of(sheetContext).pop('reserve'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'open') {
      await _openTableWithGuestCount(table);
    } else if (action == 'reserve') {
      await _showReserveDialog(table);
    }
  }

  Future<void> _showReserveDialog(RestaurantTable table) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    DateTime selected = DateTime.now().add(const Duration(hours: 1));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Réserver ${table.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du client (facultatif)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Téléphone (facultatif)',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_outlined),
                label: Text(
                  '${selected.day}/${selected.month}/${selected.year} à ${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
                ),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selected,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null) return;
                  if (!context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selected),
                  );
                  if (time == null) return;
                  setDialogState(
                    () => selected = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Réserver'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.createReservation(
        table.id,
        customerName: nameController.text.trim().isEmpty
            ? null
            : nameController.text.trim(),
        phone: phoneController.text.trim().isEmpty
            ? null
            : phoneController.text.trim(),
        reservedAt: selected,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showReservedTableActions(RestaurantTable table) async {
    final reservation = table.reservation;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    table.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (reservation != null) ...[
                    const SizedBox(height: 4),
                    if (reservation.customerName != null)
                      Text(reservation.customerName!),
                    if (reservation.phone != null)
                      Text(
                        reservation.phone!,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    Text(
                      'Réservée pour ${reservation.reservedAt.toLocal().hour.toString().padLeft(2, '0')}:${reservation.reservedAt.toLocal().minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.event_seat_outlined,
                color: AppColors.green,
              ),
              title: const Text('Client arrivé — ouvrir la table'),
              onTap: () => Navigator.of(sheetContext).pop('open'),
            ),
            ListTile(
              leading: const Icon(
                Icons.event_busy_outlined,
                color: AppColors.alert,
              ),
              title: const Text('Annuler la réservation'),
              onTap: () => Navigator.of(sheetContext).pop('cancel'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'open') {
      await _openTableWithGuestCount(table);
    } else if (action == 'cancel' && reservation != null) {
      try {
        await _repository.cancelReservation(reservation.id);
        _reload();
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _showCreateTableDialog() async {
    final nameController = TextEditingController();
    final zoneController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle table'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: zoneController,
              decoration: const InputDecoration(labelText: 'Zone (facultatif)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (created != true || nameController.text.trim().isEmpty || !mounted) {
      return;
    }
    try {
      await _repository.createTable(
        nameController.text.trim(),
        zone: zoneController.text.trim().isEmpty
            ? null
            : zoneController.text.trim(),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showEditTableDialog(RestaurantTable table) async {
    final nameController = TextEditingController(text: table.name);
    final zoneController = TextEditingController(text: table.zone ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Modifier ${table.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: zoneController,
              decoration: const InputDecoration(labelText: 'Zone (facultatif)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.alert),
            child: const Text('Supprimer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop('save'),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      if (result == 'save') {
        await _repository.updateTable(
          table.id,
          name: nameController.text.trim(),
          zone: zoneController.text.trim().isEmpty
              ? null
              : zoneController.text.trim(),
        );
      } else if (result == 'delete') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Supprimer ${table.name} ?'),
            content: const Text('Cette action est irréversible.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.alert),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        await _repository.deleteTable(table.id);
      }
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tables')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateTableDialog,
        tooltip: 'Nouvelle table',
        child: const Icon(Icons.add),
      ),
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
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Aucune table configurée.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _showCreateTableDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Créer une table'),
                  ),
                ],
              ),
            );
          }

          final searched = _search.isEmpty
              ? allTables
              : allTables
                    .where(
                      (t) =>
                          t.name.toLowerCase().contains(_search.toLowerCase()),
                    )
                    .toList();
          final tables = _filter == _kAllFilter
              ? searched
              : searched
                    .where((t) => _statusBucket(t.status) == _filter)
                    .toList();

          final counts = <String, int>{};
          for (final t in allTables) {
            counts.update(
              _statusBucket(t.status),
              (v) => v + 1,
              ifAbsent: () => 1,
            );
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
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Rechercher une table',
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Toutes (${allTables.length})', _kAllFilter),
                      const SizedBox(width: 8),
                      _filterChip('Libres (${counts['free'] ?? 0})', 'free'),
                      const SizedBox(width: 8),
                      _filterChip(
                        'Occupées (${counts['occupied'] ?? 0})',
                        'occupied',
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        'À encaisser (${counts['billing'] ?? 0})',
                        'billing',
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        'Réservées (${counts['reserved'] ?? 0})',
                        'reserved',
                      ),
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
                          mainAxisExtent: 108,
                        ),
                    itemCount: entry.value.length,
                    itemBuilder: (context, index) => _TableCard(
                      table: entry.value[index],
                      onTap: () => _onTableTap(entry.value[index]),
                      onLongPress: () =>
                          _showEditTableDialog(entry.value[index]),
                    ),
                  ),
                ],
                const SizedBox(height: 72),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, String value) {
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

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.onTap,
    required this.onLongPress,
  });

  final RestaurantTable table;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  Color get _background {
    switch (table.status) {
      case 'free':
        return AppColors.greenLight;
      case 'billing':
        return AppColors.alertLight;
      case 'reserved':
        return const Color(0xFFE6EEFB);
      default:
        return AppColors.orangeLight;
    }
  }

  Color get _accent {
    switch (table.status) {
      case 'free':
        return AppColors.green;
      case 'billing':
        return AppColors.alert;
      case 'reserved':
        return const Color(0xFF2563EB);
      default:
        return AppColors.orange;
    }
  }

  IconData get _icon {
    switch (table.status) {
      case 'reserved':
        return Icons.event_available;
      case 'billing':
        return Icons.point_of_sale;
      case 'free':
        return Icons.event_seat_outlined;
      default:
        return Icons.event_seat;
    }
  }

  String get _statusLine {
    switch (table.status) {
      case 'free':
        return 'Libre';
      case 'billing':
        return table.currentTotal != null
            ? '${table.currentTotal!.toStringAsFixed(0)} F'
            : 'À encaisser';
      case 'reserved':
        final t = table.reservation?.reservedAt.toLocal();
        return t != null
            ? 'Réservée ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
            : 'Réservée';
      default:
        if (table.guestCount != null && table.currentTotal != null) {
          return '${table.guestCount} pers. · ${table.currentTotal!.toStringAsFixed(0)} F';
        }
        if (table.guestCount != null) return '${table.guestCount} pers.';
        if (table.currentTotal != null) {
          return '${table.currentTotal!.toStringAsFixed(0)} F';
        }
        return 'Occupée';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _background,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, color: _accent, size: 26),
              const SizedBox(height: 4),
              Text(
                table.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                _statusLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: _accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
