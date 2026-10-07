import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../cash/cash_page.dart';
import '../catalog/catalog_page.dart';
import '../charts/graphiques_page.dart';
import '../common/app_reload.dart';
import '../common/date_time_range_picker.dart';
import '../common/formatting.dart';
import '../customers/customers_page.dart';
import '../expenses/expenses_page.dart';
import 'dashboard_widgets.dart';
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

final _rangeLabelFormat = DateFormat('dd/MM/yyyy HH:mm');

class _ModuleEntry {
  const _ModuleEntry(this.icon, this.label, this.builder);
  final IconData icon;
  final String label;
  final WidgetBuilder builder;

  /// Teinte de la tuile du module (purement visuelle).
  DashTone get tone => switch (label) {
    'Tables' => DashTone.teal,
    'Caisse' || 'Rapports' => DashTone.purple,
    'Stock' || 'Catalogue' || 'Clôture' => DashTone.orange,
    'Achats' || 'Graphiques' => DashTone.green,
    'Dépenses' || 'Pertes' || 'Clients' => DashTone.blue,
    'Notifications' => DashTone.red,
    _ => DashTone.teal,
  };
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

  /// Intervalle précis (date + heure + minute pour chaque borne), choisi via
  /// « Définir un intervalle précis » dans le filtre Date — demande
  /// utilisateur du 2026-09-26. `null` par défaut (et après
  /// "Réinitialiser") : le filtre par jour(s) entier(s) ci-dessus
  /// (`_selectedDates`, minuit-minuit) reste le comportement par défaut,
  /// inchangé.
  ({DateTime from, DateTime to})? _customRange;

  bool get _isToday =>
      _customRange == null &&
      _selectedDates.length == 1 &&
      _selectedDates.first == _todayDate;

  String get _periodPhrase => _customRange != null
      ? 'du ${_rangeLabelFormat.format(_customRange!.from)} au ${_rangeLabelFormat.format(_customRange!.to)}'
      : periodPhrase(_selectedDates, _todayDate);

  String get _dateFilterLabel => _customRange != null
      ? '${_rangeLabelFormat.format(_customRange!.from)} → ${_rangeLabelFormat.format(_customRange!.to)}'
      : dateFilterLabel(_selectedDates, _todayDate);

