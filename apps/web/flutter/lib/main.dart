import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api/api_client.dart';
import 'auth/auth_gate.dart';
import 'auth/me_repository.dart';
import 'cash/cash_page.dart';
import 'catalog/catalog_page.dart';
import 'config/supabase_config.dart';
import 'customers/customers_page.dart';
import 'expenses/expenses_page.dart';
import 'losses/losses_page.dart';
import 'notifications/notifications_page.dart';
import 'pos/pos_page.dart';
import 'purchasing/purchases_page.dart';
import 'reports/reports_page.dart';
import 'stock/stock_page.dart';
import 'tables/floor_plan_page.dart';

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
      body: FutureBuilder<MyProfile>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 40),
                    const SizedBox(height: 12),
                    Text("Impossible de joindre l'API : $message", textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    if (user?.email != null) Text('Connecté en tant que ${user!.email}'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(() => _future = MeRepository(ApiClient()).fetchMe()),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }

          final profile = snapshot.data!;
          if (profile.establishments.isEmpty) {
            return const Center(child: Text('Aucun établissement associé à ce compte.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final establishment in profile.establishments)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.storefront_outlined),
                          title: Text(establishment.name),
                          subtitle: Text(establishment.role),
                        ),
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.table_restaurant_outlined),
                              label: const Text('Tables'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => FloorPlanPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.point_of_sale_outlined),
                              label: const Text('Caisse'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PosPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: const Text('Stock'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => StockPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.shopping_cart_outlined),
                              label: const Text('Achats'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PurchasesPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.people_outline),
                              label: const Text('Clients'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => CustomersPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.storefront_outlined),
                              label: const Text('Catalogue'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => CatalogPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('Dépenses'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => ExpensesPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.report_gmailerrorred_outlined),
                              label: const Text('Pertes'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => LossesPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.savings_outlined),
                              label: const Text('Caisse'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => CashPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.bar_chart_outlined),
                              label: const Text('Rapports'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => ReportsPage(establishmentId: establishment.id)),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.notifications_outlined),
                              label: const Text('Notifications'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => NotificationsPage(establishmentId: establishment.id)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
