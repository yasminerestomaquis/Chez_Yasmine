import 'package:flutter/material.dart';

/// Tableau à quadrillage complet (bordures horizontales **et** verticales sur
/// chaque cellule, y compris l'en-tête) pour les listings affichés avant
/// export (Rapports > Boissons vendues/Plats vendus, Stock > Stock actif) —
/// `Table`/`TableBorder.all` plutôt que `DataTable`, qui ne trace pas de
/// séparateurs verticaux entre colonnes. Défilement horizontal explicite
/// (colonnes) ; le défilement vertical est délégué à l'`AlertDialog` appelant
/// (`scrollable: true`) plutôt qu'imbriqué ici, pour éviter le conflit de
/// contraintes classique de deux `SingleChildScrollView` d'axes opposés l'un
/// dans l'autre. Extrait de `ReportsPage._griddedSalesTable` (demande
/// utilisateur du 2026-09-25) pour être réutilisé tel quel dans `StockPage`.
Widget griddedTable(
  BuildContext context, {
  required List<String> headers,
  required List<bool> numericColumns,
  required List<List<String>> rows,
  List<String>? totalRow,
}) {
  Widget cell(String text, {required bool numeric, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        textAlign: numeric ? TextAlign.right : TextAlign.left,
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
    );
  }

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Table(
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          children: [
            for (var i = 0; i < headers.length; i++) cell(headers[i], numeric: numericColumns[i], bold: true),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              for (var i = 0; i < row.length; i++) cell(row[i], numeric: numericColumns[i]),
            ],
          ),
        if (totalRow != null)
          TableRow(
            children: [
              for (var i = 0; i < totalRow.length; i++) cell(totalRow[i], numeric: numericColumns[i], bold: true),
            ],
          ),
      ],
    ),
  );
}
