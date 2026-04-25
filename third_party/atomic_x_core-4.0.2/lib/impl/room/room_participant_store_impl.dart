// ignore_for_file: unreachable_switch_default
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' hide DeviceStatus;

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/common/log.dart';
import 'package:atomic_x_core/impl/common/future_converter.dart';
import 'package:atomic_x_core/impl/room/room_store_factory.dart';
import '../common/listener_dispatcher.dart';
import 'room_store_converter.dart';

enum ListModifyType {
  none(0),
  full(1),
  add(2),
  remove(3),
  replace(4);

  final int value;
  const ListModifyType(this.value);

  static ListModifyType parse(int value) {
    return ListModifyType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ListModifyType.none,
    );
  }
}

class _UserDeviceRequests {
  String userID;
  Map<DeviceType, TUIRequest> deviceRequests;

  _UserDeviceRequests({
    this.userID = '',
    Map<DeviceType, TUIRequest>? deviceRequests,
  }) : deviceRequests = deviceRequests ?? {};
}

class _RoomParticipantStateImpl implements RoomParticipantState {
  final ValueNotifier<List<RoomParticipant>> participantListValue = ValueNotifier<List<RoomParticipant>>([]);
  final ValueNotifier<String> participantListCursorValue = ValueNotifier<String>('');
  final ValueNotifier<List<RoomUser>> audienceListValue = ValueNotifier<List<RoomUser>>([]);
  final ValueNotifier<String> audienceListCursorValue = ValueNotifier<String>('');
  final ValueNotifier<List<RoomUser>> adminListValue = ValueNotifier<List<RoomUser>>([]);
  final ValueNotifier<List<RoomUser>> messageDisabledUserListValue = ValueNotifier<List<RoomUser>>([]);
  final ValueNotifier<List<RoomParticipant>> participantListWithVideoValue = ValueNotifier<List<RoomParticipant>>([]);
  final ValueNotifier<RoomParticipant?> participantWithScreenValue = ValueNotifier<RoomParticipant?>(null);
  final ValueNotifier<List<DeviceRequestInfo>> pendingDeviceApplicationsValue =
      ValueNotifier<List<DeviceRequestInfo>>([]);
  final ValueNotifier<List<DeviceRequestInfo>> pendingDeviceInvitationsValue =
      ValueNotifier<List<DeviceRequestInfo>>([]);
  final ValueNotifier<Map<String, int>> speakingUsersValue = ValueNotifier<Map<String, int>>({});
  final ValueNotifier<Map<String, NetworkInfo>> networkQualitiesValue = ValueNotifier<Map<String, NetworkInfo>>({});
  final ValueNotifier<List<RoomParticipant>> pendingParticipantListValue = ValueNotifier<List<RoomParticipant>>([]);
  final ValueNotifier<RoomParticipant?> localParticipantValue = ValueNotifier<RoomParticipant?>(null);

  @override
  ValueListenable<List<RoomParticipant>> get participantList => participantListValue;

  @override
  ValueListenable<String> get participantListCursor => participantListCursorValue;

  @override
  ValueListenable<List<RoomUser>> get audienceList => audienceListValue;

  @override
  ValueListenable<String> get audienceListCursor => audienceListCursorValue;

  @override
  ValueListenable<List<RoomUser>> get adminList => adminListValue;

  @override
  ValueListenable<List<RoomUser>> get messageDisabledUserList => messageDisabledUserListValue;

  @override
  ValueListenable<List<RoomParticipant>> get participantListWithVideo => participantListWithVideoValue;

  @override
  ValueListenable<RoomParticipant?> get participantWithScreen => participantWithScreenValue;

  @override
  ValueListenable<List<DeviceRequestInfo>> get pendingDeviceApplications => pendingDeviceApplicationsValue;

  @override
  ValueListenable<List<DeviceRequestInfo>> get pendingDeviceInvitations => pendingDeviceInvitationsValue;

  @override
  ValueListenable<Map<String, int>> get speakingUsers => speakingUsersValue;

  @override
  ValueListenable<Map<String, NetworkInfo>> get networkQualities => networkQualitiesValue;

  @override
  ValueListenable<List<RoomParticipant>> get pendingParticipantList => pendingParticipantListValue;

  @override
  ValueListenable<RoomParticipant?> get localParticipant => localParticipantValue;
}

class RoomParticipantStoreImpl extends RoomParticipantStore implements IStore {
  final String _roomID;
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUIConferenceListManager _conferenceListManager;
  late final TUIConferenceInvitationManager _invitationManager;
  late final TUIRoomObserver _roomObserver;
  late final TUIConferenceListManagerObserver _conferenceListObserver;
  late final TUIConferenceInvitationObserver _invitationObserver;
  final _listenerDispatcher = ListenerDispatcher<RoomParticipantListener>();

  RoomInfo? _roomInfo;
  final _sentDeviceApplications = <DeviceType, TUIRequest>{};
  final _receivedDeviceApplications = <String, _UserDeviceRequests>{};
  final _sentDeviceInvitations = <String, _UserDeviceRequests>{};
  final _receivedDeviceInvitations = <String, _UserDeviceRequests>{};

  final int _fetchCount = 50;
  bool _isFetchParticipant = false;
  bool _isInitParticipantList = false;
  final Map<String, RoomParticipant> _participantMap = <String, RoomParticipant>{};
  final Map<String, RoomParticipant> _invitationMap = <String, RoomParticipant>{};
  final Map<String, RoomParticipant> _attendeeMap = <String, RoomParticipant>{};
  final Map<String, RoomUser> _audienceMap = <String, RoomUser>{};
  final Map<String, RoomUser> _adminMap = <String, RoomUser>{};
  final Map<String, RoomUser> _messageDisabledUserMap = <String, RoomUser>{};

  // API
  static const String keyGetParticipantList = 'roomParticipantStore.getParticipantList';
  static const String keyGetAudienceList = 'roomParticipantStore.getAudienceList';
  static const String keySearchUser = 'roomParticipantStore.searchUser';
  static const String keyPromoteToParticipant = 'roomParticipantStore.promoteToParticipant';
  static const String keyDemoteToAudience = 'roomParticipantStore.demoteToAudience';

  // State
  static const String keyOnLocalParticipantChanged = 'roomParticipantState.onLocalParticipantChanged';
  static const String keyOnParticipantListChanged = 'roomParticipantState.onParticipantListChanged';
  static const String keyOnParticipantListCursorChanged = 'roomParticipantState.onParticipantListCursorChanged';
  static const String keyOnAudienceListChanged = 'roomParticipantState.onAudienceListChanged';
  static const String keyOnAudienceListCursorChanged = 'roomParticipantState.onAudienceListCursorChanged';
  static const String keyOnAdministratorListChanged = 'roomParticipantState.onAdministratorListChanged';
  static const String keyOnMessageDisabledUserListChanged = 'roomParticipantState.onMessageDisabledUserListChanged';
  static const String keyQueryAdminList = 'roomParticipantState.queryAdminList';
  static const String keyQueryMessageDisabledUserList = 'roomParticipantState.queryMessageDisabledUserList';

