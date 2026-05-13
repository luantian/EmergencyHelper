/// Stores a push notification route path that couldn't be navigated to
/// because the user was not logged in yet. After login, check this store
/// and navigate to the pending route instead of /home.
class PendingPushRouteStore {
  PendingPushRouteStore._();
  static final PendingPushRouteStore instance = PendingPushRouteStore._();

  String? _pendingRoutePath;

  void set(String routePath) => _pendingRoutePath = routePath;
  String? peek() => _pendingRoutePath;
  String? consume() {
    final path = _pendingRoutePath;
    _pendingRoutePath = null;
    return path;
  }
}
