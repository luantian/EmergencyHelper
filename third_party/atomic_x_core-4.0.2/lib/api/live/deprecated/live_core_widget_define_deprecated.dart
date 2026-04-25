import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:rtc_room_engine/api/common/tui_common_define.dart';
import 'package:rtc_room_engine/api/extension/tui_live_battle_manager.dart';
import 'package:rtc_room_engine/api/extension/tui_live_connection_manager.dart';
import 'package:rtc_room_engine/api/room/tui_room_define.dart';

import '../../view/live/live_core_widget.dart' as live_core_widget;

typedef OnConnectedUsersUpdated = void Function(
    List<TUIUserInfo> userList, List<TUIUserInfo> joinList, List<TUIUserInfo> leaveList);
typedef OnUserConnectionRequest = void Function(TUIUserInfo inviterUser);
typedef OnUserConnectionCancelled = void Function(TUIUserInfo inviterUser);
typedef OnUserConnectionAccepted = void Function(TUIUserInfo userInfo);
typedef OnUserConnectionRejected = void Function(TUIUserInfo userInfo);
typedef OnUserConnectionTimeout = void Function(TUIUserInfo userInfo);
typedef OnUserConnectionTerminated = void Function();
typedef OnUserConnectionExited = void Function(TUIUserInfo userInfo);
typedef OnConnectedRoomsUpdated = void Function(List<TUIConnectionUser> roomList);
typedef OnCrossRoomConnectionRequest = void Function(TUIConnectionUser roomInfo);
typedef OnCrossRoomConnectionCancelled = void Function(TUIConnectionUser roomInfo);
typedef OnCrossRoomConnectionAccepted = void Function(TUIConnectionUser roomInfo);
typedef OnCrossRoomConnectionRejected = void Function(TUIConnectionUser roomInfo);
typedef OnCrossRoomConnectionTimeout = void Function(TUIConnectionUser inviter, TUIConnectionUser invitee);
typedef OnCrossRoomConnectionExited = void Function(TUIConnectionUser roomInfo);
typedef OnRoomDismissed = void Function(String roomId);

class ConnectionObserver {
  OnConnectedUsersUpdated onConnectedUsersUpdated =
      (List<TUIUserInfo> userList, List<TUIUserInfo> joinList, List<TUIUserInfo> leaveList) {};

  OnUserConnectionRequest onUserConnectionRequest = (TUIUserInfo inviterUser) {};

  OnUserConnectionCancelled onUserConnectionCancelled = (TUIUserInfo operateUser) {};

  OnUserConnectionAccepted onUserConnectionAccepted = (TUIUserInfo invitee) {};

  OnUserConnectionRejected onUserConnectionRejected = (TUIUserInfo invitee) {};

  OnUserConnectionTimeout onUserConnectionTimeout = (TUIUserInfo hostUser) {};

  OnUserConnectionTerminated onUserConnectionTerminated = () {};

  OnUserConnectionExited onUserConnectionExited = (TUIUserInfo hostUser) {};

  OnConnectedRoomsUpdated onConnectedRoomsUpdated = (List<TUIConnectionUser> connectedUserList) {};

  OnCrossRoomConnectionRequest onCrossRoomConnectionRequest = (TUIConnectionUser inviter) {};

  OnCrossRoomConnectionCancelled onCrossRoomConnectionCancelled = (TUIConnectionUser inviter) {};

  OnCrossRoomConnectionAccepted onCrossRoomConnectionAccepted = (TUIConnectionUser invitee) {};

  OnCrossRoomConnectionRejected onCrossRoomConnectionRejected = (TUIConnectionUser invitee) {};

  OnCrossRoomConnectionTimeout onCrossRoomConnectionTimeout = (TUIConnectionUser inviter, TUIConnectionUser invitee) {};

  OnCrossRoomConnectionExited onCrossRoomConnectionExited = (TUIConnectionUser hostUser) {};

  OnRoomDismissed onRoomDismissed = (String roomId) {};

