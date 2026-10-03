import 'package:flutter/widgets.dart';

/// App-wide holder for the current establishment id, set once `HomeDashboard`
/// resolves it (and cleared on sign-out by `AuthGate`) — lets the single,
/// globally-mounted `SyncStatusBar` (see `main.dart`) know which
/// establishment's offline queue to show without threading the id through
/// every route pushed on top of the dashboard.
class GlobalSyncContext {
  GlobalSyncContext._();

  static final ValueNotifier<String?> establishmentId = ValueNotifier(null);

  /// Clé du Navigator de l'application : la barre de synchronisation est montée
  /// AU-DESSUS du Navigator (`MaterialApp.builder`), son propre contexte ne
  /// permet donc pas d'ouvrir une boîte de dialogue.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}
