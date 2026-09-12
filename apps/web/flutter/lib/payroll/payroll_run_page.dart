import 'package:flutter/material.dart';

class PayrollRunPage extends StatelessWidget {
  const PayrollRunPage({super.key, required this.establishmentId});
  final String establishmentId;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Préparer la paie')));
}