  // Listener
  static const String keyOnParticipantJoined = 'roomParticipantListener.onParticipantJoined';
  static const String keyOnParticipantLeft = 'roomParticipantListener.onParticipantLeft';
  static const String keyOnAudiencePromotedToParticipant = 'roomParticipantListener.onAudiencePromotedToParticipant';
  static const String keyOnParticipantDemotedToAudience = 'roomParticipantListener.onParticipantDemotedToAudience';
  static const String keyOnOwnerChanged = 'roomParticipantListener.onOwnerChanged';
  static const String keyOnAdminSet = 'roomParticipantListener.onAdminSet';
  static const String keyOnAdminRevoked = 'roomParticipantListener.onAdminRevoked';
  static const String keyOnUserMessageDisabled = 'roomParticipantListener.onUserMessageDisabled';
  static const String keyOnAllDevicesDisabled = 'roomParticipantListener.onAllDevicesDisabled';
  static const String keyOnAllMessagesDisabled = 'roomParticipantListener.onAllMessagesDisabled';

  final Log _log = Log.getRoomLog('RoomParticipantStoreImpl');

  RoomParticipantStoreImpl(this._roomID) {
    _conferenceListManager = _roomEngine.getExtension(TUIExtensionType.conferenceListManager);
    _invitationManager = _roomEngine.getExtension(TUIExtensionType.conferenceInvitationManager);
    _initObserver();
  }

  final _roomParticipantState = _RoomParticipantStateImpl();

  @override
  RoomParticipantState get state => _roomParticipantState;

  @override
  void beforeEnterRoom(String roomID) {
    DeviceStore.shared.setFocus(DeviceFocusOwner.room);
    _roomEngine.addObserver(_roomObserver);
    _conferenceListManager.addObserver(_conferenceListObserver);
    _invitationManager.addObserver(_invitationObserver);
  }

  @override
  void afterEnterRoom(RoomInfo roomInfo) {
    _roomInfo = roomInfo;
    _roomEngine.query(keyQueryAdminList, "");
    _roomEngine.query(keyQueryMessageDisabledUserList, "");
  }

  @override
  void leaveRoom(String roomID) {
    _roomInfo = null;
    _isInitParticipantList = false;
    _roomEngine.removeObserver(_roomObserver);
    _conferenceListManager.removeObserver(_conferenceListObserver);
    _invitationManager.removeObserver(_invitationObserver);
    _listenerDispatcher.cleanup();

    _participantMap.clear();
    _invitationMap.clear();
    _attendeeMap.clear();
    _roomParticipantState.participantListValue.value = [];
    _roomParticipantState.participantListCursorValue.value = '';
    _roomParticipantState.participantListWithVideoValue.value = [];
    _roomParticipantState.participantWithScreenValue.value = null;
    _roomParticipantState.pendingDeviceApplicationsValue.value = [];
    _roomParticipantState.pendingDeviceInvitationsValue.value = [];
    _roomParticipantState.speakingUsersValue.value = {};
    _roomParticipantState.networkQualitiesValue.value = {};
    _roomParticipantState.pendingParticipantListValue.value = [];
    _roomParticipantState.localParticipantValue.value = null;
  }

  @override
  void addRoomParticipantListener(RoomParticipantListener listener) {
    _listenerDispatcher.addListener(listener);
  }

  @override
  void removeRoomParticipantListener(RoomParticipantListener listener) {
    _listenerDispatcher.removeListener(listener);
  }

  @override
  Future<ListResultCompletionHandler<RoomParticipant>> getParticipantList(String? cursor) async {
    final roomID = _roomInfo?.roomID;
    if (roomID == null || roomID.isEmpty) {
      _log.error("API getParticipantList failed, not in room");
      return ListResultCompletionHandler<RoomParticipant>()
        ..errorCode = TUIError.errOperationInvalidBeforeEnterRoom.rawValue
        ..errorMessage = "not in room";
    }

    if (_isFetchParticipant) {
      _log.error("API getParticipantList failed, request limit");
      return ListResultCompletionHandler<RoomParticipant>()
        ..errorCode = TUIError.errFreqLimit.rawValue
        ..errorMessage = "request limit";
    }

    _isFetchParticipant = true;

    final resultHandler = ListResultCompletionHandler<RoomParticipant>();
    final userListResult = await _fetchUserList(cursor);
    if (!userListResult.isSuccess) {
      _isFetchParticipant = false;
      return resultHandler
        ..errorCode = userListResult.errorCode
        ..errorMessage = userListResult.errorMessage;
    }

    if (!_isInitParticipantList) {
      final invitationResult = await _fetchInvitationList(roomID);
      if (!invitationResult.isSuccess) {
        _isFetchParticipant = false;
        return resultHandler
          ..errorCode = invitationResult.errorCode
          ..errorMessage = invitationResult.errorMessage;
      }
      final attendeeResult = await _fetchAttendeeList(roomID);
      if (!attendeeResult.isSuccess) {
        _isFetchParticipant = false;
        return resultHandler
          ..errorCode = attendeeResult.errorCode
          ..errorMessage = attendeeResult.errorMessage;
      }
      _isInitParticipantList = true;
    }
    _mergePendingParticipants();
    _isFetchParticipant = false;
    return resultHandler
      ..data = _roomParticipantState.participantListValue.value
      ..cursor = _roomParticipantState.participantListCursorValue.value;
  }

