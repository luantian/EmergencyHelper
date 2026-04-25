// Copyright (c) 2025 Tencent. All rights reserved.
// Module:   CallStore @ AtomicXCore
// Function: Audio/video call management APIs for initiating, answering, rejecting, hanging up calls, group call management, and call history management.

import 'dart:async';

import 'package:atomic_x_core/api/device/device_store.dart';
import 'package:atomic_x_core/impl/common/listener_dispatcher.dart';
import 'package:flutter/foundation.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/common/future_converter.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' as engine;
import 'package:atomic_x_core/api/login/login_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info_result.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';
import '../../impl/call/call_store_converter.dart';

part '../../impl/call/call_store_impl.dart';

/// Call media type, used to specify whether to initiate an audio call or video call.
enum CallMediaType {
  /// Audio call
  audio,

  /// Video call
  video,
}

/// Call end reason, used to identify how the audio/video call ended (normal hangup, rejection, timeout, etc.).
///
/// This enum describes the various reasons why a call ended, helping developers understand how the call was terminated.
///
/// ### End Reason Description
///
/// | Reason | Description | Typical Scenario |
/// |------|-----------|----------------|
/// | `unknown` | Unknown reason | Unable to determine the end reason |
/// | `hangup` | Normal hangup | User actively hangs up the call |
/// | `reject` | Rejected | Callee rejects the incoming call |
/// | `noResponse` | No response | Callee did not answer within timeout |
/// | `offline` | Offline | Callee is offline |
/// | `lineBusy` | Line busy | Callee is already in a call |
/// | `canceled` | Canceled | Caller cancels before callee answers |
/// | `otherDeviceAccepted` | Accepted on another device | The call was picked up on another device associated with the same account. |
/// | `otherDeviceReject` | Rejected on another device | Call was rejected on another logged-in device |
/// | `endByServer` | Ended by server | Call was terminated by the server |
enum CallEndReason {
  /// Unknown reason
  unknown,

  /// Normal hangup
  hangup,

  /// Rejected
  reject,

  /// No response
  noResponse,

  /// Offline
  offline,

  /// Line busy
  lineBusy,

  /// Call was canceled
  canceled,

  /// Accepted on another device
  otherDeviceAccepted,

  /// Rejected on another device
  otherDeviceReject,

  /// Call ended by backend
  endByServer,
}

/// Call direction, used to identify whether the call is incoming, outgoing, or missed.
enum CallDirection {
  /// Unknown
  unknown,

  /// Missed call
  missed,

  /// Incoming call
  incoming,

  /// Outgoing call
  outgoing,
}

/// Call participant status, used to identify whether the participant is waiting or has answered.
enum CallParticipantStatus {
  /// No status (not in call)
  none,

  /// Waiting (calling/being called)
  waiting,

  /// Accepted
  accept,
}

/// Call parameter configuration, used to set room ID, timeout, custom data, and other parameters when initiating an audio/video call.
///
/// Configuration parameters for initiating audio/video calls, including room ID, timeout, custom data, etc.
class CallParams {
  /// Room ID, optional parameter, automatically assigned by server if not specified
  String roomId;

  /// Call timeout duration in seconds. Set to 0 to use the server-side default (typically 30s).
  int timeout;

  /// User custom data
  String userData;

  /// Chat group ID, used for group call scenarios
  String chatGroupId;

  /// Whether it is an encrypted call (no call records generated)
  bool isEphemeralCall;

  CallParams({
    this.roomId = "",
    this.timeout = 30,
    this.userData = "",
    this.chatGroupId = "",
    this.isEphemeralCall = false,
  });
}

/// Call participant information, including user ID, nickname, avatar, participation status, microphone/camera on/off status, etc.
///
/// Contains complete information about a call participant including user ID, nickname, avatar, participation status, and device states.
class CallParticipantInfo {
  /// User ID
  final String id;

  /// User nickname
  final String name;

  /// User avatar URL
  final String avatarURL;

  /// Friend remark
  final String remark;

  /// Participant status
  final CallParticipantStatus status;

  /// Whether microphone is on
  final bool isMicrophoneOpened;

  /// Whether camera is on
  final bool isCameraOpened;

  CallParticipantInfo._({
    this.id = "",
    this.name = "",
    this.avatarURL = "",
    this.remark = "",
    this.status = CallParticipantStatus.none,
    this.isMicrophoneOpened = false,
    this.isCameraOpened = false,
  });
}

/// Call information, including call ID, room ID, initiator, invitees, media type, call direction, start time, duration, and other complete information.
///
/// Contains complete information about a call session including call ID, room ID, initiator, invitees, media type, direction, timing, and duration.
class CallInfo {
  /// Call ID
  final String callId;

