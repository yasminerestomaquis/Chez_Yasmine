import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../cash/cash_page.dart';
import '../catalog/catalog_page.dart';
import '../charts/graphiques_page.dart';
import '../common/app_reload.dart';
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
/// Restructuration initialement purement visuelle de l'ancien écran
/// d'accueil (liste plate de boutons) selon "Nouvel interface.docx" : cartes
/// de statistiques du jour, actions rapides, modules regroupés par
/// catégorie, navigation inférieure.
///
/// Décision actée 2026-09-10 : "Ventes aujourd'hui" décomposée par mode de
/// paiement (Espèces/Mobile Money) et la tuile "Tables occupées" remplacée
/// par "Recettes boissons/plats aujourd'hui" + leur détail par mode de
/// paiement — voir `ReportsService.paymentCategoryBreakdown`
/// (`docs/api/reports.md`). La liste des tables n'est donc plus chargée ici.
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
    required this.breakdown,
    required this.unreadCount,
  });
  // Nullable : un rôle sans la permission `reports.view` (ex. Serveur,
  // Magasinier — voir supabase/seed/001_roles_permissions.sql) n'a pas accès
  // à ces indicateurs. On l'affiche sans eux plutôt que de bloquer tout
  // l'accueil derrière un 403 (voir _load()).
  final ReportSummary? summary;
  final PaymentCategoryBreakdown? breakdown;
  final int unreadCount;
}

class _HomeDashboardState extends State<HomeDashboard> {
  // Comparaison par nom de rôle (voir supabase/seed/001_roles_permissions.sql)
  // faute d'un identifiant de rôle stable exposé côté client (`GET /auth/me`
  // ne renvoie que `role` en texte, pas de code de permission — voir
  // `MyEstablishment`). Demande utilisateur du 2026-09-11 : le Serveur a
  // `reports.view` (uniquement pour ces 3 cartes) mais ne doit voir ni le
  // total "Ventes aujourd'hui", ni les recettes/paiements Plats, ni
  // Commandes/Alertes stock — réservés aux rôles avec une vue d'ensemble.
  bool get _isServeur => widget.roleName == 'Serveur';