  @override
  Future<ListResultCompletionHandler<RoomUser>> getAudienceList(String? cursor) async {
    final resultHandler = ListResultCompletionHandler<RoomUser>();
    final result = await _roomEngine.call(
      keyGetAudienceList,
      jsonEncode({'cursor': cursor ?? ''}),
    );
    if (result.code == TUIError.success && result.data != null) {
      final json = jsonDecode(result.data!);
      if (json is! Map<String, dynamic>) {
        return resultHandler
          ..errorCode = TUIError.errFailed.rawValue
          ..errorMessage = 'invalid data';
      }
      final audienceList = (json['audienceList'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => RoomUserFromJson.fromJson(e))
              .toList() ??
          [];
      final nextCursor = json['cursor'] as String? ?? '';
      resultHandler.data = audienceList;
      resultHandler.cursor = nextCursor;
      _roomParticipantState.audienceListValue.value = audienceList;
      _roomParticipantState.audienceListCursorValue.value = nextCursor;
    } else {
      resultHandler.errorCode = result.code.rawValue;
      resultHandler.errorMessage = result.message;
    }
    return resultHandler;
  }

  @override
  Future<ListResultCompletionHandler<RoomUser>> searchUsers(String keyword) async {
    final resultHandler = ListResultCompletionHandler<RoomUser>();
    final result = await _roomEngine.call(
      keySearchUser,
      jsonEncode({'keyword': keyword}),
    );
    if (result.code == TUIError.success && result.data != null) {
      final json = jsonDecode(result.data!);
      final userList = (json['userList'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => RoomUserFromJson.fromJson(e))
              .toList() ??
          [];
      final nextCursor = json['cursor'] as String? ?? '';
      resultHandler.data = userList;
      resultHandler.cursor = nextCursor;
    } else {
      resultHandler.errorCode = result.code.rawValue;
      resultHandler.errorMessage = result.message;
    }
    return resultHandler;
  }

  @override
  Future<CompletionHandler> promoteAudienceToParticipant(String userID) async {
    final result = await _roomEngine.call(
      keyPromoteToParticipant,
      jsonEncode({'userID': userID}),
    );
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> demoteParticipantToAudience(String userID) async {
    final result = await _roomEngine.call(
      keyDemoteToAudience,
      jsonEncode({'userID': userID}),
    );
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> transferOwner(String userID) async {
    if (_roomInfo?.roomType == RoomType.webinar) {
      _log.error('transferOwner failed, webinar room does not support transfer owner');
      return CompletionHandler()
        ..errorCode = TUIError.errOperationNotSupportedInCurrentRoomType.rawValue
        ..errorMessage = 'Webinar room does not support transfer owner';
    }
    final result = await _roomEngine.changeUserRole(userID, TUIRole.roomOwner);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> setAdmin(String userID) async {
    final result = await _roomEngine.changeUserRole(userID, TUIRole.administrator);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> revokeAdmin(String userID) async {
    final result = await _roomEngine.changeUserRole(userID, TUIRole.generalUser);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> kickUser(String userID) async {
    final result = await _roomEngine.kickRemoteUserOutOfRoom(userID);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> updateParticipantNameCard({
    required String userID,
    required String nameCard,
  }) async {
    final result = await _roomEngine.changeUserNameCard(userID, nameCard);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> closeParticipantDevice({
    required String userID,
    required DeviceType device,
  }) async {
    final deviceType = device.toEngineDevice();
    final result = await _roomEngine.closeRemoteDeviceByAdmin(userID, deviceType);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> disableUserMessage({
    required String userID,
    required bool disable,
  }) async {
    final result = await _roomEngine.disableSendingMessageByAdmin(userID, disable);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> disableAllDevices({
    required DeviceType device,
    required bool disable,
  }) async {
    final deviceType = device.toEngineDevice();
    final result = await _roomEngine.disableDeviceForAllUserByAdmin(deviceType, disable);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> disableAllMessages(bool disable) async {
    final result = await _roomEngine.disableSendingMessageForAllUser(disable);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> updateParticipantMetaData({
    required String userID,
    required Map<String, String> metaData,
  }) async {
    final result = await _roomEngine.setCustomInfoForUser(userID, metaData);
    return handleCallback(result);
  }

  @override
  void muteMicrophone() {
    _roomEngine.muteLocalAudio();
  }

  @override
  Future<CompletionHandler> unmuteMicrophone() async {
    final result = await _roomEngine.unMuteLocalAudio();
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> requestToOpenDevice({
    required DeviceType device,
    int timeout = 0,
  }) async {
    final completer = Completer<CompletionHandler>();
    final resultHandler = CompletionHandler();
    TUIRequestCallback callback = TUIRequestCallback(
      onAccepted: (requestID, userID) {
        if (_sentDeviceApplications[device] != null) {
          final request = _sentDeviceApplications[device]!;
          final user = request.toUser.toRoomUser();
          final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
          _listenerDispatcher.notify((listener) {
            listener.onDeviceRequestApproved?.call(deviceRequestInfo, user);
          });
        }
        _sentDeviceApplications.remove(device);
        completer.complete(resultHandler);
      },
      onRejected: (requestID, userID, message) {
        if (_sentDeviceApplications[device] != null) {
          final request = _sentDeviceApplications[device]!;
          final user = request.toUser.toRoomUser();
          final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
          _listenerDispatcher.notify((listener) {
            listener.onDeviceRequestRejected?.call(deviceRequestInfo, user);
          });
        }
        _sentDeviceApplications.remove(device);
        completer.complete(resultHandler);
      },
      onCancelled: (requestID, userID) {
        _sentDeviceApplications.remove(device);
        completer.complete(resultHandler);
      },
      onTimeout: (requestID, userID) {
        if (_sentDeviceApplications[device] != null) {
          final request = _sentDeviceApplications[device]!;
          final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
          _listenerDispatcher.notify((listener) {
            listener.onDeviceRequestTimeout?.call(deviceRequestInfo);
          });
        }
        _sentDeviceApplications.remove(device);
        completer.complete(resultHandler);
      },
      onError: (requestID, userID, error, message) {
        _sentDeviceApplications.remove(device);
        resultHandler.errorCode = error.rawValue;
        resultHandler.errorMessage = message;
        completer.complete(resultHandler);
      },
    );
    final request = _roomEngine.applyToAdminToOpenLocalDevice(device.toEngineDevice(), timeout, callback);
    _sentDeviceApplications[device] = request;
    return completer.future;
  }

  @override
  Future<CompletionHandler> cancelOpenDeviceRequest(DeviceType device) async {
    if (_sentDeviceApplications[device] == null) {
      return CompletionHandler()
        ..errorCode = TUIError.errFailed.rawValue
        ..errorMessage = 'No device application is requesting';
    }
    final requestId = _sentDeviceApplications[device]!.requestId;
    final result = await _roomEngine.cancelRequest(requestId);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> approveOpenDeviceRequest({required DeviceType device, required String userID}) {
    return _responseDeviceApplication(userID, device, true);
  }

  @override
  Future<CompletionHandler> rejectOpenDeviceRequest({required DeviceType device, required String userID}) {
    return _responseDeviceApplication(userID, device, false);
  }

  @override
  Future<CompletionHandler> inviteToOpenDevice({
    required String userID,
    required DeviceType device,
    int timeout = 0,
  }) async {
    final completer = Completer<CompletionHandler>();
    final resultHandler = CompletionHandler();
    TUIRequestCallback callback = TUIRequestCallback(
      onAccepted: (requestID, userID) {
        final request = _getSentDeviceInvitations(device, userID);
        if (request != null) {
          final user = request.toUser.toRoomUser();
          final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
          _listenerDispatcher.notify((listener) {
            listener.onDeviceInvitationAccepted?.call(deviceRequestInfo, user);
          });
        }
        _removeSentDeviceInvitations(device, userID);
        completer.complete(resultHandler);
      },
      onRejected: (requestID, userID, message) {
        final request = _getSentDeviceInvitations(device, userID);
        if (request != null) {
          final user = request.toUser.toRoomUser();
          final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
          _listenerDispatcher.notify((listener) {
            listener.onDeviceInvitationDeclined?.call(deviceRequestInfo, user);
          });
        }
        _removeSentDeviceInvitations(device, userID);
        completer.complete(resultHandler);
      },
      onCancelled: (requestID, userID) {
        _removeSentDeviceInvitations(device, userID);
        completer.complete(resultHandler);
      },
      onTimeout: (requestID, userID) {
        final request = _getSentDeviceInvitations(device, userID);
        if (request != null) {
          final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
          _listenerDispatcher.notify((listener) {
            listener.onDeviceInvitationTimeout?.call(deviceRequestInfo);
          });
        }
        _removeSentDeviceInvitations(device, userID);
        completer.complete(resultHandler);
      },
      onError: (requestID, userID, error, message) {
        _removeSentDeviceInvitations(device, userID);
        resultHandler.errorCode = error.rawValue;
        resultHandler.errorMessage = message;
        completer.complete(resultHandler);
      },
    );
    final request = _roomEngine.openRemoteDeviceByAdmin(userID, device.toEngineDevice(), timeout, callback);
    _addSentDeviceInvitations(device, userID, request);
    return completer.future;
  }

  @override
  Future<CompletionHandler> cancelOpenDeviceInvitation({required String userID, required DeviceType device}) async {
    final request = _getSentDeviceInvitations(device, userID);
    if (request == null) {
      return CompletionHandler()
        ..errorCode = TUIError.errFailed.rawValue
        ..errorMessage = 'No device invitation is sending';
    }
    final result = await _roomEngine.cancelRequest(request.requestId);
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> acceptOpenDeviceInvitation({required String userID, required DeviceType device}) {
    return _responseDeviceInvitation(userID: userID, device: device, isAccept: true);
  }

  @override
  Future<CompletionHandler> declineOpenDeviceInvitation({required String userID, required DeviceType device}) {
    return _responseDeviceInvitation(userID: userID, device: device, isAccept: false);
  }
}

extension RoomParticipantStoreImplObserver on RoomParticipantStoreImpl {
  void _initObserver() {
    _roomObserver = TUIRoomObserver(
      onKickedOutOfRoom: (roomId, reason, message) => _onKickedOutOfRoom(roomId, reason, message),
      onRequestReceived: (request) => _onRequestReceived(request),
      onRequestCancelled: (request, operateUser) => _onRequestCancelled(request, operateUser),
      onRequestProcessed: (request, operateUser) => _onRequestProcessed(request, operateUser),
      onUserVoiceVolumeChanged: (volumeMap) => _onUserVoiceVolumeChanged(volumeMap),
      onUserNetworkQualityChanged: (networkMap) => _onUserNetworkQualityChanged(networkMap),
      on: (key, data) => _on(key, data),
    );

    _conferenceListObserver = TUIConferenceListManagerObserver(
        onScheduleAttendeesUpdated: (conferenceInfo, leftUsers, joinedUsers) =>
            _onScheduleAttendeesUpdated(conferenceInfo, leftUsers, joinedUsers));

    _invitationObserver = TUIConferenceInvitationObserver(
      onInvitationAdded: (roomID, invitation) => _onInvitationAdded(roomID, invitation),
      onInvitationRemoved: (roomID, invitation) => _onInvitationRemoved(roomID, invitation),
      onInvitationStatusChanged: (roomID, invitation) => _onInvitationStatusChanged(roomID, invitation),
    );
  }

  void _onKickedOutOfRoom(String roomId, TUIKickedOutOfRoomReason reason, String message) {
    if (_roomID != roomId) return;
    final kickedOutReason = reason.toKickedOutReason();
    _listenerDispatcher.notify((listener) {
      listener.onKickedFromRoom?.call(kickedOutReason, message);
    });
    RoomStoreFactory.shared.leaveRoom(roomId);
  }

  void _onRequestReceived(TUIRequest request) {
    switch (request.requestAction) {
      case TUIRequestAction.applyToAdminToOpenLocalCamera:
        _addReceivedDeviceApplications(DeviceType.camera, request);
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceRequestReceived?.call(deviceRequestInfo);
        });
      case TUIRequestAction.applyToAdminToOpenLocalMicrophone:
        _addReceivedDeviceApplications(DeviceType.microphone, request);
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceRequestReceived?.call(deviceRequestInfo);
        });
      case TUIRequestAction.requestToOpenRemoteCamera:
        _addReceivedDeviceInvitations(DeviceType.camera, request);
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceInvitationReceived?.call(deviceRequestInfo);
        });
      case TUIRequestAction.requestToOpenRemoteMicrophone:
        _addReceivedDeviceInvitations(DeviceType.microphone, request);
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceInvitationReceived?.call(deviceRequestInfo);
        });
      case TUIRequestAction.requestToCloseRemoteMicrophone:
        final roomUser = request.toUser.toRoomUser();
        _listenerDispatcher.notify((listener) {
          listener.onParticipantDeviceClosed?.call(DeviceType.microphone, roomUser);
        });
      case TUIRequestAction.requestToCloseRemoteCamera:
        final roomUser = request.toUser.toRoomUser();
        _listenerDispatcher.notify((listener) {
          listener.onParticipantDeviceClosed?.call(DeviceType.camera, roomUser);
        });
      case TUIRequestAction.requestToCloseRemoteScreenShare:
        final roomUser = request.toUser.toRoomUser();
        _listenerDispatcher.notify((listener) {
          listener.onParticipantDeviceClosed?.call(DeviceType.screenShare, roomUser);
        });
      default:
        break;
    }
  }

  void _onRequestCancelled(TUIRequest request, TUIUserInfo userInfo) {
    switch (request.requestAction) {
      case TUIRequestAction.applyToAdminToOpenLocalCamera:
        _removeReceivedDeviceApplications(DeviceType.camera, request.fromUser.userId);
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceRequestCancelled?.call(deviceRequestInfo);
        });
      case TUIRequestAction.applyToAdminToOpenLocalMicrophone:
        _removeReceivedDeviceApplications(DeviceType.microphone, request.fromUser.userId);
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceRequestCancelled?.call(deviceRequestInfo);
        });
      case TUIRequestAction.requestToOpenRemoteCamera:
        _removeReceivedDeviceInvitations(DeviceType.camera, request.fromUser.userId);
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceInvitationCancelled?.call(deviceRequestInfo);
        });
      case TUIRequestAction.requestToOpenRemoteMicrophone:
        _removeReceivedDeviceInvitations(DeviceType.microphone, request.fromUser.userId);
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceInvitationCancelled?.call(deviceRequestInfo);
        });
      default:
        break;
    }
  }

