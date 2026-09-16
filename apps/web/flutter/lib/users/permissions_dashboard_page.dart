import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import 'permission_grouping.dart';
import 'user_models.dart';
import 'users_repository.dart';

const double _leftColumnWidth = 220;
const double _roleColumnWidth = 108;
const double _rowHeight = 46;
const double _headerRowHeight = 64;

/// Tableau de bord "Gestion des permissions" (demande utilisateur du
/// 2026-09-16, voir docs/api/users.md) — matrice rôle × permission, cases à
/// cocher pour accorder/retirer, vert = accordée / rouge = refusée. Réservé
/// au Super Administrateur : l'entrée de navigation est masquée aux autres
/// rôles côté UsersPage, et le serveur refuse de toute façon (`roles.manage`,
/// `RolesController`) — cette page ne fait donc aucune vérification de rôle
/// elle-même, comme le reste de l'application (un 403 s'affiche normalement).
class PermissionsDashboardPage extends StatefulWidget {
  const PermissionsDashboardPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PermissionsDashboardPage> createState() =>
      _PermissionsDashboardPageState();
}

class _PermissionsDashboardPageState extends State<PermissionsDashboardPage> {
  late final UsersRepository _repository = UsersRepository(
    ApiClient(),
    widget.establishmentId,
  );

  // Un seul contrôleur par axe, partagé entre l'en-tête/la colonne figée et
  // le corps : l'en-tête et la colonne suivent l'offset du corps par
  // translation (AnimatedBuilder + Transform.translate) plutôt que par une
  // deuxième paire de Scrollable synchronisées — pas de risque de boucle de
  // synchronisation, et le corps reste la seule surface que l'utilisateur
  // fait défiler directement.
  final ScrollController _hController = ScrollController();
  final ScrollController _vController = ScrollController();

  late Future<PermissionsMatrix> _future = _load();

  /// Copie locale mutable des permissions accordées par rôle, pour un
  /// retour visuel immédiat au clic — la liste des rôles/permissions elle
  /// (la structure de la matrice) ne change pas en cours de session.
  Map<String, Set<String>>? _grantedByRole;
  final Set<String> _pendingCells = {};

  Future<PermissionsMatrix> _load() async {
    final matrix = await _repository.getPermissionsMatrix();
    _grantedByRole = {
      for (final role in matrix.roles) role.id: {...role.permissionCodes},
    };
    return matrix;
  }

  void _reload() => setState(() => _future = _load());

  @override
  void dispose() {
    _hController.dispose();
    _vController.dispose();
    super.dispose();
  }

  String _cellKey(String roleId, String code) => '$roleId:$code';