  Future<void> _pickDates() async {
    final chosen = await showDialog<Object>(
      context: context,
      builder: (dialogContext) {
        var working = {..._selectedDates};
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            // `scrollable: true` (plutôt qu'un `ListView`/`shrinkWrap`
            // imbriqué, qui ne construit paresseusement que les tuiles
            // visibles dans sa hauteur bornée) : la liste des 7 jours ET le
            // bouton d'intervalle précis en dessous restent tous construits,
            // le dialogue défilant lui-même si le contenu dépasse la hauteur
            // disponible.
            scrollable: true,
            title: const Text('Filtrer par date'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  const Divider(),
                  // Si l'utilisateur veut véritablement définir, pour chaque
                  // borne, la date, l'heure et la minute plutôt qu'un ou
                  // plusieurs jours entiers — ferme aussi ce dialogue-ci en
                  // renvoyant directement l'intervalle choisi (demande
                  // utilisateur du 2026-09-26).
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final range = await pickDateTimeRange(
                          dialogContext,
                          initialFrom: _customRange?.from ?? _todayDate,
                          initialTo: _customRange?.to ?? DateTime.now(),
                        );
                        if (range == null) return;
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop(range);
                      },
                      icon: const Icon(Icons.schedule_outlined, size: 18),
                      label: const Text('Définir un intervalle précis'),
                    ),
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
    setState(() {
      if (chosen is Set<DateTime>) {
        _selectedDates = chosen;
        _customRange = null;
      } else if (chosen is ({DateTime from, DateTime to})) {
        _customRange = chosen;
      }
    });
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
    //
    // Différé après la frame courante : cette écriture notifie le
    // ValueListenableBuilder de main.dart, un ANCÊTRE de ce widget. La faire
    // pendant le build (donc ici, en initState) est interdit par Flutter — en
    // production la notification est perdue et la barre « En ligne / Hors
    // ligne » n'apparaît jamais (régression du 2026-10-04 : l'accueil s'affiche
    // maintenant dès la copie locale du profil, dans une frame où l'ancêtre est
    // lui-même en construction). Même précaution que dans auth_gate.dart.
    final establishmentId = widget.establishmentId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) GlobalSyncContext.establishmentId.value = establishmentId;
    });
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
    // Intervalle précis choisi via "Définir un intervalle précis" (date +
    // heure + minute pour chaque borne, demande utilisateur du 2026-09-26) :
    // un seul intervalle continu, envoyé tel quel au serveur. Par défaut
    // (`_customRange` nul), comportement inchangé — bornes UTC explicites de
    // chaque jour choisi (00:00:00.000 -> 23:59:59.999) :
    // ReportsService.resolveRange fait `new Date(from)`/`new Date(to)` côté
    // serveur sans ajouter de fin de journée — envoyer la même date pour
    // from et to donnerait un intervalle de largeur nulle (aucune vente ne
    // tombe pile à minuit) et ne renverrait jamais rien. Une requête par
    // jour coché (le serveur ne résout qu'un intervalle continu), cumulées
    // ensuite par `mergeSummaries`/`mergeBreakdowns`.
    final ranges = _customRange != null
        ? [(from: _customRange!.from.toUtc(), to: _customRange!.to.toUtc())]
        : [
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
                Icons.fact_check_outlined,
                color: AppColors.green,
              ),
              title: const Text('Vérifier le Stock'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openPage(
                  (_) => StockPage(
                    establishmentId: widget.establishmentId,
                    roleName: widget.roleName,
                  ),
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

  /// Grille de vignettes `DashStatCard`, [columns] par ligne, sans hauteur
  /// figée — pour que les désignations longues (ex. « Boissons sans Gbêlê -
  /// Mobile Money ») s'affichent toujours en entier, sur plusieurs lignes si
  /// besoin, quelle que soit la largeur de l'écran, plutôt que d'être coupées
  /// par une ellipse dans une carte de hauteur fixe (demande utilisateur du
  /// 2026-09-25). `IntrinsicHeight` aligne les cartes d'une même ligne sur la
  /// plus haute.
  Widget _cardGrid(List<Widget> cards, {int columns = 2}) {
    const gap = 10.0;
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += columns) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                Expanded(
                  child: i + c < cards.length ? cards[i + c] : const SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
      if (i + columns < cards.length) rows.add(const SizedBox(height: gap));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  /// 3 colonnes quand le nombre de cartes s'y prête (3 ou 6), sinon 2.
  int _columnsFor(int count) => count % 3 == 0 ? 3 : 2;

  /// Tuiles cliquables de hauteur fixe, [columns] par ligne.
  Widget _tileGrid(List<DashTile> tiles, {int columns = 3}) {
    const gap = 10.0;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += columns) {
      rows.add(
        SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                Expanded(
                  child: i + c < tiles.length ? tiles[i + c] : const SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
      if (i + columns < tiles.length) rows.add(const SizedBox(height: gap));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _moduleSection(String title, IconData icon, List<_ModuleEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashSectionTitle(icon: icon, title: title),
        const SizedBox(height: 10),
        _tileGrid([
          for (final entry in entries)
            DashTile(
              tone: entry.tone,
              icon: entry.icon,
              label: entry.label,
              onTap: () => _openPage(entry.builder),
            ),
        ]),
        const SizedBox(height: 18),
      ],
    );
  }

  /// Bandeau d'accueil crème : salutation, filtre de date, « Bon appétit ».
  Widget _greetingHeader() {
    const amber = Color(0xFFF5A524);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFF4E4), Color(0xFFFCF8EE), Color(0xFFEDF6E6)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.waving_hand, color: amber, size: 26),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Bonjour, ${widget.roleName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 19,
                          ),
                        ),
                      ),
                      if (widget.roleName == 'Super Administrateur') ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.workspace_premium, color: amber, size: 24),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: AppColors.greenDark,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: InkWell(
                          onTap: _pickDates,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _dateFilterLabel,
                                  style: const TextStyle(
                                    color: AppColors.greenDark,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.expand_more,
                                size: 20,
                                color: AppColors.greenDark,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (constraints.maxWidth >= 420) ...[
              const SizedBox(width: 8),
              const Text(
                'Bon appétit',
                style: TextStyle(
                  fontFamily: 'cursive',
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  fontSize: 24,
                  color: AppColors.greenDark,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.greenDark,
        foregroundColor: Colors.white,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.white,
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Gestion du maquis',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
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
              // La grille des modules s'affiche TOUT DE SUITE : seuls les
              // indicateurs (ventes, alertes stock) attendent le serveur. Avant,
              // un cercle de chargement masquait tout l'accueil jusqu'à la
              // réponse des trois appels — jusqu'à 30 à 60 s au démarrage à
              // froid de l'API (Render, plan gratuit), alors que les modules
              // eux-mêmes ne dépendent pas de ces indicateurs.
              final loading = snapshot.connectionState != ConnectionState.done;
              if (!loading && snapshot.hasError) {
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

              final data = snapshot.data ?? _DashboardData(summary: null, breakdown: null, unreadCount: 0);
              // Variables locales : Dart peut alors "promouvoir" le type
              // (String? -> String) dans les blocs `if (breakdown != null)`
              // ci-dessous, ce qui serait refusé sur `data.breakdown` (getter).
              final summary = data.summary;
              final breakdown = data.breakdown;

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (loading) const LinearProgressIndicator(minHeight: 2),
                  _greetingHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (breakdown != null && !_isServeur) ...[
                          DashStatCard(
                            large: true,
                            tone: DashTone.green,
                            icon: Icons.trending_up,
                            label: 'Total ventes $_periodPhrase',
                            labelSuffixIcon: Icons.north_east,
                            value: '${formatAmount(breakdown.totalRevenue)} F',
                            watermark: Icons.payments_rounded,
                          ),
                          const SizedBox(height: 10),
                          _cardGrid([
                            DashStatCard(
                              tone: DashTone.green,
                              icon: Icons.payments_outlined,
                              label: 'Espèces',
                              value: '${formatAmount(breakdown.cashRevenue)} F',
                              images: const ['assets/home_icon_2.jpg'],
                            ),
                            DashStatCard(
                              tone: DashTone.blue,
                              icon: Icons.phone_iphone_outlined,
                              label: 'Mobile Money',
                              value:
                                  '${formatAmount(breakdown.mobileMoneyRevenue)} F',
                              images: const ['assets/home_icon_3.jpg'],
                            ),
                          ]),
                          SizedBox(height: summary != null ? 10 : 20),
                        ],
                        if (summary != null && !_isServeur) ...[
                          _cardGrid([
                            DashStatCard(
                              tone: DashTone.orange,
                              icon: Icons.receipt_long_outlined,
                              label: 'Commandes $_periodPhrase',
                              value: '${summary.salesCount}',
                              watermark: Icons.room_service_outlined,
                            ),
                            DashStatCard(
                              tone: summary.lowStockCount > 0
                                  ? DashTone.red
                                  : DashTone.green,
                              icon: Icons.warning_amber_rounded,
                              label: 'Alertes stock',
                              value: '${summary.lowStockCount}',
                              watermark: Icons.inventory_2_outlined,
                            ),
                          ]),
                          const SizedBox(height: 20),
                        ],
                        if (breakdown != null) ...[
                          DashSectionTitle(
                            icon: Icons.restaurant,
                            title: _isToday
                                ? 'RECETTES DU JOUR'
                                : 'RECETTES ${_periodPhrase.toUpperCase()}',
                          ),
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final cards = <Widget>[
                                DashStatCard(
                                  compact: true,
                                  tone: DashTone.green,
                                  icon: Icons.sports_bar_outlined,
                                  label:
                                      'Recettes boissons sans Gbêlê $_periodPhrase',
                                  value:
                                      '${formatAmount(breakdown.boissonsSansGbeleRevenue)} F',
                                  images: const ['assets/malta.jpg'],
                                ),
                                // Isolée de "Recettes boissons" le 2026-09-24
                                // (demande utilisateur) — visible aussi au
                                // Serveur, comme la carte ci-dessus.
                                DashStatCard(
                                  compact: true,
                                  tone: DashTone.purple,
                                  icon: Icons.local_drink_outlined,
                                  label: 'Recettes Gbêlê $_periodPhrase',
                                  value:
                                      '${formatAmount(breakdown.gbeleRevenue)} F',
                                  images: const ['assets/gbele.jpg'],
                                ),
                                if (!_isServeur)
                                  DashStatCard(
                                    compact: true,
                                    tone: DashTone.orange,
                                    icon: Icons.restaurant_outlined,
                                    label: 'Recettes plats $_periodPhrase',
                                    value:
                                        '${formatAmount(breakdown.platsRevenue)} F',
                                    images: const ['assets/kedjenou_poulet.jpg'],
                                  ),
                              ];
                              return _cardGrid(
                                cards,
                                columns: _columnsFor(cards.length),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          const DashSectionTitle(
                            icon: Icons.account_balance_wallet,
                            title: 'DÉTAIL PAR MODE DE PAIEMENT',
                          ),
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final cards = <Widget>[
                                DashStatCard(
                                  compact: true,
                                  tone: DashTone.green,
                                  icon: Icons.payments_outlined,
                                  label: 'Boissons sans Gbêlê - Espèces',
                                  value:
                                      '${formatAmount(breakdown.boissonsSansGbeleCash)} F',
                                  images: const [
                                    'assets/home_icon_2.jpg',
                                    'assets/malta.jpg',
                                  ],
                                ),
                                DashStatCard(
                                  compact: true,
                                  tone: DashTone.green,
                                  icon: Icons.phone_iphone_outlined,
                                  label: 'Boissons sans Gbêlê - Mobile Money',
                                  value:
                                      '${formatAmount(breakdown.boissonsSansGbeleMobileMoney)} F',
                                  images: const [
                                    'assets/home_icon_3.jpg',
                                    'assets/malta.jpg',
                                  ],
                                ),
                                DashStatCard(
                                  compact: true,
                                  tone: DashTone.purple,
                                  icon: Icons.payments_outlined,
                                  label: 'Gbêlê - Espèces',
                                  value:
                                      '${formatAmount(breakdown.gbeleCash)} F',
                                  images: const [
                                    'assets/home_icon_2.jpg',
                                    'assets/gbele.jpg',
                                  ],
                                ),
                                DashStatCard(
                                  compact: true,
                                  tone: DashTone.purple,
                                  icon: Icons.phone_iphone_outlined,
                                  label: 'Gbêlê - Mobile Money',
                                  value:
                                      '${formatAmount(breakdown.gbeleMobileMoney)} F',
                                  images: const [
                                    'assets/home_icon_3.jpg',
                                    'assets/gbele.jpg',
                                  ],
                                ),
                                if (!_isServeur) ...[
                                  DashStatCard(
                                    compact: true,
                                    tone: DashTone.orange,
                                    icon: Icons.payments_outlined,
                                    label: 'Plats - Espèces',
                                    value:
                                        '${formatAmount(breakdown.platsCash)} F',
                                    images: const [
                                      'assets/home_icon_2.jpg',
                                      'assets/kedjenou_poulet.jpg',
                                    ],
                                  ),
                                  DashStatCard(
                                    compact: true,
                                    tone: DashTone.orange,
                                    icon: Icons.phone_iphone_outlined,
                                    label: 'Plats - Mobile Money',
                                    value:
                                        '${formatAmount(breakdown.platsMobileMoney)} F',
                                    images: const [
                                      'assets/home_icon_3.jpg',
                                      'assets/kedjenou_poulet.jpg',
                                    ],
                                  ),
                                ],
                              ];
                              return _cardGrid(
                                cards,
                                columns: _columnsFor(cards.length),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                        const DashSectionTitle(
                          icon: Icons.flash_on,
                          title: 'ACTIONS RAPIDES',
                        ),
                        const SizedBox(height: 10),
                        _tileGrid([
                          DashTile(
                            tone: DashTone.green,
                            icon: Icons.room_service_outlined,
                            label: 'Commande',
                            onTap: () => _openPage(
                              (_) => FloorPlanPage(
                                establishmentId: widget.establishmentId,
                                roleName: widget.roleName,
                              ),
                            ),
                          ),
                          DashTile(
                            tone: DashTone.blue,
                            icon: Icons.table_restaurant_outlined,
                            label: 'Tables',
                            onTap: () => _openPage(
                              (_) => FloorPlanPage(
                                establishmentId: widget.establishmentId,
                                roleName: widget.roleName,
                              ),
                            ),
                          ),
                          DashTile(
                            tone: DashTone.purple,
                            icon: Icons.point_of_sale_outlined,
                            label: 'Caisse',
                            onTap: () => _openPage(
                              (_) => PosPage(
                                establishmentId: widget.establishmentId,
                                roleName: widget.roleName,
                              ),
                            ),
                          ),
                          DashTile(
                            tone: DashTone.red,
                            icon: Icons.inventory_2_outlined,
                            label: 'Stock',
                            onTap: () => _openPage(
                              (_) => StockPage(
                                establishmentId: widget.establishmentId,
                                roleName: widget.roleName,
                              ),
                            ),
                          ),
                        ], columns: 4),
                        const SizedBox(height: 22),
                        _moduleSection('OPÉRATIONS', Icons.sell_outlined, _operations),
                        _moduleSection('GESTION', Icons.business_center_outlined, _gestion),
                        _moduleSection('PILOTAGE', Icons.insights_outlined, _pilotage),
                        if (_administration.isNotEmpty)
                          _moduleSection(
                            'ADMINISTRATION',
                            Icons.admin_panel_settings_outlined,
                            _administration,
                          ),
                      ],
                    ),
                  ),
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