  void _onRequestProcessed(TUIRequest request, TUIUserInfo userInfo) {
    switch (request.requestAction) {
      case TUIRequestAction.applyToAdminToOpenLocalCamera:
        _removeReceivedDeviceApplications(DeviceType.camera, request.fromUser.userId);
        final user = userInfo.toRoomUser();
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceRequestProcessed?.call(deviceRequestInfo, user);
        });
      case TUIRequestAction.applyToAdminToOpenLocalMicrophone:
        _removeReceivedDeviceApplications(DeviceType.microphone, request.fromUser.userId);
        final user = userInfo.toRoomUser();
        final deviceRequestInfo = _deviceRequestInfoFromEngineRequest(request);
        _listenerDispatcher.notify((listener) {
          listener.onDeviceRequestProcessed?.call(deviceRequestInfo, user);
        });
      default:
        break;
    }
  }

  void _onUserVoiceVolumeChanged(Map<String, int> volumeMap) {
    final speakingMap = <String, int>{};
    volumeMap.forEach((userId, volume) {
      speakingMap[userId] = volume;
    });
    _roomParticipantState.speakingUsersValue.value = speakingMap;
  }

  void _onUserNetworkQualityChanged(Map<String, TUINetwork> networkMap) {
    final qualityMap = <String, NetworkInfo>{};
    for (final entry in networkMap.entries) {
      final networkInfo = entry.value.toNetworkInfo();
      qualityMap[entry.key] = networkInfo;
    }
    _roomParticipantState.networkQualitiesValue.value = qualityMap;
  }

  void _on(String key, String data) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final json = decoded;

    final roomID = json['roomID'] as String?;
    if (roomID == null || roomID.isEmpty || roomID != _roomID) {
      return;
    }

    switch (key) {
      // State changes
      case RoomParticipantStoreImpl.keyOnLocalParticipantChanged:
        _handleOnLocalParticipantChanged(json);
        break;
      case RoomParticipantStoreImpl.keyOnParticipantListChanged:
        _handleOnParticipantListChanged(json);
        break;
      case RoomParticipantStoreImpl.keyOnParticipantListCursorChanged:
        _handleOnParticipantListCursorChanged(json);
        break;
      case RoomParticipantStoreImpl.keyOnAudienceListChanged:
        _handleOnAudienceListChanged(json);
        break;
      case RoomParticipantStoreImpl.keyOnAudienceListCursorChanged:
        _handleOnAudienceListCursorChanged(json);
        break;
      case RoomParticipantStoreImpl.keyOnAdministratorListChanged:
        _handleOnAdministratorListChanged(json);
        break;
      case RoomParticipantStoreImpl.keyOnMessageDisabledUserListChanged:
        _handleOnMessageDisabledUserListChanged(json);
        break;
      // Listener events
      case RoomParticipantStoreImpl.keyOnParticipantJoined:
        _handleOnParticipantJoined(json);
        break;
      case RoomParticipantStoreImpl.keyOnParticipantLeft:
        _handleOnParticipantLeft(json);
        break;
      case RoomParticipantStoreImpl.keyOnAudiencePromotedToParticipant:
        _handleAudiencePromotedToParticipant(json);
        break;
      case RoomParticipantStoreImpl.keyOnParticipantDemotedToAudience:
        _handleParticipantDemotedToAudience(json);
        break;
      case RoomParticipantStoreImpl.keyOnOwnerChanged:
        _handleOnOwnerChanged(json);
        break;
      case RoomParticipantStoreImpl.keyOnAdminSet:
        _handleOnAdminSet(json);
        break;
      case RoomParticipantStoreImpl.keyOnAdminRevoked:
        _handleOnAdminRevoked(json);
        break;
      case RoomParticipantStoreImpl.keyOnUserMessageDisabled:
        _handleOnUserMessageDisabled(json);
        break;
      case RoomParticipantStoreImpl.keyOnAllDevicesDisabled:
        _handleOnAllDevicesDisabled(json);
        break;
      case RoomParticipantStoreImpl.keyOnAllMessagesDisabled:
        _handleOnAllMessagesDisabled(json);
        break;
    }
  }

  void _handleOnLocalParticipantChanged(Map<String, dynamic> json) {
    final localParticipantJson = json['localParticipant'];
    if (localParticipantJson is! Map<String, dynamic>) return;
    final localParticipant = RoomParticipantFromJson.fromJson(localParticipantJson);
    _roomParticipantState.localParticipantValue.value = localParticipant;
  }

  void _handleOnParticipantListChanged(Map<String, dynamic> json) {
    final listModifyType = json['listModifyType'] as int? ?? 0;
    final participantListJson = json['participantList'];
    if (participantListJson is! List) return;
    final newParticipants =
        participantListJson.whereType<Map<String, dynamic>>().map((e) => RoomParticipantFromJson.fromJson(e)).toList();

    _updateStateList(
      modifyType: ListModifyType.parse(listModifyType),
      list: newParticipants,
      map: _participantMap,
      stateNotifier: _roomParticipantState.participantListValue,
      keySelector: (p) => p.userID,
    );
    _updatePendingParticipantList(ListModifyType.parse(listModifyType), newParticipants);
  }

  void _handleOnParticipantListCursorChanged(Map<String, dynamic> json) {
    final cursor = json['cursor'];
    _roomParticipantState.participantListCursorValue.value = cursor is String ? cursor : '';
  }

  void _handleOnAudienceListChanged(Map<String, dynamic> json) {
    final listModifyType = json['listModifyType'] as int? ?? 0;
    final audienceListJson = json['audienceList'];
    if (audienceListJson is! List) return;
    final newAudiences =
        audienceListJson.whereType<Map<String, dynamic>>().map((e) => RoomUserFromJson.fromJson(e)).toList();

    _updateStateList(
      modifyType: ListModifyType.parse(listModifyType),
      list: newAudiences,
      map: _audienceMap,
      stateNotifier: _roomParticipantState.audienceListValue,
      keySelector: (u) => u.userID,
    );
  }

  void _handleOnAudienceListCursorChanged(Map<String, dynamic> json) {
    final cursor = json['cursor'];
    _roomParticipantState.audienceListCursorValue.value = cursor is String ? cursor : '';
  }

  void _handleOnAdministratorListChanged(Map<String, dynamic> json) {
    final listModifyType = json['listModifyType'] as int? ?? 0;
    final adminListJson = json['adminList'];
    if (adminListJson is! List) return;
    final newAdmins = adminListJson.whereType<Map<String, dynamic>>().map((e) => RoomUserFromJson.fromJson(e)).toList();

    _updateStateList(
      modifyType: ListModifyType.parse(listModifyType),
      list: newAdmins,
      map: _adminMap,
      stateNotifier: _roomParticipantState.adminListValue,
      keySelector: (u) => u.userID,
    );
  }

  void _handleOnMessageDisabledUserListChanged(Map<String, dynamic> json) {
    final listModifyType = json['listModifyType'] as int? ?? 0;
    final userListJson = json['messageDisabledUserList'];
    if (userListJson is! List) return;
    final newUsers = userListJson.whereType<Map<String, dynamic>>().map((e) => RoomUserFromJson.fromJson(e)).toList();

    _updateStateList(
      modifyType: ListModifyType.parse(listModifyType),
      list: newUsers,
      map: _messageDisabledUserMap,
      stateNotifier: _roomParticipantState.messageDisabledUserListValue,
      keySelector: (u) => u.userID,
    );
  }

  void _handleOnParticipantJoined(Map<String, dynamic> json) {
    final participantJson = json['participant'];
    if (participantJson is! Map<String, dynamic>) return;
    final participant = RoomUserFromJson.fromJson(participantJson);
    _listenerDispatcher.notify((listener) {
      listener.onParticipantJoined?.call(participant);
    });
  }

  void _handleOnParticipantLeft(Map<String, dynamic> json) {
    final participantJson = json['participant'];
    if (participantJson is! Map<String, dynamic>) return;
    final participant = RoomUserFromJson.fromJson(participantJson);
    _listenerDispatcher.notify((listener) {
      listener.onParticipantLeft?.call(participant);
    });
  }

  void _handleAudiencePromotedToParticipant(Map<String, dynamic> json) {
    final userInfoJson = json['userInfo'];
    if (userInfoJson is! Map<String, dynamic>) return;
    final userInfo = RoomUserFromJson.fromJson(userInfoJson);
    _listenerDispatcher.notify((listener) {
      listener.onAudiencePromotedToParticipant?.call(userInfo);
    });
  }

  void _handleParticipantDemotedToAudience(Map<String, dynamic> json) {
    final userInfoJson = json['userInfo'];
    if (userInfoJson is! Map<String, dynamic>) return;
    final userInfo = RoomUserFromJson.fromJson(userInfoJson);
    _listenerDispatcher.notify((listener) {
      listener.onParticipantDemotedToAudience?.call(userInfo);
    });
  }

  void _handleOnOwnerChanged(Map<String, dynamic> json) {
    final newOwnerJson = json['newOwner'];
    final oldOwnerJson = json['oldOwner'];
    if (newOwnerJson is! Map<String, dynamic> || oldOwnerJson is! Map<String, dynamic>) return;
    final newOwner = RoomUserFromJson.fromJson(newOwnerJson);
    final oldOwner = RoomUserFromJson.fromJson(oldOwnerJson);
    _listenerDispatcher.notify((listener) {
      listener.onOwnerChanged?.call(newOwner, oldOwner);
    });
  }

  void _handleOnAdminSet(Map<String, dynamic> json) {
    final userInfoJson = json['userInfo'];
    if (userInfoJson is! Map<String, dynamic>) return;
    final userInfo = RoomUserFromJson.fromJson(userInfoJson);
    _listenerDispatcher.notify((listener) {
      listener.onAdminSet?.call(userInfo);
    });
  }

  void _handleOnAdminRevoked(Map<String, dynamic> json) {
    final userInfoJson = json['userInfo'];
    if (userInfoJson is! Map<String, dynamic>) return;
    final userInfo = RoomUserFromJson.fromJson(userInfoJson);
    _listenerDispatcher.notify((listener) {
      listener.onAdminRevoked?.call(userInfo);
    });
  }

  void _handleOnUserMessageDisabled(Map<String, dynamic> json) {
    final operatorJson = json['operator'];
    if (operatorJson is! Map<String, dynamic>) return;
    final disable = json['disable'] == true;
    final operator = RoomUserFromJson.fromJson(operatorJson);
    _listenerDispatcher.notify((listener) {
      listener.onUserMessageDisabled?.call(disable, operator);
    });
  }

  void _handleOnAllDevicesDisabled(Map<String, dynamic> json) {
    final operatorJson = json['operator'];
    if (operatorJson is! Map<String, dynamic>) return;
    final disable = json['disable'] == true;
    final deviceValue = json['device'];
    final device = DeviceType.values.where((e) => e.value == deviceValue).firstOrNull;
    if (device == null) return;
    final operator = RoomUserFromJson.fromJson(operatorJson);
    _listenerDispatcher.notify((listener) {
      listener.onAllDevicesDisabled?.call(device, disable, operator);
    });
  }

  void _handleOnAllMessagesDisabled(Map<String, dynamic> json) {
    final operatorJson = json['operator'];
    if (operatorJson is! Map<String, dynamic>) return;
    final disable = json['disable'] == true;
    final operator = RoomUserFromJson.fromJson(operatorJson);
    _listenerDispatcher.notify((listener) {
      listener.onAllMessagesDisabled?.call(disable, operator);
    });
  }

  void _onScheduleAttendeesUpdated(
      TUIConferenceInfo conferenceInfo, List<TUIUserInfo> leftUsers, List<TUIUserInfo> joinedUsers) {
    if (_roomID != conferenceInfo.basicRoomInfo.roomId) return;
    for (final user in joinedUsers) {
      _addAttendeeUser(user.toRoomParticipant(roomStatus: RoomParticipantStatus.scheduled));
    }
    for (final user in leftUsers) {
      _removeAttendeeUser(user.userId);
    }
  }

  void _onInvitationAdded(String roomID, TUIInvitation invitation) {
    if (_roomID != roomID) return;
    final participant = invitation.invitee?.toRoomParticipant(
      roomStatus: invitation.status.toRoomParticipantStatus(),
    );
    if (participant != null) {
      _addInvitationUser(participant);
    }
  }

  void _onInvitationRemoved(String roomID, TUIInvitation invitation) {
    if (_roomID != roomID) return;
    final userID = invitation.invitee?.userId;
    if (userID != null) {
      _removeInvitationUser(userID);
    }
  }

  void _onInvitationStatusChanged(String roomID, TUIInvitation invitation) {
    if (_roomID != roomID) return;
    final participant = invitation.invitee?.toRoomParticipant(
      roomStatus: invitation.status.toRoomParticipantStatus(),
    );
    if (participant != null) {
      _addInvitationUser(participant);
    }
  }
}

