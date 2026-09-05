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
}
