import 'package:flutter/material.dart';

class ExpensesOverviewTab extends StatelessWidget {
  const ExpensesOverviewTab({super.key, required this.establishmentId});
  final String establishmentId;

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
