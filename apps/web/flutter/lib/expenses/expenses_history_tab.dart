import 'package:flutter/material.dart';

class ExpensesHistoryTab extends StatelessWidget {
  const ExpensesHistoryTab({super.key, required this.establishmentId});
  final String establishmentId;

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
