import 'package:flutter/material.dart';

class PayrollTab extends StatelessWidget {
  const PayrollTab({super.key, required this.establishmentId});
  final String establishmentId;

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
