import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/global_sync_context.dart';
import 'login_page.dart';
import 'set_password_page.dart';

/// Shows [authenticated] when a Supabase session is active, [LoginPage]
/// otherwise, and reacts live to sign-in/sign-out. A session that came from
/// an invitation (module Utilisateurs, docs/api/users.md) carries
/// `needs_password_setup: true` in the user's metadata — until that flag is
/// cleared, [SetPasswordPage] is shown instead of [authenticated], since the
/// invited person is connected via a one-time link but has never chosen a
/// password to sign back in with later.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.authenticated});

  final WidgetBuilder authenticated;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          final needsPasswordSetup = Supabase.instance.client.auth.currentUser?.userMetadata?['needs_password_setup'] == true;
          if (needsPasswordSetup) return const SetPasswordPage();
          return authenticated(context);
        }
        // Déconnexion : la barre de synchronisation globale ne doit plus
        // afficher le statut de l'établissement de la session précédente.
        // Différé après la frame courante — modifier le ValueNotifier
        // pendant le build() de ce widget notifierait immédiatement le
        // ValueListenableBuilder de main.dart, qui est un ANCÊTRE de cet
        // arbre (son builder englobe AuthGate) : le reconstruire pendant que
        // le build de son propre descendant est encore en cours lèverait
        // une exception Flutter.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => GlobalSyncContext.establishmentId.value = null,
        );
        return const LoginPage();
      },
    );
  }
}
