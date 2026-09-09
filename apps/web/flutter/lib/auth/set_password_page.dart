import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Affiché par [AuthGate] à la place de l'application quand la session
/// active provient d'une invitation (`needs_password_setup` dans les
/// métadonnées utilisateur, posé par UsersService.invite/generateInviteLink
/// — voir docs/api/users.md) : la personne invitée est déjà connectée via le
/// lien magique, mais n'a encore jamais choisi de mot de passe pour se
/// reconnecter plus tard.
class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({super.key});

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      // `data` ne porte que le drapeau à lever : les autres métadonnées de
      // l'invitation (invited_establishment_id/invited_role_id) n'ont plus
      // d'utilité après la création du compte (lues une seule fois, à
      // l'insertion, par le déclencheur handle_new_user).
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text, data: {'needs_password_setup': false}),
      );
      // AuthGate écoute onAuthStateChange et bascule automatiquement vers
      // l'application dès que le drapeau disparaît des métadonnées.
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Définir votre mot de passe'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Vous avez été invité·e à rejoindre ${Supabase.instance.client.auth.currentUser?.email ?? "cet établissement"}. '
                    'Choisissez un mot de passe pour pouvoir vous reconnecter ensuite.',
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Mot de passe'),
                    validator: (value) => (value == null || value.length < 6) ? '6 caractères minimum' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'),
                    validator: (value) => value != _passwordController.text ? 'Les mots de passe ne correspondent pas' : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Valider'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