  ConnectionObserver({
    OnConnectedUsersUpdated? onConnectedUsersUpdated,
    OnUserConnectionRequest? onUserConnectionRequest,
    OnUserConnectionCancelled? onUserConnectionCancelled,
    OnUserConnectionAccepted? onUserConnectionAccepted,
    OnUserConnectionRejected? onUserConnectionRejected,
    OnUserConnectionTimeout? onUserConnectionTimeout,
    OnUserConnectionTerminated? onUserConnectionTerminated,
    OnUserConnectionExited? onUserConnectionExited,
    OnConnectedRoomsUpdated? onConnectedRoomsUpdated,
    OnCrossRoomConnectionRequest? onCrossRoomConnectionRequest,
    OnCrossRoomConnectionCancelled? onCrossRoomConnectionCancelled,
    OnCrossRoomConnectionAccepted? onCrossRoomConnectionAccepted,
    OnCrossRoomConnectionRejected? onCrossRoomConnectionRejected,
    OnCrossRoomConnectionTimeout? onCrossRoomConnectionTimeout,
    OnCrossRoomConnectionExited? onCrossRoomConnectionExited,
    OnRoomDismissed? onRoomDismissed,
  }) {
    if (onConnectedUsersUpdated != null) {
      this.onConnectedUsersUpdated = onConnectedUsersUpdated;
    }
    if (onUserConnectionRequest != null) {
      this.onUserConnectionRequest = onUserConnectionRequest;
    }
    if (onUserConnectionCancelled != null) {
      this.onUserConnectionCancelled = onUserConnectionCancelled;
    }
    if (onUserConnectionAccepted != null) {
      this.onUserConnectionAccepted = onUserConnectionAccepted;
    }
    if (onUserConnectionRejected != null) {
      this.onUserConnectionRejected = onUserConnectionRejected;
    }
    if (onUserConnectionTimeout != null) {
      this.onUserConnectionTimeout = onUserConnectionTimeout;
    }
    if (onUserConnectionTerminated != null) {
      this.onUserConnectionTerminated = onUserConnectionTerminated;
    }
    if (onUserConnectionExited != null) {
      this.onUserConnectionExited = onUserConnectionExited;
    }
    if (onConnectedRoomsUpdated != null) {
      this.onConnectedRoomsUpdated = onConnectedRoomsUpdated;
    }
    if (onCrossRoomConnectionRequest != null) {
      this.onCrossRoomConnectionRequest = onCrossRoomConnectionRequest;
    }
    if (onCrossRoomConnectionCancelled != null) {
      this.onCrossRoomConnectionCancelled = onCrossRoomConnectionCancelled;
    }
    if (onCrossRoomConnectionAccepted != null) {
      this.onCrossRoomConnectionAccepted = onCrossRoomConnectionAccepted;
    }
    if (onCrossRoomConnectionRejected != null) {
      this.onCrossRoomConnectionRejected = onCrossRoomConnectionRejected;
    }
    if (onCrossRoomConnectionTimeout != null) {
      this.onCrossRoomConnectionTimeout = onCrossRoomConnectionTimeout;
    }
    if (onCrossRoomConnectionExited != null) {
      this.onCrossRoomConnectionExited = onCrossRoomConnectionExited;
    }
    if (onRoomDismissed != null) {
      this.onRoomDismissed = onRoomDismissed;
    }
  }
}

typedef OnBattleStarted = void Function(TUIBattleInfo battleInfo);
typedef OnBattleEnded = void Function(TUIBattleInfo battleInfo);
typedef OnUserJoinBattle = void Function(String battleId, TUIBattleUser battleUser);
typedef OnUserExitBattle = void Function(String battleId, TUIBattleUser battleUser);
typedef OnBattleScoreChanged = void Function(String battleId, List<TUIBattleUser> battleUserList);
typedef OnBattleRequestReceived = void Function(String battleId, TUIBattleUser inviter, TUIBattleUser invitee);
typedef OnBattleRequestCancelled = void Function(String battleId, TUIBattleUser inviter, TUIBattleUser invitee);
typedef OnBattleRequestTimeout = void Function(String battleId, TUIBattleUser inviter, TUIBattleUser invitee);
typedef OnBattleRequestAccept = void Function(String battleId, TUIBattleUser inviter, TUIBattleUser invitee);
typedef OnBattleRequestReject = void Function(String battleId, TUIBattleUser inviter, TUIBattleUser invitee);

class BattleObserver {
  OnBattleStarted onBattleStarted = (TUIBattleInfo battleInfo) {};

  OnBattleEnded onBattleEnded = (TUIBattleInfo battleInfo) {};

  OnUserJoinBattle onUserJoinBattle = (String battleId, TUIBattleUser battleUser) {};

  OnUserExitBattle onUserExitBattle = (String battleId, TUIBattleUser battleUser) {};

  OnBattleScoreChanged onBattleScoreChanged = (String battleId, List<TUIBattleUser> battleUserList) {};

  OnBattleRequestReceived onBattleRequestReceived = (String battleId, TUIBattleUser inviter, TUIBattleUser invitee) {};

  OnBattleRequestCancelled onBattleRequestCancelled =
      (String battleId, TUIBattleUser inviter, TUIBattleUser invitee) {};

  OnBattleRequestTimeout onBattleRequestTimeout = (String battleId, TUIBattleUser inviter, TUIBattleUser invitee) {};

  OnBattleRequestAccept onBattleRequestAccept = (String battleId, TUIBattleUser inviter, TUIBattleUser invitee) {};

  OnBattleRequestReject onBattleRequestReject = (String battleId, TUIBattleUser inviter, TUIBattleUser invitee) {};

