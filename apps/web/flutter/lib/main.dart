import 'package:flutter/material.dart';

void main() {
  runApp(const ChezYasmineApp());
}

class ChezYasmineApp extends StatelessWidget {
  const ChezYasmineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chez Yasmine',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE07A1F))),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Image.asset('assets/logo.png', height: 36, width: 36, fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            const Text('Chez Yasmine', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: const Center(
        child: Text('Fondations en cours de mise en place.'),
      ),
    );
  }
}
