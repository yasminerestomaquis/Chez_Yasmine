import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api/api_client.dart';
import 'auth/auth_gate.dart';
import 'auth/link_confirmation_gate.dart';
import 'auth/me_repository.dart';
import 'config/supabase_config.dart';
import 'home/home_dashboard.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  runApp(const ChezYasmineApp());
}

class ChezYasmineApp extends StatelessWidget {
  const ChezYasmineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chez Yasmine',
      theme: buildAppTheme(),
      home: LinkConfirmationGate(
        child: AuthGate(authenticated: (context) => const HomePage()),
      ),
    );
  }
}

/// Point d'entrée après connexion : charge le profil puis affiche le tableau
/// de bord du seul établissement de l'utilisateur, ou un sélecteur si plusieurs.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<MyProfile> _future;

  @override
  void initState() {
    super.initState();
    _future = MeRepository(ApiClient()).fetchMe();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return FutureBuilder<MyProfile>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException
              ? (snapshot.error as ApiException).message
              : '${snapshot.error}';
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      "Impossible de joindre l'API : $message",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    if (user?.email != null)
                      Text('Connecté en tant que ${user!.email}'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(
                        () => _future = MeRepository(ApiClient()).fetchMe(),
                      ),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final profile = snapshot.data!;
        if (profile.establishments.isEmpty) {
          return const Scaffold(
            body: Center(
              child: Text('Aucun établissement associé à ce compte.'),
            ),
          );
        }

        if (profile.establishments.length == 1) {
          final establishment = profile.establishments.single;
          return HomeDashboard(
            establishmentId: establishment.id,
            establishmentName: establishment.name,
            roleName: establishment.role,
          );
        }

        return _EstablishmentPicker(establishments: profile.establishments);
      },
    );
  }
}

/// Rare cas d'un compte rattaché à plusieurs établissements : un sélecteur
/// simple avant d'entrer dans le tableau de bord de l'un d'eux.
class _EstablishmentPicker extends StatelessWidget {
  const _EstablishmentPicker({required this.establishments});

  final List<MyEstablishment> establishments;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choisir un établissement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final establishment in establishments)
            Card(
              child: ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(establishment.name),
                subtitle: Text(establishment.role),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HomeDashboard(
                      establishmentId: establishment.id,
                      establishmentName: establishment.name,
                      roleName: establishment.role,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
