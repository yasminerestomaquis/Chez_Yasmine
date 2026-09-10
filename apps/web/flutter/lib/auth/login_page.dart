import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import 'otp_verify_page.dart';
import 'sign_up_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _sendOtp() async {
    if (_emailController.text.trim().isEmpty) {
      _showError('Saisissez votre e-mail pour recevoir un code de connexion.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerifyPage(email: _emailController.text.trim()),
        ),
      );
    } on AuthException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
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
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: AppColors.orangeLight,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/logo.png',
                          height: 88,
                          width: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Chez Yasmine',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Bonne cuisine, bon moment !',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      validator: (value) =>
                          (value == null || !value.contains('@'))
                          ? 'E-mail invalide'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mot de passe',
                      ),
                      validator: (value) => (value == null || value.length < 6)
                          ? '6 caractères minimum'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _signInWithPassword,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Se connecter'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _isSubmitting ? null : _sendOtp,
                      child: const Text('Recevoir un code par e-mail'),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SignUpPage(),
                              ),
                            ),
                      child: const Text('Créer un compte établissement'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