extension on RoomParticipantStoreImpl {
  Future<CompletionHandler> _fetchUserList(String? cursor) async {
    final resultHandler = CompletionHandler();
    int nextSequence = int.tryParse(cursor ?? "0") ?? 0;
    if (nextSequence == 0) _participantMap.clear();

    final result = await _roomEngine.call(
      RoomParticipantStoreImpl.keyGetParticipantList,
      jsonEncode({'cursor': cursor ?? ''}),
    );
    if (result.code == TUIError.success && result.data != null) {
      final json = jsonDecode(result.data!) as Map<String, dynamic>;
      final participantListJson = json['participantList'];
      if (participantListJson is List) {
        final participantList = participantListJson
            .whereType<Map<String, dynamic>>()
            .map((e) => RoomParticipantFromJson.fromJson(e))
            .toList();
        _updateStateList(
            modifyType: ListModifyType.full,
            list: participantList,
            map: _participantMap,
            stateNotifier: _roomParticipantState.participantListValue,
            keySelector: (p) => p.userID);
      }
      final nextCursor = json['cursor'] as String? ?? '';
      _roomParticipantState.participantListCursorValue.value = nextCursor;
    } else {
      resultHandler.errorCode = result.code.rawValue;
      resultHandler.errorMessage = result.message;
    }
    return resultHandler;
  }

