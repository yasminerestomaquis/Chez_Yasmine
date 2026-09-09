import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'user_models.dart';
import 'users_repository.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late final UsersRepository _repository = UsersRepository(ApiClient(), widget.establishmentId);
  late Future<(List<TeamMember>, List<RoleOption>)> _future = _load();

  Future<(List<TeamMember>, List<RoleOption>)> _load() async {
    final team = await _repository.listTeam();
    final roles = await _repository.listRoles();
    return (team, roles);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _invite(List<RoleOption> roles) async {
    final emailController = TextEditingController();
    final fullNameController = TextEditingController();
    String? roleId = roles.firstOrNull?.id;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Inviter un utilisateur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              TextField(controller: fullNameController, decoration: const InputDecoration(labelText: 'Nom complet (optionnel)')),
              DropdownButtonFormField<String>(
                initialValue: roleId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Rôle'),
                items: [for (final role in roles) DropdownMenuItem(value: role.id, child: Text(role.name))],
                onChanged: (value) => setDialogState(() => roleId = value),
              ),
              const SizedBox(height: 8),
              const Text(
                "Un e-mail avec un lien pour choisir un mot de passe sera envoyé à cette adresse.",
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Inviter')),
          ],
        ),
      ),
    );
    if (result != true) return;
    final email = emailController.text.trim();
    if (email.isEmpty || roleId == null) return;
    try {
      await _repository.invite(
        email: email,
        roleId: roleId!,
        fullName: fullNameController.text.trim().isEmpty ? null : fullNameController.text.trim(),
      );
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invitation envoyée à $email.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs')),
      body: FutureBuilder<(List<TeamMember>, List<RoleOption>)>(
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
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _reload, child: const Text('Réessayer')),
                  ],
                ),
              ),
            );
          }
          final (team, roles) = snapshot.data!;
          return ListView(
            children: [
              if (team.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Aucun utilisateur.')),
              for (final member in team)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(member.fullName?.isNotEmpty == true ? member.fullName! : '(nom non renseigné)'),
                  subtitle: Text(member.roleName),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<(List<TeamMember>, List<RoleOption>)>(
        future: _future,
        builder: (context, snapshot) {
          final roles = snapshot.data?.$2 ?? const <RoleOption>[];
          return FloatingActionButton.extended(
            onPressed: roles.isEmpty ? null : () => _invite(roles),
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('Inviter'),
          );
        },
      ),
    );
  }
}
