// ignore_for_file: unreachable_switch_default
import 'dart:convert';

import 'package:atomic_x_core/impl/common/future_converter.dart';
import 'package:atomic_x_core/impl/room/room_store_factory.dart';
import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import '../common/listener_dispatcher.dart';
import '../common/log.dart';
import 'room_store_converter.dart';

class _RoomStateImpl implements RoomState {
  final ValueNotifier<List<RoomInfo>> scheduledRoomListValue = ValueNotifier<List<RoomInfo>>([]);
  final ValueNotifier<String> scheduledRoomListCursorValue = ValueNotifier<String>('');
  final ValueNotifier<RoomInfo?> currentRoomValue = ValueNotifier<RoomInfo?>(null);

  @override
  ValueListenable<List<RoomInfo>> get scheduledRoomList => scheduledRoomListValue;

  @override
  ValueListenable<String> get scheduledRoomListCursor => scheduledRoomListCursorValue;

  @override
  ValueListenable<RoomInfo?> get currentRoom => currentRoomValue;
}

class RoomStoreImpl extends RoomStore {
  static final RoomStoreImpl shared = RoomStoreImpl._();

  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUIConferenceListManager _roomListManager;
  late final TUIConferenceInvitationManager _invitationManager;
  late final TUIRoomObserver _roomObserver;
  late final TUIConferenceListManagerObserver _roomListObserver;
  late final TUIConferenceInvitationObserver _invitationObserver;
  final _listenerDispatcher = ListenerDispatcher<RoomListener>();

  final int _fetchListCount = 20;

  final Log _log = Log.getRoomLog('RoomStoreImpl');

  // API
  static const String keyCreateAndJoinRoom = 'roomStore.createAndJoinRoom';
  static const String keyJoinRoom = 'roomStore.joinRoom';
  static const String keyLeaveRoom = 'roomStore.leaveRoom';
  static const String keyEndRoom = 'roomStore.endRoom';
  static const String keyUpdateRoomInfo = 'roomStore.updateRoomInfo';
  static const String keyGetRoomInfo = 'roomStore.getRoomInfo';

  // State
  static const String keyOnCurrentRoomChanged = 'roomState.onCurrentRoomChanged';

  // Listener
  static const String keyOnRoomEnded = 'roomListener.onRoomEnded';

  RoomStoreImpl._() {
    _roomListManager = _roomEngine.getExtension(TUIExtensionType.conferenceListManager);
    _invitationManager = _roomEngine.getExtension(TUIExtensionType.conferenceInvitationManager);
    _initAndAddObserver();
  }

  final _roomState = _RoomStateImpl();

  @override
  RoomState get state => _roomState;

  @override
  void addRoomListener(RoomListener listener) {
    _listenerDispatcher.addListener(listener);
  }

  @override
  void removeRoomListener(RoomListener listener) {
    _listenerDispatcher.removeListener(listener);
  }

  @override
  Future<ListResultCompletionHandler<RoomInfo>> getScheduledRoomList(String? cursor) async {
    final cursorValue = cursor ?? "";
    final result = await _roomListManager.fetchScheduledConferenceList(
        [TUIConferenceStatus.notStarted, TUIConferenceStatus.running], cursorValue, _fetchListCount);
    final resultHandler = ListResultCompletionHandler<RoomInfo>();
    resultHandler.errorCode = result.code.rawValue;
    resultHandler.errorMessage = result.message;
    if (result.code == TUIError.success) {
      final roomInfoList = result.data?.conferenceInfoList
          .map((conferenceInfo) => conferenceInfo.toRoomInfo())
          .whereType<RoomInfo>()
          .toList();
      final nextCursor = result.data?.cursor;
      resultHandler.data = roomInfoList;
      resultHandler.cursor = nextCursor;
      _roomState.scheduledRoomListCursorValue.value = nextCursor ?? "";
      if (cursorValue.isEmpty) {
        _roomState.scheduledRoomListValue.value = roomInfoList ?? [];
      } else {
        _roomState.scheduledRoomListValue.value = [
          ..._roomState.scheduledRoomListValue.value,
          ...roomInfoList ?? [],
        ];
      }
    }
    return resultHandler;
  }