  Future<CompletionHandler> _fetchInvitationList(String roomID) async {
    final resultHandler = CompletionHandler();
    if (_roomInfo?.roomType != RoomType.standard) return resultHandler;
    _invitationMap.clear();

    String cursor = "";

    do {
      final result = await _invitationManager.getInvitationList(roomID, cursor, _fetchCount);

      if (result.code != TUIError.success) {
        _log.error("fetchInvitationList, error: ${result.code}, ${result.message}");
        resultHandler.errorCode = result.code.rawValue;
        resultHandler.errorMessage = result.message;
        return resultHandler;
      }

      final invitationList = result.data?.invitationList ?? [];
      for (final invitation in invitationList) {
        final participant = invitation.invitee?.toRoomParticipant(
          roomStatus: invitation.status.toRoomParticipantStatus(),
        );
        if (participant != null) {
          _invitationMap[participant.userID] = participant;
        }
      }
      cursor = result.data?.cursor ?? "";

      _log.info("fetchInvitationList page, cursor: $cursor");
    } while (cursor.isNotEmpty);

    return resultHandler;
  }

  Future<CompletionHandler> _fetchAttendeeList(String roomID) async {
    final resultHandler = CompletionHandler();
    if (_roomInfo?.roomType != RoomType.standard) return resultHandler;
    _attendeeMap.clear();

    String cursor = "";

    do {
      final result = await _conferenceListManager.fetchAttendeeList(roomID, cursor, _fetchCount);

      if (result.code != TUIError.success) {
        _log.error("fetchAttendeeList, error: ${result.code}, ${result.message}");
        resultHandler.errorCode = result.code.rawValue;
        resultHandler.errorMessage = result.message;
        return resultHandler;
      }

      final participantList = result.data?.scheduleAttendees
              .map((attendee) => attendee.toRoomParticipant().copyWith(
                    roomStatus: RoomParticipantStatus.scheduled,
                  ))
              .toList() ??
          [];

      _attendeeMap.addAll({for (var user in participantList) user.userID: user});
      cursor = result.data?.cursor ?? "";

      _log.info("fetchAttendeeList page, cursor: $cursor");
    } while (cursor.isNotEmpty);

    return resultHandler;
  }

