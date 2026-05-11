/// Global participant name registry.
/// Maps userId → displayName so that call UI can show names instead of IDs.
/// Populated by the caller from contacts/trtc route extra, and by the callee
/// when call signaling data is received.
class ParticipantNameRegistry {
  ParticipantNameRegistry._();
  static final Map<String, String> _names = <String, String>{};

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

  static void clear() {
    _names.clear();
  }
}
