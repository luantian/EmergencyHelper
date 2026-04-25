import 'dart:collection';

class ListenerDispatcher<T> {
  final _listeners = HashSet<T>();

  void addListener(T listener) {
    if (listener == null) return;
    _listeners.add(listener);
  }

  void removeListener(T listener) {
    if (listener == null) return;
    _listeners.remove(listener);
  }

  void notify(void Function(T) block) {
    final activeListeners = _listeners.toSet();
    for (final listener in activeListeners) {
      block(listener);
    }
  }

  void cleanup() {
    _listeners.clear();
  }
}