  void _mergePendingParticipants() {
    final userIDs = <String>{};

    final pendingParticipants = <RoomParticipant>[];

    userIDs.addAll(_participantMap.keys);

    _invitationMap.forEach((userId, participant) {
      if (userIDs.add(userId)) {
        pendingParticipants.add(participant);
      }
    });

    _attendeeMap.forEach((userId, participant) {
      if (userIDs.add(userId)) {
        pendingParticipants.add(participant);
      }
    });

    _roomParticipantState.pendingParticipantListValue.value = pendingParticipants;
  }

  Future<CompletionHandler> _responseDeviceApplication(String userID, DeviceType device, bool isAccept) async {
    final request = _getReceivedDeviceApplications(device, userID);
    if (request == null) {
      return CompletionHandler()
        ..errorCode = TUIError.errFailed.rawValue
        ..errorMessage = 'No device application is received';
    }
    final result = await _roomEngine.responseRemoteRequest(request.requestId, isAccept);
    return handleCallback(
      result,
      onSuccess: (data) {
        _removeReceivedDeviceApplications(device, userID);
      },
    );
  }

  Future<CompletionHandler> _responseDeviceInvitation({
    required String userID,
    required DeviceType device,
    required bool isAccept,
  }) async {
    final request = _getReceivedDeviceInvitations(device, userID);
    if (request == null) {
      return CompletionHandler()
        ..errorCode = TUIError.errFailed.rawValue
        ..errorMessage = 'No device invitation is received';
    }

    final result = await _roomEngine.responseRemoteRequest(request.requestId, isAccept);
    return handleCallback(
      result,
      onSuccess: (data) {
        _removeReceivedDeviceInvitations(device, userID);
      },
    );
  }

  void _addReceivedDeviceApplications(DeviceType device, TUIRequest request) {
    final userID = request.fromUser.userId;
    var userDeviceRequests = _receivedDeviceApplications[userID] ?? _UserDeviceRequests(userID: userID);
    userDeviceRequests.deviceRequests[device] = request;
    _receivedDeviceApplications[userID] = userDeviceRequests;

    final updatedApplications =
        List<DeviceRequestInfo>.from(_roomParticipantState.pendingDeviceApplicationsValue.value);
    final exists = updatedApplications.any((info) => info.senderUserID == userID && info.device == device);
    if (!exists) {
      updatedApplications.add(_deviceRequestInfoFromEngineRequest(request));
    }
    _roomParticipantState.pendingDeviceApplicationsValue.value = updatedApplications;
  }

  void _removeReceivedDeviceApplications(DeviceType device, String userID) {
    _receivedDeviceApplications[userID]?.deviceRequests.remove(device);

    if (_receivedDeviceApplications[userID]?.deviceRequests.isEmpty ?? false) {
      _receivedDeviceApplications.remove(userID);
    }

    final updatedApplications = _roomParticipantState.pendingDeviceApplicationsValue.value
        .where((info) => info.senderUserID != userID)
        .toList();
    _roomParticipantState.pendingDeviceApplicationsValue.value = updatedApplications;
  }

  TUIRequest? _getReceivedDeviceApplications(DeviceType device, String userID) {
    return _receivedDeviceApplications[userID]?.deviceRequests[device];
  }

