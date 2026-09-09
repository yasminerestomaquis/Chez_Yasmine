import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import 'user_models.dart';
import 'users_repository.dart';

enum _InviteAction { sendEmail, copyLink }

class _InviteFormResult {
  const _InviteFormResult({required this.action, required this.email, required this.roleId, this.fullName});

  final _InviteAction action;
  final String email;
  final String roleId;
  final String? fullName;
}

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
    final result = await showDialog<_InviteFormResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          _InviteFormResult? buildResult(_InviteAction action) {
            final email = emailController.text.trim();
            if (email.isEmpty || roleId == null) return null;
            return _InviteFormResult(
              action: action,
              email: email,
              roleId: roleId!,
              fullName: fullNameController.text.trim().isEmpty ? null : fullNameController.text.trim(),
            );
          }

          return AlertDialog(
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
                  "« Inviter » envoie un e-mail avec un lien pour choisir un mot de passe. "
                  "« Copier le lien » génère ce même lien sans passer par e-mail (utile si le quota d'envoi de Supabase "
                  "est atteint) — vous le transmettez alors vous-même par le canal de votre choix.",
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(buildResult(_InviteAction.copyLink)),
                child: const Text('Copier le lien'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(buildResult(_InviteAction.sendEmail)),
                child: const Text('Inviter'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    try {
      if (result.action == _InviteAction.sendEmail) {
        await _repository.invite(email: result.email, roleId: result.roleId, fullName: result.fullName);
        _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invitation envoyée à ${result.email}.')));
      } else {
        final link = await _repository.generateInviteLink(
          email: result.email,
          roleId: result.roleId,
          fullName: result.fullName,
        );
        await Clipboard.setData(ClipboardData(text: link));
        _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lien copié — transmettez-le à ${result.email} par le canal de votre choix.')),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> _changeRole(TeamMember member, List<RoleOption> roles) async {
    String roleId = member.roleId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Modifier le rôle — ${member.fullName ?? member.userId}'),
          content: DropdownButtonFormField<String>(
            initialValue: roleId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Rôle'),
            items: [for (final role in roles) DropdownMenuItem(value: role.id, child: Text(role.name))],
            onChanged: (value) => setDialogState(() => roleId = value ?? roleId),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Valider')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.changeRole(member.membershipId, roleId);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _removeMember(TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer cet utilisateur ?'),
        content: Text(
          '« ${member.fullName ?? member.userId} » perdra son accès à cet établissement. '
          "Son compte n'est pas supprimé — il pourra rester utilisable sur un autre établissement.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Retirer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.removeMember(member.membershipId);
      _reload();
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
                  subtitle: Text(member.userId == _currentUserId ? '${member.roleName} (vous)' : member.roleName),
                  trailing: member.userId == _currentUserId
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Modifier le rôle',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _changeRole(member, roles),
                            ),
                            IconButton(
                              tooltip: 'Retirer',
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: () => _removeMember(member),
                            ),
                          ],
                        ),
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
