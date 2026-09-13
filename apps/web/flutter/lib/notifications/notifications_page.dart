import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import 'notification_models.dart';
import 'notifications_repository.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.establishmentId,
    required this.roleName,
  });

  final String establishmentId;

  /// Contrôle uniquement l'affichage du bouton "Effacer tout" (voir
  /// `_isSuperAdmin`) — le serveur refuse de toute façon l'action à qui n'a
  /// pas `notifications.manage`, cette vérification client est un confort
  /// d'affichage, pas la véritable protection.
  final String roleName;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final NotificationsRepository _repository = NotificationsRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<List<AppNotification>> _future = _repository.listNotifications();

  bool get _isSuperAdmin => widget.roleName == 'Super Administrateur';

  void _reload() {
    final future = _repository.listNotifications();
    future.ignore(); // see docs/api/reports.md — avoids a spurious "unhandled error" under flutter_test.
    setState(() => _future = future);
  }

  Future<void> _openNotification(AppNotification notification) async {
    if (notification.isUnread && !notification.isBroadcast) {
      try {
        await _repository.markAsRead(notification.id);
        _reload();
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      } catch (_) {
        // No offline queue for this — a read marker is low-stakes enough to just retry manually.
      }
    }
  }

  Future<void> _broadcast() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diffuser un message'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Titre *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
              ),
              TextField(
                controller: bodyController,
                decoration: const InputDecoration(
                  labelText: 'Message (optionnel)',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await _repository.broadcast(
        title: titleController.text.trim(),
        body: bodyController.text.trim(),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'envoyer le message.")),
      );
    }
  }

  Future<void> _checkLowStock() async {
    try {
      await _repository.checkLowStock();
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vérification des stocks effectuée.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de vérifier les stocks.')),
      );
    }
  }

  /// Action destructive et irréversible (suppression réelle, pas un simple
  /// marquage lu) — confirmation obligatoire, même motif que
  /// `UsersPage._removeMember`.
  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Effacer toutes les notifications ?'),
        content: const Text(
          'Toutes les notifications de l\'organisation seront définitivement supprimées, y compris celles adressées à d\'autres utilisateurs. Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Effacer tout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.clearAll();
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossible d'effacer les notifications."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Vérifier les stocks bas',
            icon: const Icon(Icons.inventory_outlined),
            onPressed: _checkLowStock,
          ),
          IconButton(
            tooltip: 'Diffuser un message',
            icon: const Icon(Icons.campaign_outlined),
            onPressed: _broadcast,
          ),
          if (_isSuperAdmin)
            IconButton(
              tooltip: 'Effacer toutes les notifications',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : '${snapshot.error}';
            return Center(child: Text(message));
          }
          final notifications = snapshot.data!;
          if (notifications.isEmpty) {
            return const Center(child: Text('Aucune notification.'));
          }
          return ListView(
            children: [
              for (final n in notifications)
                ListTile(
                  leading: Icon(
                    n.isUnread
                        ? Icons.mark_email_unread_outlined
                        : Icons.mark_email_read_outlined,
                  ),
                  title: Text(
                    n.title,
                    style: TextStyle(
                      fontWeight: n.isUnread
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '${n.body != null && n.body!.isNotEmpty ? '${n.body}\n' : ''}${dateFormat.format(n.createdAt.toLocal())}',
                  ),
                  isThreeLine: n.body != null && n.body!.isNotEmpty,
                  onTap: () => _openNotification(n),
                ),
            ],
          );
        },
      ),
    );
  }
}