  /// Room ID
  final String roomId;

  /// Initiator ID
  final String inviterId;

  /// Invitee ID list
  final List<String> inviteeIds;

  /// Chat group ID
  final String chatGroupId;

  /// Call media type
  final CallMediaType? mediaType;

  /// Call result/direction
  final CallDirection result;

  /// Call start time (timestamp, seconds)
  final int startTime;

  /// Call duration (seconds)
  final int duration;

  CallInfo._({
    this.callId = "",
    this.roomId = "",
    this.inviterId = "",
    this.inviteeIds = const [],
    this.chatGroupId = "",
    this.mediaType,
    this.result = CallDirection.unknown,
    this.startTime = 0,
    this.duration = 0,
  });
}

/// Call state data, manages the real-time data state of the current call.
///
/// A comprehensive snapshot of the current call session state. This structure contains all relevant information about active calls, recent call records, participant lists, etc.
///
/// > **Note**: Call state updates automatically. Subscribe to `state` to receive real-time updates.
///
/// ### State Properties Overview
///
/// | Property | Type | Description |
/// |--------|------|-----------|
/// | `activeCall` | `ValueListenable<CallInfo>` | Current active call information |
/// | `recentCalls` | `ValueListenable<List<CallInfo>>` | Recent call records list |
/// | `cursor` | `ValueListenable<String>` | Pagination cursor |
/// | `selfInfo` | `ValueListenable<CallParticipantInfo>` | Current user's own information |
/// | `allParticipants` | `ValueListenable<List<CallParticipantInfo>>` | All participants in current call |
/// | `speakerVolumes` | `ValueListenable<Map<String, int>>` | Participant volume information |
/// | `networkQualities` | `ValueListenable<Map<String, NetworkQuality>>` | Participant network quality information |
abstract class CallState {
  /// Current active call information
  ValueListenable<CallInfo> get activeCall;

  /// Recent call records list
  ValueListenable<List<CallInfo>> get recentCalls;

  /// Pagination cursor, used to query more call records
  ValueListenable<String> get cursor;

  /// Current user's own information
  ValueListenable<CallParticipantInfo> get selfInfo;

  /// All participants in current call
  ValueListenable<List<CallParticipantInfo>> get allParticipants;

  /// Participant volume information, key is user ID, value is volume level
  ValueListenable<Map<String, int>> get speakerVolumes;

  /// Participant network quality information, key is user ID, value is network quality
  ValueListenable<Map<String, NetworkQuality>> get networkQualities;
}

/// Call events, used to receive various event notifications during a call.
class CallEventListener {
  /// Callback when a call starts, triggered when a call is successfully initiated.
  /// - [callId] : Call ID
  /// - [mediaType] : Call media type
  void Function(String callId, CallMediaType mediaType)? onCallStarted;

  /// Callback when receiving a call invitation, triggered when receiving a call invitation from another user.
  /// - [callId] : Call ID
  /// - [mediaType] : Call media type
  /// - [userData] : User custom data
  void Function(String callId, CallMediaType mediaType, String userData)? onCallReceived;

  /// Callback when a call ends, triggered when the call terminates.
  /// - [callId] : Call ID
  /// - [mediaType] : Call media type
  /// - [reason] : Call end reason
  /// - [userId] : User ID who triggered the end
  void Function(String callId, CallMediaType mediaType, CallEndReason reason, String userId)? onCallEnded;

  CallEventListener({
    this.onCallStarted,
    this.onCallReceived,
    this.onCallEnded,
  });
}