  BattleObserver({
    OnBattleStarted? onBattleStarted,
    OnBattleEnded? onBattleEnded,
    OnUserJoinBattle? onUserJoinBattle,
    OnUserExitBattle? onUserExitBattle,
    OnBattleScoreChanged? onBattleScoreChanged,
    OnBattleRequestReceived? onBattleRequestReceived,
    OnBattleRequestCancelled? onBattleRequestCancelled,
    OnBattleRequestTimeout? onBattleRequestTimeout,
    OnBattleRequestAccept? onBattleRequestAccept,
    OnBattleRequestReject? onBattleRequestReject,
  }) {
    if (onBattleStarted != null) {
      this.onBattleStarted = onBattleStarted;
    }
    if (onBattleEnded != null) {
      this.onBattleEnded = onBattleEnded;
    }
    if (onUserJoinBattle != null) {
      this.onUserJoinBattle = onUserJoinBattle;
    }
    if (onUserExitBattle != null) {
      this.onUserExitBattle = onUserExitBattle;
    }
    if (onBattleScoreChanged != null) {
      this.onBattleScoreChanged = onBattleScoreChanged;
    }
    if (onBattleRequestReceived != null) {
      this.onBattleRequestReceived = onBattleRequestReceived;
    }
    if (onBattleRequestCancelled != null) {
      this.onBattleRequestCancelled = onBattleRequestCancelled;
    }
    if (onBattleRequestTimeout != null) {
      this.onBattleRequestTimeout = onBattleRequestTimeout;
    }
    if (onBattleRequestAccept != null) {
      this.onBattleRequestAccept = onBattleRequestAccept;
    }
    if (onBattleRequestReject != null) {
      this.onBattleRequestReject = onBattleRequestReject;
    }
  }
}

typedef OnSuccess = void Function(String battleId, List<TUIBattleUser> requestedUserList);
typedef OnError = void Function(TUIError error, String message);

class BattleRequestCallback {
  String battleId;
  List<TUIBattleUser> requestedUserList;

  OnError onError = (TUIError error, String message) {};

  BattleRequestCallback({
    required this.battleId,
    required this.requestedUserList,
  });

  @override
  String toString() {
    return 'BattleRequestCallback{battleId:$battleId, requestedUserList:$TUIBattleUser, onError:$onError}';
  }
}

typedef CoGuestWidgetBuilder = live_core_widget.CoGuestWidgetBuilder;
typedef CoHostWidgetBuilder = live_core_widget.CoHostWidgetBuilder;
typedef BattleWidgetBuilder = live_core_widget.BattleWidgetBuilder;
typedef BattleContainerWidgetBuilder = Widget Function(BuildContext context, List<SeatFullInfo> seatList);

class VideoWidgetBuilder extends live_core_widget.VideoWidgetBuilder {
  BattleContainerWidgetBuilder deprecatedBattleContainerWidgetBuilder =
      (BuildContext context, List<SeatFullInfo> seatList) {
    return Container();
  };

  VideoWidgetBuilder({
    CoGuestWidgetBuilder? coGuestWidgetBuilder,
    CoHostWidgetBuilder? coHostWidgetBuilder,
    BattleWidgetBuilder? battleWidgetBuilder,
    BattleContainerWidgetBuilder? battleContainerWidgetBuilder,
  }) {
    if (coGuestWidgetBuilder != null) this.coGuestWidgetBuilder = coGuestWidgetBuilder;
    if (coHostWidgetBuilder != null) this.coHostWidgetBuilder = coHostWidgetBuilder;
    if (battleWidgetBuilder != null) this.battleWidgetBuilder = battleWidgetBuilder;
    if (battleContainerWidgetBuilder != null) deprecatedBattleContainerWidgetBuilder = battleContainerWidgetBuilder;
  }
}

class CoreState {
  RoomState roomState;
  UserState userState;
  MediaState mediaState;
  CoGuestState coGuestState;
  CoHostState coHostState;
  BattleState battleState;
  LayoutState layoutState;

  CoreState(
      {required this.roomState,
      required this.userState,
      required this.mediaState,
      required this.coGuestState,
      required this.coHostState,
      required this.battleState,
      required this.layoutState});
}

abstract class RoomState {
  ValueListenable<String> get roomId;

  ValueListenable<TUIUserInfo> get ownerInfo;

  ValueListenable<int> get maxCoGuestCount;
}

abstract class UserState {
  ValueListenable<TUIUserInfo> get selfInfo;

  ValueListenable<Set<String>> get hasAudioStreamUserList;

  ValueListenable<Set<String>> get hasVideoStreamUserList;
}

abstract class MediaState {
  ValueListenable<bool> get isMicrophoneOpened;

  ValueListenable<bool> get isMicrophoneMuted;

  ValueListenable<bool> get isCameraOpened;

  ValueListenable<bool> get isFrontCamera;

  ValueListenable<bool> get isMirrorEnable;
}

abstract class CoGuestState {
  ValueListenable<List<TUISeatInfo>> get seatList;

  ValueListenable<List<TUIUserInfo>> get connectedUserList;

  ValueListenable<Set<TUIUserInfo>> get applicantList;

  ValueListenable<Set<TUIUserInfo>> get inviteeList;
}

abstract class CoHostState {
  ValueListenable<List<TUIConnectionUser>> get connectedUserList;

  ValueListenable<List<TUIConnectionUser>> get sentConnectionRequestList;

  ValueListenable<TUIConnectionUser?> get receivedConnectionRequest;
}

abstract class BattleState {
  ValueListenable<String> get battleId;

  ValueListenable<List<TUIBattleUser>> get inviteeList;

  ValueListenable<List<TUIBattleUser>> get battlingUserList;
}

abstract class LayoutState {
  ValueListenable<bool> get pipMode;
}
