import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';

/// Shows [authenticated] when a Supabase session is active, [LoginPage]
/// otherwise, and reacts live to sign-in/sign-out.
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
          return authenticated(context);
        }
        return const LoginPage();
      },
    );
  }
}