  late final ReportsRepository _reports = ReportsRepository(
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
      (_) => StockPage(
        establishmentId: widget.establishmentId,
        roleName: widget.roleName,
      ),
    ),
    _ModuleEntry(
      Icons.shopping_cart_outlined,
      'Achats',
      (_) => PurchasesPage(
        establishmentId: widget.establishmentId,
        roleName: widget.roleName,
      ),
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
      (_) => ReportsPage(
        establishmentId: widget.establishmentId,
        roleName: widget.roleName,
      ),
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

  /// Les 3 appels partent en parallèle (démarrés avant tout `await`), comme
  /// avant. `summary`/`breakdown` exigent `reports.view` côté serveur — un
  /// rôle qui ne l'a pas (Serveur, Magasinier, ...) reçoit un 403 dessus,
  /// traité ici comme "pas d'indicateurs à afficher" plutôt que de faire
  /// échouer tout le chargement de l'accueil (`unreadCount` n'exige aucune
  /// permission particulière, voir NotificationsController).
  Future<_DashboardData> _load() async {
    final summaryFuture = _reports.getSummary();
    final breakdownFuture = _reports.getPaymentCategoryBreakdown();
    final unreadFuture = _notifications.unreadCount();

    // Les 3 futures sont attendues ici quoi qu'il arrive (jamais de `rethrow`
    // avant d'avoir attendu les 3) : un `rethrow` immédiat sur `summary`
    // laisserait `breakdownFuture`/`unreadFuture`, déjà lancées, sans jamais
    // être observées si elles échouent aussi — une "unhandled exception"
    // silencieuse en prime d'une régression bien plus difficile à repérer.
    Object? unexpectedError;

    ReportSummary? summary;
    try {
      summary = await summaryFuture;
    } on ApiException catch (e) {
      if (e.statusCode != 403) unexpectedError = e;
    }
    PaymentCategoryBreakdown? breakdown;
    try {
      breakdown = await breakdownFuture;
    } on ApiException catch (e) {
      if (e.statusCode != 403) unexpectedError ??= e;
    }
    final unreadCount = await unreadFuture;

    if (unexpectedError != null) throw unexpectedError;

    return _DashboardData(
      summary: summary,
      breakdown: breakdown,
      unreadCount: unreadCount,
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
              title: const Text('Réceptionner un menu'),
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
              title: const Text('Commander boissons'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openPage(
                  (_) => PurchasesPage(
                    establishmentId: widget.establishmentId,
                    roleName: widget.roleName,
                  ),
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
    // Icônes décoratives à côté du libellé (demande utilisateur du
    // 2026-09-12 : Wave/Espèces existants + 2 icônes produit — Malta pour
    // les cartes "Boissons", Kedjenou de poulet pour les cartes "Plats" —,
    // un peu plus grandes que l'icône unique précédente) ; `null`/vide :
    // aucune icône.
    List<String>? iconAssets,
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
            Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (iconAssets != null)
                  for (final asset in iconAssets) ...[
                    const SizedBox(width: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        asset,
                        width: 18,
                        height: 18,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Carte pleine largeur : "Ventes aujourd'hui" décomposée par mode de
  /// paiement (Espèces/Mobile Money) — le total est construit comme la somme
  /// exacte des deux, voir `ReportsService.paymentCategoryBreakdown`.
  Widget _salesSummaryCard(PaymentCategoryBreakdown breakdown) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.trending_up,
                    color: AppColors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  "Total ventes Aujourd'hui",
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Image.asset(
                    'assets/home_icon_1.jpg',
                    width: 14,
                    height: 14,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${formatAmount(breakdown.totalRevenue)} F',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _miniStat(
                    'Espèces',
                    breakdown.cashRevenue,
                    iconAsset: 'assets/home_icon_2.jpg',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _miniStat(
                    'Mobile Money',
                    breakdown.mobileMoneyRevenue,
                    iconAsset: 'assets/home_icon_3.jpg',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, double value, {String? iconAsset}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.greenLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (iconAsset != null) ...[
                const SizedBox(width: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Image.asset(
                    iconAsset,
                    width: 13,
                    height: 13,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${formatAmount(value)} F',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
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
          // Rechargement complet du navigateur (pas seulement _reload()) :
          // récupère aussi bien les dernières données que, le cas échéant,
          // un nouveau `main.dart.js` déployé depuis le dernier chargement
          // — demande utilisateur du 2026-09-13.
          IconButton(
            tooltip: 'Synchroniser / actualiser l\'application',
            icon: const Icon(Icons.sync),
            onPressed: reloadApp,
          ),
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
              // Variables locales : Dart peut alors "promouvoir" le type
              // (String? -> String) dans les blocs `if (breakdown != null)`
              // ci-dessous, ce qui serait refusé sur `data.breakdown` (getter).
              final summary = data.summary;
              final breakdown = data.breakdown;

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
                  if (breakdown != null && !_isServeur) ...[
                    _salesSummaryCard(breakdown),
                    const SizedBox(height: 10),
                  ],
                  if (summary != null && !_isServeur) ...[
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
                          icon: Icons.receipt_long_outlined,
                          label: "Commandes aujourd'hui",
                          value: '${summary.salesCount}',
                          color: AppColors.orange,
                        ),
                        _statCard(
                          icon: Icons.warning_amber_outlined,
                          label: 'Alertes stock',
                          value: '${summary.lowStockCount}',
                          color: summary.lowStockCount > 0
                              ? AppColors.alert
                              : AppColors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (breakdown != null) ...[
                    const Text(
                      'RECETTES DU JOUR',
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
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _isServeur ? 1 : 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 110,
                      ),
                      children: [
                        _statCard(
                          icon: Icons.sports_bar_outlined,
                          label: 'Recettes boissons aujourd\'hui',
                          value: '${formatAmount(breakdown.boissonsRevenue)} F',
                          color: AppColors.green,
                          iconAssets: const ['assets/malta.jpg'],
                        ),
                        if (!_isServeur)
                          _statCard(
                            icon: Icons.restaurant_outlined,
                            label: 'Recettes plats aujourd\'hui',
                            value: '${formatAmount(breakdown.platsRevenue)} F',
                            color: AppColors.orange,
                            iconAssets: const ['assets/kedjenou_poulet.jpg'],
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'DÉTAIL PAR MODE DE PAIEMENT',
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
                            mainAxisExtent: 100,
                          ),
                      children: [
                        _statCard(
                          icon: Icons.payments_outlined,
                          label: 'Boissons · Espèces',
                          value: '${formatAmount(breakdown.boissonsCash)} F',
                          color: AppColors.green,
                          iconAssets: const [
                            'assets/home_icon_2.jpg',
                            'assets/malta.jpg',
                          ],
                        ),
                        _statCard(
                          icon: Icons.phone_iphone_outlined,
                          label: 'Boissons · Mobile Money',
                          value:
                              '${formatAmount(breakdown.boissonsMobileMoney)} F',
                          color: AppColors.green,
                          iconAssets: const [
                            'assets/home_icon_3.jpg',
                            'assets/malta.jpg',
                          ],
                        ),
                        if (!_isServeur) ...[
                          _statCard(
                            icon: Icons.payments_outlined,
                            label: 'Plats · Espèces',
                            value: '${formatAmount(breakdown.platsCash)} F',
                            color: AppColors.orange,
                            iconAssets: const [
                              'assets/home_icon_2.jpg',
                              'assets/kedjenou_poulet.jpg',
                            ],
                          ),
                          _statCard(
                            icon: Icons.phone_iphone_outlined,
                            label: 'Plats · Mobile Money',
                            value:
                                '${formatAmount(breakdown.platsMobileMoney)} F',
                            color: AppColors.orange,
                            iconAssets: const [
                              'assets/home_icon_3.jpg',
                              'assets/kedjenou_poulet.jpg',
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
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
                        label: 'Caisse',
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
                            roleName: widget.roleName,
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
                (_) => PurchasesPage(
                  establishmentId: widget.establishmentId,
                  roleName: widget.roleName,
                ),
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
