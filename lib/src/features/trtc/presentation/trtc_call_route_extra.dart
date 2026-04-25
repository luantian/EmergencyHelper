class TrtcCallRouteExtra {
  const TrtcCallRouteExtra({
    required this.calleeUserId,
    required this.calleeName,
    this.calleeUserIds = const <String>[],
    this.calleeNames = const <String>[],
    this.calleeTitles = const <String>[],
    this.calleeDepartments = const <String>[],
    this.calleePhones = const <String>[],
    this.initialRoomId,
    this.autoJoinOnOpen = false,
    this.callId,
    this.calleeTitle,
    this.calleeDepartment,
    this.calleePhone,
  });

  final String calleeUserId;
  final String calleeName;
  final List<String> calleeUserIds;
  final List<String> calleeNames;
  final List<String> calleeTitles;
  final List<String> calleeDepartments;
  final List<String> calleePhones;
  final int? initialRoomId;
  final bool autoJoinOnOpen;
  final String? callId;
  final String? calleeTitle;
  final String? calleeDepartment;
  final String? calleePhone;

  List<String> get initialTargetUserIds {
    final source = calleeUserIds.isNotEmpty
        ? calleeUserIds
        : <String>[calleeUserId];
    final seen = <String>{};
    final result = <String>[];
    for (final item in source) {
      final normalized = item.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }
}
