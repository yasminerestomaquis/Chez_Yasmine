import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _prefsKey = 'chez_yasmine_device_id';

/// A stable per-browser-profile identifier — required on every sync
/// operation (prompt maître §26) to trace which device produced it.
Future<String> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_prefsKey);
  if (existing != null) return existing;
  final generated = const Uuid().v4();
  await prefs.setString(_prefsKey, generated);
  return generated;
}
