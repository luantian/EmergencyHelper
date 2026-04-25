import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

import '../common/future_converter.dart';
import '../common/listener_dispatcher.dart';
import '../common/log.dart';
import '../common/type_converter.dart';
import 'store_factory.dart';

class _LiveAudienceStateImpl implements LiveAudienceState {
  final ValueNotifier<List<LiveUserInfo>> audienceListValue = ValueNotifier<List<LiveUserInfo>>([]);
  final ValueNotifier<int> audienceCountValue = ValueNotifier<int>(0);
  final ValueNotifier<List<LiveUserInfo>> messageBannedUserListValue = ValueNotifier<List<LiveUserInfo>>([]);

  @override
  ValueListenable<List<LiveUserInfo>> get audienceList => audienceListValue;

  @override
  ValueListenable<int> get audienceCount => audienceCountValue;

  @override
  ValueListenable<List<LiveUserInfo>> get messageBannedUserList => messageBannedUserListValue;
}

class LiveAudienceStoreImpl extends LiveAudienceStore implements IStore {
  final String _liveID;
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUIRoomObserver _roomObserver;

  final _liveAudienceState = _LiveAudienceStateImpl();
  final _listenerDispatcher = ListenerDispatcher<LiveAudienceListener>();
  
  final Log _log = Log.getLiveLog('LiveAudienceStoreImpl');

  LiveAudienceStoreImpl(this._liveID) {
    _initObserver();
  }

  @override
  LiveAudienceState get liveAudienceState => _liveAudienceState;

  @override
  void beforeEnterRoom(String liveID) {
    _roomEngine.addObserver(_roomObserver);
  }

  @override
  void afterEnterRoom(LiveInfo liveInfo) {
    fetchAudienceList();
    _fetchMessageBannedUserList();
  }

  @override
  void leaveRoom(String liveID) {
    _liveAudienceState.audienceListValue.value = [];
    _liveAudienceState.audienceCountValue.value = 0;
    _roomEngine.removeObserver(_roomObserver);
    _listenerDispatcher.cleanup();
  }

  @override
  void addLiveAudienceListener(LiveAudienceListener listener) {
    _listenerDispatcher.addListener(listener);
  }

  @override
  void removeLiveAudienceListener(LiveAudienceListener listener) {
    _listenerDispatcher.removeListener(listener);
  }

  @override
  Future<CompletionHandler> fetchAudienceList() async {
    _log.info('API fetchAudienceList');
    final result = await _roomEngine.getUserList(0);
    final handler = handleCallback(
      result,
      onSuccess: (data) {
        if (data is! TUIUserListResult) return;
        List<TUIUserInfo> userList = data.userInfoList;
        _liveAudienceState.audienceListValue.value = userList
            .where((user) => user.userRole != TUIRole.roomOwner)
            .map((user) => TypeConverter.liveUserInfoFromEngineUserInfo(user))
            .toList();
      },
    );
    handler.isSuccess 
      ? _log.info('Response fetchAudienceList onSuccess')
      : _log.error('Response fetchAudienceList onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> setAdministrator(String userID) async {
    _log.info('API setAdministrator userID:$userID');
    final result = await _roomEngine.changeUserRole(userID, TUIRole.administrator);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response setAdministrator onSuccess')
      : _log.error('Response setAdministrator onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> revokeAdministrator(String userID) async {
    _log.info('API revokeAdministrator userID:$userID');
    final result = await _roomEngine.changeUserRole(userID, TUIRole.generalUser);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response revokeAdministrator onSuccess')
      : _log.error('Response revokeAdministrator onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> kickUserOutOfRoom(String userID) async {
    _log.info('API kickUserOutOfRoom userID:$userID');
    final result = await _roomEngine.kickRemoteUserOutOfRoom(userID);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response kickUserOutOfRoom onSuccess')
      : _log.error('Response kickUserOutOfRoom onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> disableSendMessage({
    required String userID,
    required bool isDisable,
  }) async {
    _log.info('API disableSendMessage userID:$userID, isDisable:$isDisable');
    final result = await _roomEngine.disableSendingMessageByAdmin(userID, isDisable);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response disableSendMessage onSuccess')
      : _log.error('Response disableSendMessage onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  void _fetchMessageBannedUserList() async {
    _log.info('getBannedUserList called');
    final result = await _roomEngine.getBannedUserList();
    if (result.code == TUIError.success && result.data != null) {
      final list =
          result.data!.userInfoList.map((userInfo) => TypeConverter.liveUserInfoFromEngineUserInfo(userInfo)).toList();
      _liveAudienceState.messageBannedUserListValue.value = list;
    }
    result.code == TUIError.success
        ? _log.info('Response getBannedUserList onSuccess')
        : _log.error('Response getBannedUserList onError code:${result.code}, message:${result.message}');
  }
}

extension LiveAudienceStoreImplObserver on LiveAudienceStoreImpl {
  void _initObserver() {
    _roomObserver = TUIRoomObserver(
      onRemoteUserEnterRoom: (roomId, userInfo) => _onRemoteUserEnterRoom(roomId, userInfo),
      onRemoteUserLeaveRoom: (roomId, userInfo) => _onRemoteUserLeaveRoom(roomId, userInfo),
      onRoomUserCountChanged: (roomId, userCount) => _onRoomUserCountChanged(roomId, userCount),
      onSendMessageForUserDisableChanged: (roomId, userId, isDisable) =>
          _onSendMessageForUserDisableChanged(roomId, userId, isDisable),
    );
  }

  void _onRemoteUserEnterRoom(String roomId, TUIUserInfo userInfo) {
    if (roomId != _liveID || userInfo.userRole == TUIRole.roomOwner) return;
    final currentAudienceList = _liveAudienceState.audienceListValue.value;
    if (!currentAudienceList.any((user) => user.userID == userInfo.userId)) {
      _liveAudienceState.audienceListValue.value = [
        ...currentAudienceList,
        TypeConverter.liveUserInfoFromEngineUserInfo(userInfo)
      ];
    }
    final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(userInfo);
    _listenerDispatcher.notify(
      (listener) => listener.onAudienceJoined?.call(liveUserInfo),
    );
  }

  void _onRemoteUserLeaveRoom(String roomId, TUIUserInfo userInfo) {
    if (roomId != _liveID) return;
    _liveAudienceState.audienceListValue.value = [
      ..._liveAudienceState.audienceListValue.value.where((user) => user.userID != userInfo.userId)
    ];
    final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(userInfo);
    _listenerDispatcher.notify(
      (listener) => listener.onAudienceLeft?.call(liveUserInfo),
    );
  }

  void _onRoomUserCountChanged(String roomId, int userCount) {
    if (roomId != _liveID) return;
    _liveAudienceState.audienceCountValue.value = userCount;
  }

  void _onSendMessageForUserDisableChanged(String roomId, String userID, bool isDisable) {
    final LiveUserInfo? user =
        _liveAudienceState.messageBannedUserListValue.value.firstWhereOrNull((userInfo) => userInfo.userID == userID);
    if (isDisable) {
      if (user != null) return;
      final list = [..._liveAudienceState.messageBannedUserListValue.value, LiveUserInfo(userID: userID)];
      _liveAudienceState.messageBannedUserListValue.value = list;
    } else {
      if (user == null) return;
      final list = [..._liveAudienceState.messageBannedUserListValue.value];
      list.removeWhere((user) => user.userID == userID);
      _liveAudienceState.messageBannedUserListValue.value = list;
    }
  }
}