  @override
  Future<ListResultCompletionHandler<RoomUser>> getScheduledAttendees({
    required String roomID,
    required String? cursor,
  }) async {
    final result = await _roomListManager.fetchAttendeeList(roomID, cursor ?? "", _fetchListCount);
    final resultHandler = ListResultCompletionHandler<RoomUser>();
    resultHandler.errorCode = result.code.rawValue;
    resultHandler.errorMessage = result.message;
    if (result.code == TUIError.success) {
      final userInfoList =
          result.data?.scheduleAttendees.map((userInfo) => userInfo.toRoomUser()).whereType<RoomUser>().toList();
      final nextCursor = result.data?.cursor;
      resultHandler.data = userInfoList;
      resultHandler.cursor = nextCursor;

      final currentRoom = _roomState.currentRoom.value;
      if (currentRoom != null && currentRoom.roomID == roomID) {
        _roomState.currentRoomValue.value = currentRoom.copyWith(
          scheduleAttendees: userInfoList ?? [],
        );
      }

      final scheduledList = _roomState.scheduledRoomList.value;
      final index = scheduledList.indexWhere((room) => room.roomID == roomID);
      if (index != -1) {
        scheduledList[index].scheduleAttendees = userInfoList ?? [];
        _roomState.scheduledRoomListValue.value = [...scheduledList];
      }
    }
    return resultHandler;
  }

