import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Traite un lien d'invitation/réinitialisation construit par
/// `SupabaseAdminService` (`?token_hash=&type=`) *avant* d'afficher [child]
/// (normalement `AuthGate`).
///
/// Pourquoi ne pas simplement pointer vers le lien Supabase
/// `/auth/v1/verify?token=...` habituel : ce lien est à usage unique, et les
/// applications de messagerie visitent automatiquement tout lien partagé
/// pour en générer un aperçu — confirmé en conditions réelles le
/// 2026-09-09 (journaux Supabase) : WhatsApp avait consommé le jeton par un
/// simple GET avant même que la personne concernée ne clique elle-même,
/// la laissant sur l'écran de connexion classique sans jamais comprendre
/// pourquoi. En pointant plutôt vers cette page de l'application (qui n'a
/// aucun effet de bord — juste du HTML/JS statique) et en appelant
/// `verifyOTP` nous-mêmes uniquement quand du code Dart s'exécute
/// réellement dans un navigateur, un robot d'aperçu qui ne charge jamais
/// JavaScript ne consomme plus jamais le jeton à notre place.
class LinkConfirmationGate extends StatefulWidget {
  const LinkConfirmationGate({super.key, required this.child});

  final Widget child;

  @override
  State<LinkConfirmationGate> createState() => _LinkConfirmationGateState();
}

class _LinkConfirmationGateState extends State<LinkConfirmationGate> {
  bool _isVerifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final tokenHash = Uri.base.queryParameters['token_hash'];
    final typeParam = Uri.base.queryParameters['type'];
    if (tokenHash != null && typeParam != null) {
      _isVerifying = true;
      _verify(tokenHash, typeParam);
    }
  }

  Future<void> _verify(String tokenHash, String typeParam) async {
    final type = switch (typeParam) {
      'invite' => OtpType.invite,
      'recovery' => OtpType.recovery,
      _ => null,
    };
    if (type == null) {
      setState(() {
        _isVerifying = false;
        _error = 'Lien invalide.';
      });
      return;
    }
    try {
      await Supabase.instance.client.auth.verifyOTP(type: type, tokenHash: tokenHash);
      // AuthGate réagit à onAuthStateChange une fois la session établie —
      // aucune navigation manuelle nécessaire ici.
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Ce lien a expiré ou a déjà été utilisé (${e.message}). Demandez-en un nouveau.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isVerifying) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => setState(() => _error = null), child: const Text('Continuer')),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
