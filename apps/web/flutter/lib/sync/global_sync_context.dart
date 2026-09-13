import 'package:flutter/foundation.dart';

/// App-wide holder for the current establishment id, set once `HomeDashboard`
/// resolves it (and cleared on sign-out by `AuthGate`) — lets the single,
/// globally-mounted `SyncStatusBar` (see `main.dart`) know which
/// establishment's offline queue to show without threading the id through
/// every route pushed on top of the dashboard.
class GlobalSyncContext {
  GlobalSyncContext._();

  static final ValueNotifier<String?> establishmentId = ValueNotifier(null);
}