  @override
  Future<CompletionHandler> scheduleRoom({
    required String roomID,
    required ScheduleRoomOptions options,
  }) async {
    final conferenceInfo = options.toEngineConferenceInfo(roomID);
    final result = await _roomListManager.scheduleConference(conferenceInfo);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> updateScheduledRoom({
    required String roomID,
    required ScheduleRoomOptions options,
    required List<ScheduleRoomOptionsModifyFlag> modifyFlagList,
  }) async {
    final roomName = modifyFlagList.contains(ScheduleRoomOptionsModifyFlag.roomName) ? options.roomName : null;
    final startTime =
        modifyFlagList.contains(ScheduleRoomOptionsModifyFlag.scheduleStartTime) ? options.scheduleStartTime : null;
    final endTime =
        modifyFlagList.contains(ScheduleRoomOptionsModifyFlag.scheduleEndTime) ? options.scheduleEndTime : null;
    final result = await _roomListManager.updateConferenceInfo(roomID,
        roomName: roomName, scheduleStartTime: startTime, scheduleEndTime: endTime);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> addScheduledAttendees({
    required String roomID,
    required List<String> userIDList,
  }) async {
    final result = await _roomListManager.addAttendeesByAdmin(roomID, userIDList);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> removeScheduledAttendees({
    required String roomID,
    required List<String> userIDList,
  }) async {
    final result = await _roomListManager.removeAttendeesByAdmin(roomID, userIDList);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> cancelScheduledRoom(String roomID) async {
    final result = await _roomListManager.cancelConference(roomID);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> createAndJoinRoom({
    required String roomID,
    required RoomType roomType,
    required CreateRoomOptions options,
  }) async {
    RoomStoreFactory.shared.beforeEnterRoom(roomID);
    final result = await _roomEngine.call(
      keyCreateAndJoinRoom,
      jsonEncode({
        'roomID': roomID,
        'roomType': roomType.value,
        'options': {
          'roomName': options.roomName,
          'isAllMicrophoneDisabled': options.isAllMicrophoneDisabled,
          'isAllCameraDisabled': options.isAllCameraDisabled,
          'isAllScreenShareDisabled': options.isAllScreenShareDisabled,
          'isAllMessageDisabled': options.isAllMessageDisabled,
          'password': options.password,
        },
      }),
    );
    if (result.code == TUIError.success) {
      final roomInfo = RoomInfoFromJson.fromJsonString(result.data);
      if (roomInfo != null) {
        _roomState.currentRoomValue.value = roomInfo;
        RoomStoreFactory.shared.afterEnterRoom(roomInfo);
      }
    }
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> joinRoom({
    required String roomID,
    required RoomType roomType,
    String? password = "",
  }) async {
    RoomStoreFactory.shared.beforeEnterRoom(roomID);
    final result = await _roomEngine.call(
      keyJoinRoom,
      jsonEncode({
        'roomID': roomID,
        'roomType': roomType.value,
        'password': password ?? '',
      }),
    );
    if (result.code == TUIError.success) {
      final roomInfo = RoomInfoFromJson.fromJsonString(result.data);
      if (roomInfo != null) {
        _roomState.currentRoomValue.value = roomInfo;
        RoomStoreFactory.shared.afterEnterRoom(roomInfo);
      }
    }
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> leaveRoom() async {
    final roomID = _roomState.currentRoom.value?.roomID;
    final result = await _roomEngine.call(
      keyLeaveRoom,
      jsonEncode({}),
    );
    if (result.code == TUIError.success) {
      RoomStoreFactory.shared.leaveRoom(roomID ?? '');
    }
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> endRoom() async {
    final roomID = _roomState.currentRoom.value?.roomID;
    final result = await _roomEngine.call(
      keyEndRoom,
      jsonEncode({}),
    );
    if (result.code == TUIError.success) {
      RoomStoreFactory.shared.leaveRoom(roomID ?? "");
    }
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> updateRoomInfo({
    required String roomID,
    required UpdateRoomOptions options,
    required List<UpdateRoomOptionsModifyFlag> modifyFlagList,
  }) async {
    int modifyFlag = 0;
    for (final flag in modifyFlagList) {
      modifyFlag |= flag.value;
    }

    final result = await _roomEngine.call(
      keyUpdateRoomInfo,
      jsonEncode({
        'roomID': roomID,
        'modifyFlag': modifyFlag,
        'options': {
          'roomName': options.roomName,
          'password': options.password,
        },
      }),
    );
    return handleCallback(result);
  }

  @override
  Future<GetRoomInfoCompletionHandler> getRoomInfo(String roomID) async {
    final resultHandler = GetRoomInfoCompletionHandler();
    final result = await _roomEngine.call(
      keyGetRoomInfo,
      jsonEncode({'roomID': roomID}),
    );
    if (result.code != TUIError.success) {
      resultHandler.errorCode = result.code.rawValue;
      resultHandler.errorMessage = result.message;
      return resultHandler;
    }
    resultHandler.roomInfo = RoomInfoFromJson.fromJsonString(result.data);
    return resultHandler;
  }

  @override
  Future<ListResultCompletionHandler<RoomCall>> getPendingCalls({
    required String roomID,
    required String? cursor,
  }) async {
    final cursorValue = cursor ?? "";
    final result = await _invitationManager.getInvitationList(roomID, cursorValue, _fetchListCount);
    final resultHandler = ListResultCompletionHandler<RoomCall>();
    resultHandler.errorCode = result.code.rawValue;
    resultHandler.errorMessage = result.message;
    if (result.code == TUIError.success) {
      final invitationList = result.data?.invitationList.map((invitation) => invitation.toRoomCall()).toList();
      resultHandler.data = invitationList;
      resultHandler.cursor = result.data?.cursor;
    }
    return resultHandler;
  }

  @override
  Future<CallUserToRoomCompletionHandler> callUserToRoom({
    required String roomID,
    required List<String> userIDList,
    int timeout = 0,
    String? extensionInfo,
  }) async {
    final result = await _invitationManager.inviteUsers(roomID, userIDList, timeout, extensionInfo ?? "");
    final resultHandler = CallUserToRoomCompletionHandler();
    resultHandler.errorCode = result.code.rawValue;
    resultHandler.errorMessage = result.message;
    if (result.code == TUIError.success) {
      final resultMap = result.data?.resultMap.map((key, value) => MapEntry(key, value.toRoomCallResult()));
      resultHandler.data = resultMap;
    }
    return resultHandler;
  }

  @override
  Future<CompletionHandler> cancelCall({
    required String roomID,
    required List<String> userIDList,
  }) async {
    final result = await _invitationManager.cancelInvitation(roomID, userIDList);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> acceptCall(String roomID) async {
    final result = await _invitationManager.accept(roomID);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> rejectCall({
    required String roomID,
    required CallRejectionReason reason,
  }) async {
    final result = await _invitationManager.reject(roomID, reason.toEngineRejectedReason());
    return handleCallback(result);
  }

  @override
  void reset() {
    _roomState.scheduledRoomListValue.value = [];
    _roomState.scheduledRoomListCursorValue.value = "";
    _roomState.currentRoomValue.value = RoomInfo();
  }
}

extension RoomStoreImplObserver on RoomStoreImpl {
  void _initAndAddObserver() {
    _roomObserver = TUIRoomObserver(
      on: (key, data) => _on(key, data),
    );
    _roomListObserver = TUIConferenceListManagerObserver(
      onConferenceScheduled: (conferenceInfo) => _onConferenceScheduled(conferenceInfo),
      onConferenceWillStart: (conferenceInfo) => _onConferenceWillStart(conferenceInfo),
      onConferenceDidCancelled: (conferenceInfo, reason, operateUser) =>
          _onConferenceDidCancelled(conferenceInfo, reason, operateUser),
      onConferenceInfoChanged: (conferenceInfo, modifyFlagList) =>
          _onConferenceInfoChanged(conferenceInfo, modifyFlagList),
      onScheduleAttendeesUpdated: (conferenceInfo, leftUsers, joinedUsers) =>
          _onScheduleAttendeesUpdated(conferenceInfo, leftUsers, joinedUsers),
      onConferenceStatusUpdated: (conferenceInfo, status) => _onConferenceStatusUpdated(conferenceInfo, status),
    );
    _invitationObserver = TUIConferenceInvitationObserver(
      onReceiveInvitation: (roomInfo, invitation, extensionInfo) =>
          _onReceiveInvitation(roomInfo, invitation, extensionInfo),
      onInvitationCancelled: (roomInfo, invitation) => _onInvitationCancelled(roomInfo, invitation),
      onInvitationTimeout: (roomInfo, invitation) => _onInvitationTimeout(roomInfo, invitation),
      onInvitationAccepted: (roomInfo, invitation) => _onInvitationAccepted(roomInfo, invitation),
      onInvitationRejected: (roomInfo, invitation, reason) => _onInvitationRejected(roomInfo, invitation, reason),
      onInvitationRevokedByAdmin: (roomInfo, invitation, admin) =>
          _onInvitationRevokedByAdmin(roomInfo, invitation, admin),
      onInvitationHandledByOtherDevice: (roomInfo, accepted) => _onInvitationHandledByOtherDevice(roomInfo, accepted),
    );

    _roomEngine.addObserver(_roomObserver);
    _roomListManager.addObserver(_roomListObserver);
    _invitationManager.addObserver(_invitationObserver);
  }

  void _on(String key, String data) {
    switch (key) {
      // State changes
      case RoomStoreImpl.keyOnCurrentRoomChanged:
        _handleOnCurrentRoomChanged(data);
        break;
      // Listener events
      case RoomStoreImpl.keyOnRoomEnded:
        _handleOnRoomEnded(data);
        break;
    }
  }

  void _handleOnCurrentRoomChanged(String data) {
    final Map<String, dynamic>? json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>?;
    } catch (_) {
      return;
    }
    if (json == null) return;
    final currentRoomJson = json['currentRoom'];
    if (currentRoomJson is! Map<String, dynamic>) return;
    final currentRoom = RoomInfoFromJson.fromJson(currentRoomJson);
    _updateCurrentRoomInfo(currentRoom);
  }

  void _handleOnRoomEnded(String data) {
    final roomInfo = RoomInfoFromJson.fromJsonString(data);
    if (roomInfo == null) return;
    _listenerDispatcher.notify((listener) {
      listener.onRoomEnded?.call(roomInfo);
    });
  }

  void _onConferenceScheduled(TUIConferenceInfo conferenceInfo) {
    final roomInfo = conferenceInfo.toRoomInfo();
    _updateScheduledRoom(roomInfo);
    _listenerDispatcher.notify((listener) => listener.onAddedToScheduledRoom?.call(roomInfo));
  }

  void _onConferenceWillStart(TUIConferenceInfo conferenceInfo) {
    final roomInfo = conferenceInfo.toRoomInfo();
    _listenerDispatcher.notify((listener) => listener.onScheduledRoomStartingSoon?.call(roomInfo));
  }

  void _onConferenceDidCancelled(
      TUIConferenceInfo conferenceInfo, TUIConferenceCancelReason reason, TUIUserInfo operateUser) {
    final currentRoomId = _roomState.currentRoom.value?.roomID ?? "";
    final conferenceRoomId = conferenceInfo.basicRoomInfo.roomId;
    final isSameRoom = currentRoomId == conferenceRoomId;
    final roomInfo = conferenceInfo.toRoomInfo();

    _roomState.scheduledRoomListValue.value =
        _roomState.scheduledRoomListValue.value.where((it) => it.roomID != conferenceRoomId).toList();

    if (isSameRoom && reason == TUIConferenceCancelReason.cancelledByAdmin) {
      return;
    }

    if (!isSameRoom) {
      final operateUserInfo = operateUser.toRoomUser();
      switch (reason) {
        case TUIConferenceCancelReason.cancelledByAdmin:
          _listenerDispatcher.notify((listener) {
            listener.onScheduledRoomCancelled?.call(roomInfo, operateUserInfo);
          });
          break;
        case TUIConferenceCancelReason.removedFromAttendees:
          _listenerDispatcher.notify((listener) {
            listener.onRemovedFromScheduledRoom?.call(roomInfo, operateUserInfo);
          });
          break;
        default:
          break;
      }
    }
  }

  void _onScheduleAttendeesUpdated(
      TUIConferenceInfo conferenceInfo, List<TUIUserInfo> leftUsers, List<TUIUserInfo> joinedUsers) {
    final leftUserIds = leftUsers.map((it) => it.userId).toSet();
    final newAttendees = joinedUsers.map((it) => it.toRoomUser()).toList();

    final updatedScheduledRoomList = List<RoomInfo>.from(_roomState.scheduledRoomList.value);
    final index = updatedScheduledRoomList.indexWhere((room) => room.roomID == conferenceInfo.basicRoomInfo.roomId);
    if (index != -1) {
      final updatedAttendees = _removeScheduledAttendees(
        from: updatedScheduledRoomList[index].scheduleAttendees,
        userIds: leftUserIds,
      );
      final finalAttendees = _addScheduledAttendees(
        to: updatedAttendees,
        newAttendees: newAttendees,
      );
      updatedScheduledRoomList[index] = updatedScheduledRoomList[index].copyWith(
        scheduleAttendees: finalAttendees,
      );
    }
    _roomState.scheduledRoomListValue.value = updatedScheduledRoomList;

    final currentRoom = _roomState.currentRoom.value;
    if (currentRoom != null && currentRoom.roomID == conferenceInfo.basicRoomInfo.roomId) {
      final updatedAttendees = _removeScheduledAttendees(
        from: currentRoom.scheduleAttendees,
        userIds: leftUserIds,
      );
      final finalAttendees = _addScheduledAttendees(
        to: updatedAttendees,
        newAttendees: newAttendees,
      );
      _roomState.currentRoomValue.value = currentRoom.copyWith(
        scheduleAttendees: finalAttendees,
      );
    }
  }

  void _onConferenceInfoChanged(TUIConferenceInfo conferenceInfo, List<TUIConferenceModifyFlag> modifyFlagList) {
    final roomInfo = conferenceInfo.toRoomInfo();
    final updateRoomInfo = _roomState.currentRoomValue.value?.updateFromModifyFlags(roomInfo, modifyFlagList) ??
        roomInfo.updateFromModifyFlags(roomInfo, modifyFlagList);

    if (roomInfo.roomID == _roomState.currentRoomValue.value?.roomID) {
      _roomState.currentRoomValue.value = updateRoomInfo;
    }

    _updateScheduledRoom(updateRoomInfo);
  }

  void _updateScheduledRoom(RoomInfo roomInfo) {
    final list = _roomState.scheduledRoomListValue.value;
    final index = list.indexWhere((it) => it.roomID == roomInfo.roomID);

    if (index >= 0) {
      final newList = List<RoomInfo>.from(list);
      newList[index] = roomInfo;
      _roomState.scheduledRoomListValue.value = newList;
    } else {
      _roomState.scheduledRoomListValue.value = [...list, roomInfo];
    }
  }

  List<RoomUser> _removeScheduledAttendees({
    required List<RoomUser> from,
    required Set<String> userIds,
  }) {
    return from.where((user) => !userIds.contains(user.userID)).toList();
  }

  List<RoomUser> _addScheduledAttendees({
    required List<RoomUser> to,
    required List<RoomUser> newAttendees,
  }) {
    final existingUserIds = to.map((user) => user.userID).toSet();
    final filteredNewAttendees = newAttendees.where((user) => !existingUserIds.contains(user.userID)).toList();
    return [...to, ...filteredNewAttendees];
  }

  void _onConferenceStatusUpdated(TUIConferenceInfo conferenceInfo, TUIConferenceStatus status) {
    final roomStatus = status.toRoomStatus();
    _roomState.scheduledRoomListValue.value = _roomState.scheduledRoomListValue.value
        .map((roomInfo) => roomInfo.roomID == conferenceInfo.basicRoomInfo.roomId
            ? roomInfo.copyWith(roomStatus: roomStatus)
            : roomInfo)
        .toList();

    final currentRoom = _roomState.currentRoomValue.value;
    if (currentRoom != null && currentRoom.roomID == conferenceInfo.basicRoomInfo.roomId) {
      _roomState.currentRoomValue.value = currentRoom.copyWith(roomStatus: roomStatus);
    }
  }

  void _onReceiveInvitation(TUIRoomInfo roomInfo, TUIInvitation invitation, String extensionInfo) {
    _listenerDispatcher.notify((listener) {
      listener.onCallReceived?.call(roomInfo.toRoomInfo(), invitation.toRoomCall(), extensionInfo);
    });
  }

  void _onInvitationCancelled(TUIRoomInfo roomInfo, TUIInvitation invitation) {
    _listenerDispatcher.notify((listener) {
      listener.onCallCancelled?.call(roomInfo.toRoomInfo(), invitation.toRoomCall());
    });
  }

  void _onInvitationTimeout(TUIRoomInfo roomInfo, TUIInvitation invitation) {
    _listenerDispatcher.notify((listener) {
      listener.onCallTimeout?.call(roomInfo.toRoomInfo(), invitation.toRoomCall());
    });
  }

  void _onInvitationAccepted(TUIRoomInfo roomInfo, TUIInvitation invitation) {
    _listenerDispatcher.notify((listener) {
      listener.onCallAccepted?.call(roomInfo.toRoomInfo(), invitation.toRoomCall());
    });
  }

  void _onInvitationRejected(TUIRoomInfo roomInfo, TUIInvitation invitation, TUIInvitationRejectedReason reason) {
    _listenerDispatcher.notify((listener) {
      listener.onCallRejected?.call(roomInfo.toRoomInfo(), invitation.toRoomCall(), reason.toCallRejectionReason());
    });
  }

  void _onInvitationRevokedByAdmin(TUIRoomInfo roomInfo, TUIInvitation invitation, TUIUserInfo admin) {
    _listenerDispatcher.notify((listener) {
      listener.onCallRevokedByAdmin?.call(roomInfo.toRoomInfo(), invitation.toRoomCall(), admin.toRoomUser());
    });
  }

  void _onInvitationHandledByOtherDevice(TUIRoomInfo roomInfo, bool accepted) {
    _listenerDispatcher.notify((listener) {
      listener.onCallHandledByOtherDevice?.call(roomInfo.toRoomInfo(), accepted);
    });
  }

  void _updateCurrentRoomInfo(RoomInfo roomInfo) {
    final current = _roomState.currentRoom.value;
    if (current == null) {
      _roomState.currentRoomValue.value = roomInfo;
      return;
    }
    _roomState.currentRoomValue.value = roomInfo.copyWith(
      scheduledStartTime: current.scheduledStartTime,
      scheduledEndTime: current.scheduledEndTime,
      scheduleAttendees: current.scheduleAttendees,
    );
  }
}
