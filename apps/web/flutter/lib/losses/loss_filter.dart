import 'loss_models.dart';

/// Rôles portant `losses.edit` (voir supabase/seed/001_roles_permissions.sql) —
/// modifier/supprimer une perte déjà enregistrée. Comparaison par nom de rôle,
/// faute de code de permission exposé côté client (même limite que
/// `canRefundSale`) ; le serveur refuse de toute façon les autres (403).
const _editRoles = {'Super Administrateur', 'Gérant', 'Serveur'};
bool canEditLosses(String roleName) => _editRoles.contains(roleName);

/// Pertes d'un jour donné (`day` nul : toutes les dates) — le jour civil est
/// évalué en heure locale, comme l'affichage.
List<Loss> lossesOnDay(List<Loss> losses, DateTime? day) {
  if (day == null) return losses;
  return losses.where((l) {
    final local = l.createdAt.toLocal();
    return local.year == day.year && local.month == day.month && local.day == day.day;
  }).toList();
}

/// Nombre total de bouteilles perdues (somme des quantités, remplace le
/// nombre de lignes — demande utilisateur du 2026-09-22) et valeur estimée
/// totale de [losses], affichés en gras au-dessus du listing.
({double count, double totalValue}) lossTotals(List<Loss> losses) => (
      count: losses.fold(0.0, (sum, l) => sum + l.quantity),
      totalValue: losses.fold(0.0, (sum, l) => sum + l.estimatedValue),
    );