  Future<void> _toggle(String roleId, String code, bool currentlyGranted) async {
    final key = _cellKey(roleId, code);
    if (_pendingCells.contains(key)) return;
    setState(() {
      _pendingCells.add(key);
      final codes = _grantedByRole![roleId]!;
      if (currentlyGranted) {
        codes.remove(code);
      } else {
        codes.add(code);
      }
    });
    try {
      if (currentlyGranted) {
        await _repository.revokePermission(roleId, code);
      } else {
        await _repository.grantPermission(roleId, code);
      }
    } on ApiException catch (e) {
      setState(() {
        final codes = _grantedByRole![roleId]!;
        // Échec : on annule le changement optimiste.
        if (currentlyGranted) {
          codes.add(code);
        } else {
          codes.remove(code);
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _pendingCells.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion des permissions')),
      body: FutureBuilder<PermissionsMatrix>(
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _reload,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }
          final matrix = snapshot.data!;
          final rows = buildMatrixRows(matrix.permissions);
          return Column(
            children: [
              _buildLegend(),
              Expanded(
                child: _buildMatrix(matrix, rows),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 20,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: const [
          Text(
            'Les rôles sont globaux : une modification s\'applique à tout l\'établissement.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          _LegendDot(color: AppColors.green, label: 'Accordée'),
          _LegendDot(color: AppColors.alert, label: 'Refusée'),
        ],
      ),
    );
  }

  Widget _buildMatrix(PermissionsMatrix matrix, List<MatrixRow> rows) {
    final bodyWidth = matrix.roles.length * _roleColumnWidth;
    final bodyHeight = rows.length * _rowHeight;

    return Column(
      children: [
        // En-tête : coin figé + noms de rôle suivant le défilement horizontal du corps.
        SizedBox(
          height: _headerRowHeight,
          child: Row(
            children: [
              Container(
                width: _leftColumnWidth,
                height: _headerRowHeight,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  border: Border(
                    right: BorderSide(color: Color(0xFFE9E1D8)),
                    bottom: BorderSide(color: Color(0xFFE9E1D8)),
                  ),
                ),
                child: const Text(
                  'Permission',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Expanded(
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _hController,
                    builder: (context, child) {
                      final offset = _hController.hasClients
                          ? _hController.offset
                          : 0.0;
                      return Transform.translate(
                        offset: Offset(-offset, 0),
                        child: child,
                      );
                    },
                    child: Container(
                      width: bodyWidth,
                      height: _headerRowHeight,
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE9E1D8)),
                        ),
                      ),
                      child: Row(
                        children: [
                          for (final role in matrix.roles)
                            Container(
                              width: _roleColumnWidth,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                role.name,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Corps : colonne des libellés figée + grille de cases à cocher, défilement libre.
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _leftColumnWidth,
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _vController,
                    builder: (context, child) {
                      final offset = _vController.hasClients
                          ? _vController.offset
                          : 0.0;
                      return Transform.translate(
                        offset: Offset(0, -offset),
                        child: child,
                      );
                    },
                    child: SizedBox(
                      height: bodyHeight,
                      child: Column(
                        children: [for (final row in rows) _leftCellFor(row)],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _vController,
                  thumbVisibility: true,
                  notificationPredicate: (n) => n.depth == 0,
                  child: SingleChildScrollView(
                    controller: _vController,
                    child: Scrollbar(
                      controller: _hController,
                      thumbVisibility: true,
                      notificationPredicate: (n) => n.depth == 0,
                      child: SingleChildScrollView(
                        controller: _hController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: bodyWidth,
                          child: Column(
                            children: [
                              for (final row in rows)
                                _bodyRowFor(row, matrix, bodyWidth),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _leftCellFor(MatrixRow row) {
    return switch (row) {
      ModuleHeaderRow(:final label) => Container(
        height: _rowHeight,
        width: double.infinity,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: AppColors.orangeLight,
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 0.3,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      SubModuleHeaderRow(:final label) => Container(
        height: _rowHeight,
        width: double.infinity,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20, right: 12),
        color: const Color(0xFFFAF6F1),
        child: Text(
          label,
          style: const TextStyle(
            fontStyle: FontStyle.italic,
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      PermissionRow(:final permission) => Container(
        height: _rowHeight,
        width: double.infinity,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 28, right: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF2ECE4))),
        ),
        child: Tooltip(
          message: permission.description ?? permission.code,
          child: Text(
            permission.description ?? permission.code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ),
    };
  }

  Widget _bodyRowFor(
    MatrixRow row,
    PermissionsMatrix matrix,
    double bodyWidth,
  ) {
    if (row is ModuleHeaderRow || row is SubModuleHeaderRow) {
      final color = row is ModuleHeaderRow
          ? AppColors.orangeLight
          : const Color(0xFFFAF6F1);
      return Container(height: _rowHeight, width: bodyWidth, color: color);
    }
    final permission = (row as PermissionRow).permission;
    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          for (final role in matrix.roles)
            _permissionCell(role, permission.code),
        ],
      ),
    );
  }

  Widget _permissionCell(RoleMatrixEntry role, String code) {
    final granted = _grantedByRole![role.id]!.contains(code);
    final pending = _pendingCells.contains(_cellKey(role.id, code));
    return SizedBox(
      width: _roleColumnWidth,
      height: _rowHeight,
      child: Center(
        child: pending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _toggle(role.id, code, granted),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: granted ? AppColors.greenLight : AppColors.alertLight,
                  ),
                  child: Icon(
                    granted ? Icons.check : Icons.close,
                    size: 18,
                    color: granted ? AppColors.green : AppColors.alert,
                  ),
                ),
              ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
