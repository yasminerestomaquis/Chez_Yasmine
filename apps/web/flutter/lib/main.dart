import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api/api_client.dart';
import 'auth/auth_gate.dart';
import 'auth/link_confirmation_gate.dart';
import 'auth/me_repository.dart';
import 'auth/profile_cache.dart';
import 'auth/profile_loader.dart';
import 'catalog/product_photo_service.dart';
import 'common/read_cache.dart';
import 'config/supabase_config.dart';
import 'home/home_dashboard.dart';
import 'sync/global_sync_context.dart';
import 'sync/sync_queue_service.dart';
import 'sync/sync_status_bar.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  // Les photos produits sont privées et stockées sur l'appareil pour la
  // lecture hors ligne : on les efface à la déconnexion (appareil partagé).
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    if (state.event == AuthChangeEvent.signedOut) {
      ProductPhotoService.instance.clearAll();
      ReadCache.clearAll();
      ProfileCache().clear();
    }
  });
  runApp(const ChezYasmineApp());
}

class ChezYasmineApp extends StatelessWidget {
  const ChezYasmineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: GlobalSyncContext.navigatorKey,
      title: 'Chez Yasmine',
      theme: buildAppTheme(),
      home: LinkConfirmationGate(
        child: AuthGate(authenticated: (context) => const HomePage()),
      ),
      // Barre de statut de synchronisation montée UNE SEULE FOIS, au-dessus
      // de l'écran courant quel qu'il soit (`child` couvre tout le contenu
      // routé) — visible dans n'importe quel module, pas seulement les
      // écrans qui l'intégraient individuellement jusqu'ici (décision
      // utilisateur du 2026-09-13). N'affiche rien tant qu'aucun
      // établissement n'est résolu (avant connexion, ou pendant la sélection
      // d'établissement) — voir `GlobalSyncContext`.
      builder: withSyncStatusBar,
    );
  }
}

/// `MaterialApp.builder` : pose la barre de synchronisation au-dessus de
/// l'écran courant. Fonction publique pour que les tests exercent le vrai
/// montage plutôt qu'une copie.
Widget withSyncStatusBar(BuildContext context, Widget? child) => ValueListenableBuilder<String?>(
      valueListenable: GlobalSyncContext.establishmentId,
      builder: (context, establishmentId, _) => Column(
        children: [
          if (establishmentId != null)
            SyncStatusBar(
              syncQueue: SyncQueueService(ApiClient(), establishmentId),
            ),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
    );

/// Point d'entrée après connexion : charge le profil puis affiche le tableau
/// de bord du seul établissement de l'utilisateur, ou un sélecteur si plusieurs.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.loader});

  /// Injecté par les tests ; par défaut, le vrai chargement du profil.
  final ProfileLoader? loader;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ProfileLoader _loader = widget.loader ??
      ProfileLoader(
        fetch: () => MeRepository(ApiClient()).fetchMe(),
        cache: ProfileCache(),
        currentUserId: () => Supabase.instance.client.auth.currentUser?.id,
      );

  MyProfile? _profile;
  Object? _error;
  // Passe à vrai quand le serveur tarde (premier lancement : l'API gratuite se
  // réveille en 30 à 60 s) — on le dit plutôt que de laisser un cercle muet.
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  /// Copie locale d'abord (affichée tout de suite, serveur ou pas), puis
  /// rafraîchissement en arrière-plan. Sans copie (toute première connexion sur
  /// cet appareil), il faut bien attendre le serveur.
  ///
  /// Avant, ce premier écran attendait `GET /auth/me` même quand le dernier
  /// profil connu était sur l'appareil : au démarrage à froid de l'API, jusqu'à
  /// 30 à 60 s de cercle de chargement avant d'atteindre le moindre module. La
  /// copie servait déjà à ouvrir l'application hors ligne (constaté par
  /// l'utilisateur le 2026-09-13, voir docs/api/sync.md) ; elle sert maintenant
  /// aussi quand le serveur est seulement lent.
  Future<void> _start() async {
    setState(() {
      _error = null;
      _slow = false;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _profile == null && _error == null) setState(() => _slow = true);
    });

    final cached = await _loader.cachedForCurrentUser();
    if (!mounted) return;
    if (cached != null) {
      setState(() => _profile = cached);
      unawaited(_refresh());
      return;
    }
    try {
      final fresh = await _loader.fetchAndCache();
      if (!mounted) return;
      setState(() => _profile = fresh);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _refresh() async {
    final fresh = await _loader.refresh();
    final current = _profile;
    if (fresh == null || !mounted || current == null) return;
    // Rien de changé : on ne touche à rien (reconstruire ferait perdre sa
    // position à l'utilisateur). Rôle ou établissements modifiés : mise à jour.
    if (!sameProfile(fresh, current)) setState(() => _profile = fresh);
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final profile = _profile;

    if (profile == null && _error != null) {
      final error = _error!;
      final message = error is ApiException ? error.message : '$error';
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
                  onPressed: _start,
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (profile == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (_slow) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Connexion au serveur en cours…',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Au premier lancement après une période d\'inactivité, le serveur se réveille : '
                    'cela peut prendre jusqu\'à une minute.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

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
