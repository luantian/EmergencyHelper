// Global participant name registry.
// Maps userId → displayName so that call UI can show names instead of IDs.
// Populated by the caller from contacts/trtc route extra, and by the callee
// when call signaling data is received.
import 'package:shared_preferences/shared_preferences.dart';

class ParticipantNameRegistry {
  ParticipantNameRegistry._();
  static final Map<String, String> _names = <String, String>{};

  static const String _cacheKey = 'trtc_participant_names_v1';

  static void register(String userId, String name) {
    final id = userId.trim();
    final n = name.trim();
    if (id.isNotEmpty && n.isNotEmpty) {
      _names[id] = n;
    }
  }

  static void registerAll(Map<String, String> entries) {
    entries.forEach((id, name) {
      if (id.isNotEmpty && name.isNotEmpty) {
        _names[id] = name;
      }
    });
  }

  static String resolve(String userId, {String fallback = ''}) {
    final id = userId.trim();
    if (id.isEmpty) return fallback;
    return _names[id] ?? fallback;
  }

  /// Save current name map to SharedPreferences cache.
  static Future<void> saveToCache() async {
    try {
      if (_names.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final flat = <String>[];
      _names.forEach((id, name) {
        flat.add('$id\t$name');
      });
      await prefs.setStringList(_cacheKey, flat);
    } catch (_) {}
  }

  /// Load name map from SharedPreferences cache.
  static Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final flat = prefs.getStringList(_cacheKey);
      if (flat == null || flat.isEmpty) return;
      for (final entry in flat) {
        final idx = entry.indexOf('\t');
        if (idx <= 0) continue;
        final id = entry.substring(0, idx);
        final name = entry.substring(idx + 1);
        if (id.isNotEmpty && name.isNotEmpty) {
          _names[id] = name;
        }
      }
    } catch (_) {}
  }

  static void clear() {
    _names.clear();
  }
}
