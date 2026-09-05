import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';
import 'config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
  runApp(const ChezYasmineApp());
}

class ChezYasmineApp extends StatelessWidget {
  const ChezYasmineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chez Yasmine',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE07A1F))),
      home: AuthGate(authenticated: (context) => const HomePage()),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
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
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Fondations en cours de mise en place.'),
            const SizedBox(height: 8),
            if (user?.email != null) Text('Connecté en tant que ${user!.email}'),
          ],
        ),
      ),
    );
  }
}
