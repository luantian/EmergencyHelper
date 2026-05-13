import 'package:flutter/foundation.dart';

/// Call phase state machine.
/// Transitions:
///   idle → outgoingRinging (calls() sent, waiting for answer)
///   idle → incomingRinging (onCallReceived)
///   outgoingRinging → connecting (callee accepted, media negotiation)
///   incomingRinging → connecting (local accepted, media negotiation)
///   connecting → inCall (onCallBegin)
///   any → idle (onCallEnd / onCallNotConnected)
enum CallPhase {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  inCall,
}

/// Immutable snapshot of a call session at a given phase.
@immutable
class CallSession {
  const CallSession({
    required this.phase,
    this.callId = '',
    this.mediaType = '',
    this.remoteUserId = '',
    this.inviterId = '',
    this.inviteeIds = const <String>[],
    this.callerName = '',
    this.calleeNames = const <String>[],
  });

  final CallPhase phase;
  final String callId;
  final String mediaType;
  final String remoteUserId;
  final String inviterId;
  final List<String> inviteeIds;
  final String callerName;
  final List<String> calleeNames;

  bool get isIdle => phase == CallPhase.idle;
  bool get isRinging =>
      phase == CallPhase.incomingRinging ||
      phase == CallPhase.outgoingRinging;
  bool get isInCall => phase == CallPhase.inCall;

  CallSession copyWith({
    CallPhase? phase,
    String? callId,
    String? mediaType,
    String? remoteUserId,
    String? inviterId,
    List<String>? inviteeIds,
    String? callerName,
    List<String>? calleeNames,
  }) {
    return CallSession(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      mediaType: mediaType ?? this.mediaType,
      remoteUserId: remoteUserId ?? this.remoteUserId,
      inviterId: inviterId ?? this.inviterId,
      inviteeIds: inviteeIds ?? this.inviteeIds,
      callerName: callerName ?? this.callerName,
      calleeNames: calleeNames ?? this.calleeNames,
    );
  }

  @override
  String toString() {
    return 'CallSession(phase=$phase, callId=$callId, mediaType=$mediaType, '
        'remoteUserId=$remoteUserId, inviterId=$inviterId, callerName=$callerName)';
  }
}

/// Manages the current call session with phase transitions.
class CallSessionManager {
  CallSessionManager._();

  static final CallSessionManager instance = CallSessionManager._();

  CallSession _current = const CallSession(phase: CallPhase.idle);

  CallSession get current => _current;

  /// Reactive notifier for the current call phase.
  final ValueNotifier<CallPhase> phaseNotifier =
      ValueNotifier<CallPhase>(CallPhase.idle);

  void _notifyPhaseChanged() {
    phaseNotifier.value = _current.phase;
  }

  /// Transition to idle (end any active call).
  void resetToIdle() {
    debugPrint('[CallSessionManager] resetToIdle from ${_current.phase}');
    _current = const CallSession(phase: CallPhase.idle);
    _notifyPhaseChanged();
  }

  /// Transition: idle → incomingRinging
  void markIncomingCall({
    required String callId,
    required String callerId,
    required String mediaType,
    String callerName = '',
  }) {
    debugPrint(
      '[CallSessionManager] idle → incomingRinging '
      'callId=$callId caller=$callerId media=$mediaType name=$callerName',
    );
    _current = CallSession(
      phase: CallPhase.incomingRinging,
      callId: callId,
      mediaType: mediaType,
      remoteUserId: callerId,
      inviterId: callerId,
      callerName: callerName,
    );
    _notifyPhaseChanged();
  }

  /// Transition: idle → outgoingRinging
  void markOutgoingCall({
    required String callId,
    required String mediaType,
    required String inviterId,
    required List<String> inviteeIds,
    List<String> calleeNames = const <String>[],
  }) {
    debugPrint(
      '[CallSessionManager] idle → outgoingRinging '
      'callId=$callId media=$mediaType inviter=$inviterId',
    );
    _current = CallSession(
      phase: CallPhase.outgoingRinging,
      callId: callId,
      mediaType: mediaType,
      inviterId: inviterId,
      inviteeIds: inviteeIds,
      remoteUserId: inviteeIds.isNotEmpty ? inviteeIds.first : '',
      calleeNames: calleeNames,
    );
    _notifyPhaseChanged();
  }

  /// Transition: ringing → connecting (local or remote accepted)
  void markConnecting({String? callId}) {
    debugPrint(
      '[CallSessionManager] ${_current.phase} → connecting',
    );
    _current = _current.copyWith(
      phase: CallPhase.connecting,
      callId: callId ?? _current.callId,
    );
    _notifyPhaseChanged();
  }

  /// Transition: connecting → inCall
  void markInCall({String? callId}) {
    debugPrint(
      '[CallSessionManager] ${_current.phase} → inCall',
    );
    _current = _current.copyWith(
      phase: CallPhase.inCall,
      callId: callId ?? _current.callId,
    );
    _notifyPhaseChanged();
  }

  /// Update callId in current session (e.g., after onCallReceived provides the real ID).
  void updateCallId(String callId) {
    if (callId.isNotEmpty && _current.callId != callId) {
      debugPrint('[CallSessionManager] updating callId: "${_current.callId}" → "$callId"');
      _current = _current.copyWith(callId: callId);
    }
  }

  /// Check if the current session matches the given callId.
  bool matchesCallId(String callId) {
    return _current.callId == callId && !_current.isIdle;
  }

  /// Whether this is an incoming call on this device.
  bool get isIncomingRinging => _current.phase == CallPhase.incomingRinging;

  /// Whether this is an outgoing call from this device.
  bool get isOutgoingRinging => _current.phase == CallPhase.outgoingRinging;
}
