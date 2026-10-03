import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Bandeau affiché au-dessus d'une liste servie depuis la copie locale : dit
/// de quand datent les données, et propose de les actualiser.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.cachedAt, this.onRefresh});

  final DateTime cachedAt;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 16, color: Colors.orange.shade900),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hors ligne — données du ${DateFormat('dd/MM HH:mm').format(cachedAt.toLocal())}',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
              ),
            ),
            if (onRefresh != null) TextButton(onPressed: onRefresh, child: const Text('Actualiser')),
          ],
        ),
      ),
    );
  }
}
