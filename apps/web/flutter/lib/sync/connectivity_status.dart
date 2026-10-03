import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Live online/offline status (prompt maître §24 : « Connexion Internet : ●
/// En ligne / ○ Hors ligne »).
class ConnectivityStatus {
  static Stream<bool> get onlineStream =>
      Connectivity().onConnectivityChanged.map((results) => !results.contains(ConnectivityResult.none));

  static Future<bool> isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  /// Appelle [callback] à chaque retour de la connexion (hors ligne -> en
  /// ligne). Une erreur du plugin (absent en test, plateforme sans support) est
  /// ignorée : sans lui, l'écran garde simplement son bouton « Actualiser ».
  static StreamSubscription<bool> onReconnect(void Function() callback) {
    var wasOnline = true;
    isOnline().then((online) => wasOnline = online).catchError((Object _) => wasOnline);
    return onlineStream.listen(
      (online) {
        if (online && !wasOnline) callback();
        wasOnline = online;
      },
      onError: (Object _) {},
    );
  }
}