/// Audio/video call management APIs for initiating, answering, rejecting, hanging up calls, group call management, and call history management.
///
/// `CallStore` Manages all audio/video call related operations,
/// including initiating, answering, rejecting, hanging up, group call management, and call history management.
/// Audio/video call functionality is implemented through `CallStore` for real-time audio/video interaction between users. `CallStore` provides a comprehensive set of APIs to manage the entire call lifecycle.
///
/// ### Key Features
///
/// - **Create Audio/Video Calls**：Support initiating audio or video calls to one or multiple users, with configurable timeout, custom data, and other parameters
/// - **Answer/Reject Audio/Video Calls**：When receiving an incoming call invitation, you can choose to answer or reject
/// - **Hang Up Audio/Video Calls**：End the current ongoing audio/video call
/// - **Group Call Management**：Support joining existing group calls or inviting other users to join during a call
/// - **Call History Management**：Query recent call records (with pagination support), delete specified call records
/// - **Event-Driven Architecture**：Provides event listeners for call started, call received, call ended, etc.
/// - **State Subscription**：Real-time subscription to current call state, including participant list, volume information, network quality, etc.
///
/// > **Important**: Ensure the SDK is initialized before accessing the `CallStore.shared` singleton. Do not instantiate it directly, as doing so will prevent you from receiving call state updates.
///
/// > **Note**: Call state updates are delivered through the `state` publisher. Subscribe to it to receive real-time updates of call data.
///
/// ### Call Operations Overview
///
/// The following table shows the main call operations
///
/// | Feature | Method | Description |
/// |-------|------|-----------|
/// | Create Call | `calls` | Create an audio or video call to specified users |
/// | Answer Call | `accept` | Answer an incoming call |
/// | Reject Call | `reject` | Reject an incoming call |
/// | Hang Up Call | `hangup` | Hang up the current call |
/// | Join Call | `join` | Actively join a group call |
/// | Invite Users | `invite` | Invite other users to join the current call |
///
/// ### Call History Management
///
/// | Feature | Method | Description |
/// |-------|------|-----------|
/// | Query Records | `queryRecentCalls` | Query recent call records (with pagination support) |
/// | Delete Records | `deleteRecordCalls` | Delete specified call records |
///
/// ### Usage Example
///
/// ```dart
/// import 'package:atomic_x_core/atomicxcore.dart';
///
/// // Create a video call
/// final result = await CallStore.shared.calls(
///   ["mike"],
///   CallMediaType.video,
///   null,
/// );
/// ```
///
/// ## Topics
///
/// ### Get Instance
/// - [shared] : Get the CallStore singleton instance
///
/// ### Observe State and Events
/// - [state] : Reactive state containing active call, participant list, volume information, and network quality
/// - [addListener]/[removeListener] : Call event callbacks
///
/// ### Call Operations
/// - [calls] : Create a call
/// - [accept] : Answer a call
/// - [reject] : Reject a call
/// - [hangup] : Hang up a call
/// - [join] : Join a group call
/// - [invite] : Invite users to join a call
///
/// ### Call History
/// - [queryRecentCalls] : Query recent call records
/// - [deleteRecordCalls] : Delete call records
///
/// ## See Also
///
/// - [CallMediaType]
/// - [CallEndReason]
/// - [CallDirection]
/// - [CallParticipantStatus]
/// - [CallParams]
/// - [CallParticipantInfo]
/// - [CallInfo]
/// - [CallState]
/// - [CallEventListener]
abstract class CallStore {
  /// CallStore singleton instance
  static final CallStore _instance = _CallStoreImpl();

  static CallStore get shared => _instance;

  /// Current call state, including active call, participant list, volume information, network quality, etc.
  CallState get state;

  /// Create an audio or video call to specified users, supporting both one-on-one and group calls.
  ///
  /// - [participantIds] : List of callee IDs, supports single or multiple users
  /// - [mediaType] : Call media type (audio/video)
  /// - [params] : Call parameter configuration
  Future<CompletionHandler> calls(List<String> participantIds, CallMediaType mediaType, CallParams? params);

  /// Answer a call. Call this method to answer the call when receiving an incoming call invitation.
  ///
  Future<CompletionHandler> accept();

  /// Reject a call. Call this method to reject the call when receiving an incoming call invitation.
  ///
  Future<CompletionHandler> reject();

  /// Hang up and end the current ongoing call.
  ///
  Future<CompletionHandler> hangup();

  /// Join an ongoing group call using a specific call ID.
  ///
  /// - [callId] : Call ID to join
  Future<CompletionHandler> join(String callId);

  /// Invite other users to join during an ongoing call.
  ///
  /// - [participantIds] : List of invitee IDs
  /// - [params] : Call parameter configuration
  Future<CompletionHandler> invite(List<String> participantIds, CallParams? params);

  /// Query recent call records with pagination support. Pass an empty string as the initial cursor. For subsequent requests, use the cursor returned in the previous response to fetch the next page. Results are updated asynchronously in `state.recentCalls`.
  ///
  /// - [cursor] : Pagination cursor, pass empty string for first query
  /// - [count] : Query count
  Future<CompletionHandler> queryRecentCalls(String cursor, int count);

  /// Delete specified call records.
  ///
  /// - [callIdList] : List of call IDs to delete
  Future<CompletionHandler> deleteRecordCalls(List<String> callIdList);

  /// Add call event callback listener
  ///
  /// - [listener] : Listener
  void addListener(CallEventListener listener);

  /// Remove call event callback listener
  ///
  /// - [listener] : Listener
  void removeListener(CallEventListener listener);

  /// Call experimental API
  ///
  /// - [jsonMap] : JSON parameter map
  Future<void> callExperimentalAPI(Map<String, dynamic> jsonMap);
}