  void _addSentDeviceInvitations(DeviceType device, String userID, TUIRequest request) {
    var userDeviceRequests = _sentDeviceInvitations[userID] ?? _UserDeviceRequests(userID: userID);
    userDeviceRequests.deviceRequests[device] = request;
    _sentDeviceInvitations[userID] = userDeviceRequests;

    _roomParticipantState.pendingDeviceInvitationsValue.value = [
      ..._roomParticipantState.pendingDeviceInvitationsValue.value,
      _deviceRequestInfoFromEngineRequest(request)
    ];
  }

  void _removeSentDeviceInvitations(DeviceType device, String userID) {
    _sentDeviceInvitations[userID]?.deviceRequests.remove(device);
    if (_sentDeviceInvitations[userID]?.deviceRequests.isEmpty ?? false) {
      _sentDeviceInvitations.remove(userID);
    }

    final updatedInvitations =
        _roomParticipantState.pendingDeviceInvitationsValue.value.where((info) => info.senderUserID != userID).toList();
    _roomParticipantState.pendingDeviceInvitationsValue.value = updatedInvitations;
  }

  TUIRequest? _getSentDeviceInvitations(DeviceType device, String userID) {
    return _sentDeviceInvitations[userID]?.deviceRequests[device];
  }

  void _addReceivedDeviceInvitations(DeviceType device, TUIRequest request) {
    var userDeviceRequests =
        _receivedDeviceInvitations[request.fromUser.userId] ?? _UserDeviceRequests(userID: request.fromUser.userId);
    userDeviceRequests.deviceRequests[device] = request;
    _receivedDeviceInvitations[request.fromUser.userId] = userDeviceRequests;
  }

  void _removeReceivedDeviceInvitations(DeviceType device, String userID) {
    _receivedDeviceInvitations[userID]?.deviceRequests.remove(device);

    if (_receivedDeviceInvitations[userID]?.deviceRequests.isEmpty ?? false) {
      _receivedDeviceInvitations.remove(userID);
    }
  }

  TUIRequest? _getReceivedDeviceInvitations(DeviceType device, String userID) {
    return _receivedDeviceInvitations[userID]?.deviceRequests[device];
  }

  DeviceRequestInfo _deviceRequestInfoFromEngineRequest(TUIRequest request) {
    DeviceType? deviceType;
    switch (request.requestAction) {
      case TUIRequestAction.requestToOpenRemoteCamera:
      case TUIRequestAction.applyToAdminToOpenLocalCamera:
        deviceType = DeviceType.camera;
      case TUIRequestAction.applyToAdminToOpenLocalMicrophone:
      case TUIRequestAction.requestToOpenRemoteMicrophone:
        deviceType = DeviceType.microphone;
      case TUIRequestAction.applyToAdminToOpenLocalScreenShare:
        deviceType = DeviceType.screenShare;
      case TUIRequestAction.requestToTakeSeat:
      case TUIRequestAction.requestRemoteUserOnSeat:
      case TUIRequestAction.invalidAction:
      default:
        break;
    }
    return DeviceRequestInfo(
      timestamp: request.timestamp,
      senderUserID: request.fromUser.userId,
      senderUserName: request.fromUser.userName,
      senderAvatarURL: request.fromUser.avatarUrl,
      senderNameCard: request.fromUser.nameCard ?? "",
      content: request.content,
      device: deviceType ?? DeviceType.microphone,
    );
  }

  void _addInvitationUser(RoomParticipant participant) {
    if (_participantMap.containsKey(participant.userID)) return;
    _invitationMap[participant.userID] = participant;
    final list = _roomParticipantState.pendingParticipantListValue.value;
    final index = list.indexWhere((p) => p.userID == participant.userID);

    if (index >= 0) {
      final updatedList = List<RoomParticipant>.from(list);
      updatedList[index] = participant;
      _roomParticipantState.pendingParticipantListValue.value = updatedList;
    } else {
      _roomParticipantState.pendingParticipantListValue.value = [...list, participant];
    }
  }

  void _removeInvitationUser(String userID) {
    if (!_invitationMap.containsKey(userID)) return;
    _invitationMap.remove(userID);
    _roomParticipantState.pendingParticipantListValue.value =
        _roomParticipantState.pendingParticipantListValue.value.where((p) => p.userID != userID).toList();
  }

  void _addAttendeeUser(RoomParticipant participant) {
    if (_participantMap.containsKey(participant.userID) || _invitationMap.containsKey(participant.userID)) return;
    _attendeeMap[participant.userID] = participant;
    final list = _roomParticipantState.pendingParticipantListValue.value;
    final index = list.indexWhere((p) => p.userID == participant.userID);

    if (index >= 0) {
      final updatedList = List<RoomParticipant>.from(list);
      updatedList[index] = participant;
      _roomParticipantState.pendingParticipantListValue.value = updatedList;
    } else {
      _roomParticipantState.pendingParticipantListValue.value = [...list, participant];
    }
  }

  void _removeAttendeeUser(String userID) {
    if (!_attendeeMap.containsKey(userID)) return;
    _attendeeMap.remove(userID);
    _roomParticipantState.pendingParticipantListValue.value =
        _roomParticipantState.pendingParticipantListValue.value.where((p) => p.userID != userID).toList();
  }

  void _updateStateList<T>({
    required ListModifyType modifyType,
    required List<T> list,
    required Map<String, T> map,
    required ValueNotifier<List<T>> stateNotifier,
    required String Function(T) keySelector,
  }) {
    switch (modifyType) {
      case ListModifyType.full:
        map.clear();
        for (final item in list) {
          map[keySelector(item)] = item;
        }
        stateNotifier.value = map.values.toList();
        break;
      case ListModifyType.add:
      case ListModifyType.replace:
        for (final item in list) {
          map[keySelector(item)] = item;
        }
        stateNotifier.value = map.values.toList();
        break;
      case ListModifyType.remove:
        for (final item in list) {
          map.remove(keySelector(item));
        }
        stateNotifier.value = map.values.toList();
        break;
      case ListModifyType.none:
        return;
    }

    if (stateNotifier == _roomParticipantState.participantListValue) {
      final participants = stateNotifier.value as List<RoomParticipant>;
      _roomParticipantState.participantListWithVideoValue.value =
          participants.where((p) => p.cameraStatus == DeviceStatus.on).toList();
      _roomParticipantState.participantWithScreenValue.value =
          participants.where((p) => p.screenShareStatus == DeviceStatus.on).firstOrNull;
    }
  }

  void _updatePendingParticipantList(ListModifyType modifyType, List<RoomParticipant> list) {
    switch (modifyType) {
      case ListModifyType.full:
        _mergePendingParticipants();
        break;
      case ListModifyType.add:
        for (final participant in list) {
          _removeInvitationUser(participant.userID);
          _removeAttendeeUser(participant.userID);
        }
        break;
      default:
        break;
    }
  }
}
