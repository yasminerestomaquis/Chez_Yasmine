import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import 'stock_models.dart';
import 'stock_repository.dart';

class ProductStockHistoryPage extends StatefulWidget {
  const ProductStockHistoryPage({super.key, required this.repository, required this.productId, required this.productName});

  final StockRepository repository;
  final String productId;
  final String productName;

  @override
  State<ProductStockHistoryPage> createState() => _ProductStockHistoryPageState();
}

class _ProductStockHistoryPageState extends State<ProductStockHistoryPage> {
  late final Future<List<StockMovement>> _future = widget.repository.listMovements(widget.productId);

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: Text('Historique — ${widget.productName}')),
      body: FutureBuilder<List<StockMovement>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }
          final movements = snapshot.data!;
          if (movements.isEmpty) {
            return const Center(child: Text('Aucun mouvement enregistré.'));
          }
          return ListView.separated(
            itemCount: movements.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = movements[index];
              final sign = m.type == 'in' ? '+' : (m.type == 'adjustment' ? '=' : '-');
              return ListTile(
                title: Text('${stockMovementTypeLabels[m.type] ?? m.type} — $sign${m.quantity}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateFormat.format(m.createdAt.toLocal())),
                    if (m.reason != null && m.reason!.isNotEmpty) Text(m.reason!),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
