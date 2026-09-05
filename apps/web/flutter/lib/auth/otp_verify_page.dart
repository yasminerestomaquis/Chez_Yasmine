import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OtpVerifyPage extends StatefulWidget {
  const OtpVerifyPage({super.key, required this.email});

  final String email;

  @override
  State<OtpVerifyPage> createState() => _OtpVerifyPageState();
}

class _OtpVerifyPageState extends State<OtpVerifyPage> {
  final _codeController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.email,
        token: _codeController.text.trim(),
        email: widget.email,
      );
      // On success, AuthGate's onAuthStateChange listener takes over.
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
      appBar: AppBar(title: const Text('Code de connexion')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Code envoyé à ${widget.email}'),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Code à 6 chiffres'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _isSubmitting ? null : _verify,
                  child: _isSubmitting
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Valider'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
