import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../cash/cash_page.dart';
import '../catalog/catalog_page.dart';
import '../charts/graphiques_page.dart';
import '../common/formatting.dart';
import '../customers/customers_page.dart';
import '../expenses/expenses_page.dart';
import '../losses/losses_page.dart';
import '../notifications/notifications_page.dart';
import '../notifications/notifications_repository.dart';
import '../pos/pos_page.dart';
import '../purchasing/purchases_page.dart';
import '../reports/report_models.dart';
import '../reports/reports_page.dart';
import '../reports/reports_repository.dart';
import '../stock/stock_page.dart';
import '../tables/floor_plan_page.dart';
import '../tables/tables_models.dart';
import '../tables/tables_repository.dart';
import '../theme/app_theme.dart';
import '../users/users_page.dart';

const _frenchWeekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
const _frenchMonths = [
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

String _frenchDate(DateTime date) {
  final weekday = _frenchWeekdays[date.weekday - 1];
  final month = _frenchMonths[date.month - 1];
  final weekdayCapitalized = weekday[0].toUpperCase() + weekday.substring(1);
  return '$weekdayCapitalized ${date.day} $month';
}

class _ModuleEntry {
  const _ModuleEntry(this.icon, this.label, this.builder);
  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

/// Tableau de bord d'un établissement — écran d'accueil principal.
///
/// Restructuration purement visuelle de l'ancien écran d'accueil (liste
/// plate de boutons) selon "Nouvel interface.docx" : cartes de statistiques
/// du jour, actions rapides, modules regroupés par catégorie, navigation
/// inférieure. Aucune fonctionnalité n'est ajoutée ni retirée : toutes les
/// données affichées et toutes les pages ouvertes existaient déjà.
class HomeDashboard extends StatefulWidget {
  const HomeDashboard({
    super.key,
    required this.establishmentId,
    required this.establishmentName,
    required this.roleName,
  });

  final String establishmentId;
  final String establishmentName;
  final String roleName;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _DashboardData {
  _DashboardData({
    required this.summary,
    required this.tables,
    required this.unreadCount,
  });
  final ReportSummary summary;
  final List<RestaurantTable> tables;
  final int unreadCount;
}

class _HomeDashboardState extends State<HomeDashboard> {
  late final ReportsRepository _reports = ReportsRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final TablesRepository _tablesRepo = TablesRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final NotificationsRepository _notifications = NotificationsRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<_DashboardData> _future = _load();

  late final List<_ModuleEntry> _operations = [
    _ModuleEntry(
      Icons.table_restaurant_outlined,
      'Tables',
      (_) => FloorPlanPage(establishmentId: widget.establishmentId),
    ),
    _ModuleEntry(
      Icons.point_of_sale_outlined,
      'Caisse',
      (_) => PosPage(establishmentId: widget.establishmentId),
    ),
    _ModuleEntry(
      Icons.inventory_2_outlined,
      'Stock',
      (_) => StockPage(establishmentId: widget.establishmentId),
    ),
    _ModuleEntry(
      Icons.shopping_cart_outlined,
      'Achats',
      (_) => PurchasesPage(establishmentId: widget.establishmentId),
    ),
  ];
  late final List<_ModuleEntry> _gestion = [
    _ModuleEntry(
      Icons.receipt_long_outlined,
      'Dépenses',
      (_) => ExpensesPage(establishmentId: widget.establishmentId),
    ),
    _ModuleEntry(
      Icons.report_gmailerrorred_outlined,
      'Pertes',
      (_) => LossesPage(establishmentId: widget.establishmentId),
    ),
    _ModuleEntry(
      Icons.people_outline,
      'Clients',
      (_) => CustomersPage(establishmentId: widget.establishmentId),
    ),
    _ModuleEntry(
      Icons.storefront_outlined,
      'Catalogue',
      (_) => CatalogPage(establishmentId: widget.establishmentId),
    ),
  ];
  late final List<_ModuleEntry> _pilotage = [
    _ModuleEntry(
      Icons.bar_chart_outlined,
      'Rapports',
      (_) => ReportsPage(establishmentId: widget.establishmentId),
    ),
    // Anciennement une deuxième rubrique "Caisse" (icône tirelire) — renommée
    // pour lever l'ambiguïté avec le module Caisse/encaissement ci-dessus,
    // conformément à "Nouvel interface.docx". Même page (CashPage), aucun
    // changement de comportement.
    _ModuleEntry(
      Icons.point_of_sale,
      'Clôture',
      (_) => CashPage(establishmentId: widget.establishmentId),
    ),
    _ModuleEntry(
      Icons.notifications_outlined,
      'Notifications',
      (_) => NotificationsPage(establishmentId: widget.establishmentId),
    ),
    _ModuleEntry(
      Icons.insert_chart_outlined,
      'Graphiques',
      (_) => GraphiquesPage(establishmentId: widget.establishmentId),
    ),
  ];
  late final List<_ModuleEntry> _administration = [
    _ModuleEntry(
      Icons.manage_accounts_outlined,
      'Utilisateurs',
      (_) => UsersPage(establishmentId: widget.establishmentId),
    ),
  ];

  Future<_DashboardData> _load() async {
    final results = await Future.wait<dynamic>([
      _reports.getSummary(),
      _tablesRepo.listTables(),
      _notifications.unreadCount(),
    ]);
    return _DashboardData(
      summary: results[0] as ReportSummary,
      tables: results[1] as List<RestaurantTable>,
      unreadCount: results[2] as int,
    );
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _openPage(WidgetBuilder builder) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: builder));
    if (mounted) _reload();
  }

  void _showQuickActions() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Action rapide',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.restaurant_outlined,
                color: AppColors.green,
              ),
              title: const Text('Nouvelle commande'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openPage(
                  (_) => FloorPlanPage(establishmentId: widget.establishmentId),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.point_of_sale_outlined,
                color: AppColors.green,
              ),
              title: const Text('Encaisser'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openPage(
                  (_) => PosPage(establishmentId: widget.establishmentId),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.green,
              ),
              title: const Text('Réceptionner un achat'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openPage(
                  (_) => PurchasesPage(establishmentId: widget.establishmentId),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.receipt_long_outlined,
                color: AppColors.green,
              ),
              title: const Text('Enregistrer une dépense'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openPage(
                  (_) => ExpensesPage(establishmentId: widget.establishmentId),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAllModules() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Tous les modules',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            for (final entry in [
              ..._operations,
              ..._gestion,
              ..._pilotage,
              ..._administration,
            ])
              ListTile(
                leading: Icon(entry.icon, color: AppColors.green),
                title: Text(entry.label),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openPage(entry.builder);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.green, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moduleSection(String title, List<_ModuleEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisExtent: 84,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openPage(entry.builder),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.greenLight,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          entry.icon,
                          color: AppColors.green,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: AppColors.orangeLight,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/logo.png',
                  height: 38,
                  width: 38,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chez Yasmine',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  Text(
                    'Gestion du maquis',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FutureBuilder<_DashboardData>(
            future: _future,
            builder: (context, snapshot) {
              final unread = snapshot.data?.unreadCount ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'Notifications',
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => _openPage(
                      (_) => NotificationsPage(
                        establishmentId: widget.establishmentId,
                      ),
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.alert,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(minWidth: 16),
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'logout') Supabase.instance.client.auth.signOut();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<_DashboardData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final message = snapshot.error is ApiException
                    ? (snapshot.error as ApiException).message
                    : '${snapshot.error}';
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            "Impossible de joindre l'API : $message",
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _reload,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              final data = snapshot.data!;
              final occupied = data.tables
                  .where((t) => t.status != 'free')
                  .length;
              final total = data.tables.length;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Bonjour, ${widget.roleName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.waving_hand_outlined,
                        color: AppColors.orange,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _frenchDate(DateTime.now()),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent: 110,
                        ),
                    children: [
                      _statCard(
                        icon: Icons.trending_up,
                        label: "Ventes aujourd'hui",
                        value: '${formatAmount(data.summary.revenue)} F',
                        color: AppColors.green,
                      ),
                      _statCard(
                        icon: Icons.receipt_long_outlined,
                        label: "Commandes aujourd'hui",
                        value: '${data.summary.salesCount}',
                        color: AppColors.orange,
                      ),
                      _statCard(
                        icon: Icons.table_restaurant_outlined,
                        label: 'Tables occupées',
                        value: '$occupied / $total',
                        color: AppColors.orange,
                      ),
                      _statCard(
                        icon: Icons.warning_amber_outlined,
                        label: 'Alertes stock',
                        value: '${data.summary.lowStockCount}',
                        color: data.summary.lowStockCount > 0
                            ? AppColors.alert
                            : AppColors.green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'ACTIONS RAPIDES',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent: 56,
                        ),
                    children: [
                      _quickActionButton(
                        icon: Icons.add_circle_outline,
                        label: 'Commande',
                        onTap: () => _openPage(
                          (_) => FloorPlanPage(
                            establishmentId: widget.establishmentId,
                          ),
                        ),
                      ),
                      _quickActionButton(
                        icon: Icons.table_restaurant_outlined,
                        label: 'Tables',
                        onTap: () => _openPage(
                          (_) => FloorPlanPage(
                            establishmentId: widget.establishmentId,
                          ),
                        ),
                      ),
                      _quickActionButton(
                        icon: Icons.point_of_sale_outlined,
                        label: 'Encaisser',
                        onTap: () => _openPage(
                          (_) =>
                              PosPage(establishmentId: widget.establishmentId),
                        ),
                      ),
                      _quickActionButton(
                        icon: Icons.inventory_2_outlined,
                        label: 'Stock',
                        onTap: () => _openPage(
                          (_) => StockPage(
                            establishmentId: widget.establishmentId,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _moduleSection('OPÉRATIONS', _operations),
                  _moduleSection('GESTION', _gestion),
                  _moduleSection('PILOTAGE', _pilotage),
                  _moduleSection('ADMINISTRATION', _administration),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 1:
              _openPage(
                (_) => PosPage(establishmentId: widget.establishmentId),
              );
              break;
            case 2:
              _showQuickActions();
              break;
            case 3:
              _openPage(
                (_) => PurchasesPage(establishmentId: widget.establishmentId),
              );
              break;
            case 4:
              _showAllModules();
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale_outlined),
            label: 'Caisse',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle, color: AppColors.orange, size: 30),
            label: 'Action',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            label: 'Achats',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Menu'),
        ],
      ),
    );
  }
}
