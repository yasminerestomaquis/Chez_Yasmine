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
import 'date_selection.dart';
import '../losses/losses_page.dart';
import '../notifications/notifications_page.dart';
import '../notifications/notifications_repository.dart';
import '../pos/pos_page.dart';
import '../purchasing/purchases_page.dart';
import '../reports/report_models.dart';
import '../reports/reports_page.dart';
import '../reports/reports_repository.dart';
import '../stock/stock_page.dart';
import '../sync/global_sync_context.dart';
import '../tables/floor_plan_page.dart';
import '../theme/app_theme.dart';
import '../users/users_page.dart';

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
  final ({int salesCount, int lowStockCount})? summary;
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

  // Demande utilisateur du 2026-09-13 : le Gérant ne doit pas voir le module
  // Utilisateurs (gestion des comptes/rôles) — masqué ici en plus du refus
  // serveur (users.manage retirée de ce rôle, voir
  // supabase/seed/001_roles_permissions.sql), défense en profondeur comme
  // pour le reste de l'application.
  bool get _isGerant => widget.roleName == 'Gérant';

  late final ReportsRepository _reports = ReportsRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final NotificationsRepository _notifications = NotificationsRepository(
    ApiClient(),
    widget.establishmentId,
  );

  /// Aujourd'hui, tronqué à la date (sans heure) — base commune du filtre de
  /// date et de la date sélectionnée par défaut.
  DateTime get _todayDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Filtre "Date" de l'accueil (décision utilisateur du 2026-09-14, passé en
  /// sélection multiple le 2026-09-20) : aujourd'hui et les 6 jours
  /// précédents, le plus récent en premier. Les cartes de statistiques
  /// ci-dessous (ventes, recettes boissons/plats, détail par mode de
  /// paiement) cumulent toutes les dates cochées ici, jamais figées sur
  /// "aujourd'hui".
  List<DateTime> get _dateOptions =>
      List.generate(7, (i) => _todayDate.subtract(Duration(days: i)));

  late Set<DateTime> _selectedDates = {_todayDate};

  bool get _isToday =>
      _selectedDates.length == 1 && _selectedDates.first == _todayDate;

  String get _periodPhrase => periodPhrase(_selectedDates, _todayDate);

  Future<void> _pickDates() async {
    final chosen = await showDialog<Set<DateTime>>(
      context: context,
      builder: (dialogContext) {
        var working = {..._selectedDates};
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Filtrer par date'),
            content: SizedBox(
              width: 360,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final date in _dateOptions)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: working.contains(date),
                      title: Text(
                        date == _todayDate ? "Aujourd'hui" : frenchDate(date),
                      ),
                      onChanged: (checked) => setDialogState(() {
                        if (checked ?? false) {
                          working.add(date);
                        } else {
                          working.remove(date);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setDialogState(() => working = {_todayDate}),
                child: const Text('Réinitialiser'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: working.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop(working),
                child: const Text('Appliquer'),
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null) return;
    setState(() => _selectedDates = chosen);
    _reload();
  }

  late Future<_DashboardData> _future = _load();

  @override
  void initState() {
    super.initState();
    // Fait connaître l'établissement courant à la barre de synchronisation
    // globale (montée une seule fois au-dessus de l'écran courant, voir
    // main.dart) — sans ça, elle n'a aucun moyen de savoir quelle file
    // hors ligne afficher tant qu'aucun module n'a été ouvert.
    GlobalSyncContext.establishmentId.value = widget.establishmentId;
  }

  late final List<_ModuleEntry> _operations = [
    _ModuleEntry(
      Icons.table_restaurant_outlined,
      'Tables',
      (_) => FloorPlanPage(establishmentId: widget.establishmentId, roleName: widget.roleName),
    ),
    _ModuleEntry(
      Icons.point_of_sale_outlined,
      'Caisse',
      (_) => PosPage(establishmentId: widget.establishmentId, roleName: widget.roleName),
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
      (_) => LossesPage(establishmentId: widget.establishmentId, roleName: widget.roleName),
    ),
    _ModuleEntry(
      Icons.people_outline,
      'Clients',
      (_) => CustomersPage(establishmentId: widget.establishmentId),
    ),
    _ModuleEntry(
      Icons.storefront_outlined,
      'Catalogue',
      (_) => CatalogPage(establishmentId: widget.establishmentId, roleName: widget.roleName),
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
      (_) => NotificationsPage(
        establishmentId: widget.establishmentId,
        roleName: widget.roleName,
      ),
    ),
    _ModuleEntry(
      Icons.insert_chart_outlined,
      'Graphiques',
      (_) => GraphiquesPage(establishmentId: widget.establishmentId),
    ),
  ];
  late final List<_ModuleEntry> _administration = [
    if (!_isGerant)
      _ModuleEntry(
        Icons.manage_accounts_outlined,
        'Utilisateurs',
        (_) => UsersPage(
          establishmentId: widget.establishmentId,
          roleName: widget.roleName,
        ),
      ),
  ];

  /// Les 3 appels partent en parallèle (démarrés avant tout `await`), comme
  /// avant. `summary`/`breakdown` exigent `reports.view` côté serveur — un
  /// rôle qui ne l'a pas (Serveur, Magasinier, ...) reçoit un 403 dessus.
  ///
  /// Toute erreur (403, ou n'importe quelle autre — en particulier une
  /// coupure réseau) est traitée comme "pas d'indicateur à afficher",
  /// jamais comme une erreur bloquante pour tout l'accueil : avant ce
  /// correctif, une coupure réseau ici bloquait la grille de modules
  /// elle-même (Tables, Caisse, Stock...) puisqu'elle est rendue dans la
  /// même `FutureBuilder` — empêchant d'ouvrir l'application hors ligne
  /// malgré le reste de la mécanique déjà en place (constaté par
  /// l'utilisateur le 2026-09-13, voir docs/api/sync.md). Ces 3 appels ne
  /// portent que des indicateurs de confort en lecture seule ; les masquer
  /// hors ligne est un compromis largement préférable à bloquer la
  /// navigation.
  Future<_DashboardData> _load() async {
    // Bornes UTC explicites de chaque jour choisi (00:00:00.000 ->
    // 23:59:59.999) : ReportsService.resolveRange fait `new Date(from)`/
    // `new Date(to)` côté serveur sans ajouter de fin de journée — envoyer la
    // même date pour from et to donnerait un intervalle de largeur nulle
    // (aucune vente ne tombe pile à minuit) et ne renverrait jamais rien.
    // Une requête par jour coché (le serveur ne résout qu'un intervalle
    // continu), cumulées ensuite par `mergeSummaries`/`mergeBreakdowns`.
    final ranges = [
      for (final date in _selectedDates)
        (
          from: DateTime.utc(date.year, date.month, date.day),
          to: DateTime.utc(date.year, date.month, date.day)
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1)),
        ),
    ];

    final summaryFuture = Future.wait([
      for (final r in ranges)
        _reports.getSummary(
          from: r.from.toIso8601String(),
          to: r.to.toIso8601String(),
        ),
    ]);
    final breakdownFuture = Future.wait([
      for (final r in ranges)
        _reports.getPaymentCategoryBreakdown(
          from: r.from.toIso8601String(),
          to: r.to.toIso8601String(),
        ),
    ]);
    final unreadFuture = _notifications.unreadCount();

    // Les 3 futures sont attendues ici quoi qu'il arrive : un retour anticipé
    // sur l'échec de l'une laisserait les autres, déjà lancées, sans jamais
    // être observées si elles échouent aussi — une "unhandled exception"
    // silencieuse en prime d'une régression bien plus difficile à repérer.
    ({int salesCount, int lowStockCount})? summary;
    try {
      summary = mergeSummaries(await summaryFuture);
    } catch (_) {
      // ignore — voir le commentaire de _load() ci-dessus.
    }
    PaymentCategoryBreakdown? breakdown;
    try {
      breakdown = mergeBreakdowns(await breakdownFuture);
    } catch (_) {
      // ignore
    }
    var unreadCount = 0;
    try {
      unreadCount = await unreadFuture;
    } catch (_) {
      // ignore
    }

    return _DashboardData(
      summary: summary,
      breakdown: breakdown,
      unreadCount: unreadCount,
    );
  }

  Future<void> _reload() async {
    final next = _load();
    // Accolades nécessaires : `() => _future = next` renvoie la valeur de
    // l'affectation (le Future lui-même) comme résultat de la closure —
    // `setState` rejette alors un callback qui "retourne un Future"
    // (assertion levée en debug/test, silencieuse en release). Révélé par
    // le nouveau test du filtre de date (2026-09-14), qui est le premier à
    // exercer `_reload()` dans `flutter test`.
    setState(() {
      _future = next;
    });
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
                  (_) => FloorPlanPage(establishmentId: widget.establishmentId, roleName: widget.roleName),
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
                  (_) => PosPage(establishmentId: widget.establishmentId, roleName: widget.roleName),
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
                Text(
                  'Total ventes $_periodPhrase',
                  style: const TextStyle(
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
                        roleName: widget.roleName,
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
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: _pickDates,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              dateFilterLabel(_selectedDates, _todayDate),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ],
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
                          label: 'Commandes $_periodPhrase',
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
                    Text(
                      _isToday
                          ? 'RECETTES DU JOUR'
                          : 'RECETTES ${_periodPhrase.toUpperCase()}',
                      style: const TextStyle(
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
                          label: 'Recettes boissons $_periodPhrase',
                          value: '${formatAmount(breakdown.boissonsRevenue)} F',
                          color: AppColors.green,
                          iconAssets: const ['assets/malta.jpg'],
                        ),
                        if (!_isServeur)
                          _statCard(
                            icon: Icons.restaurant_outlined,
                            label: 'Recettes plats $_periodPhrase',
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
                            roleName: widget.roleName,
                          ),
                        ),
                      ),
                      _quickActionButton(
                        icon: Icons.table_restaurant_outlined,
                        label: 'Tables',
                        onTap: () => _openPage(
                          (_) => FloorPlanPage(
                            establishmentId: widget.establishmentId,
                            roleName: widget.roleName,
                          ),
                        ),
                      ),
                      _quickActionButton(
                        icon: Icons.point_of_sale_outlined,
                        label: 'Caisse',
                        onTap: () => _openPage(
                          (_) =>
                              PosPage(establishmentId: widget.establishmentId, roleName: widget.roleName),
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
                  if (_administration.isNotEmpty)
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
                (_) => PosPage(establishmentId: widget.establishmentId, roleName: widget.roleName),
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
