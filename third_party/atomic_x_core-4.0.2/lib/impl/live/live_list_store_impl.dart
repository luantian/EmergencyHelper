import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:rtc_room_engine/rtc_room_engine.dart';

import '../../api/define.dart';
import '../../api/live/live_audience_store.dart';
import '../../api/live/live_list_store.dart';
import '../common/future_converter.dart';
import '../common/listener_dispatcher.dart';
import '../common/log.dart';
import '../common/version.dart';
import 'live_list_store_define.dart';
import 'live_data_reporter.dart';
import 'room_engine_login.dart';
import 'store_factory.dart';

class TriggerableValueNotifier<T> extends ValueNotifier<T> {
  TriggerableValueNotifier(super.value);

  void notify() {
    notifyListeners();
  }
}

class _LiveListStateImpl implements LiveListState {
  final ValueNotifier<List<LiveInfo>> liveListValue = ValueNotifier([]);
  final ValueNotifier<String> liveListCursorValue = ValueNotifier('');
  final ValueNotifier<LiveInfo> currentLiveValue = TriggerableValueNotifier(LiveInfo());

  @override
  ValueListenable<List<LiveInfo>> get liveList => liveListValue;

  @override
  ValueListenable<String> get liveListCursor => liveListCursorValue;

  @override
  ValueListenable<LiveInfo> get currentLive => currentLiveValue;
}

class LiveListStoreImpl extends LiveListStore {
  static final LiveListStoreImpl shared = LiveListStoreImpl._();

  final ListenerDispatcher<LiveListListener> _listenerDispatcher = ListenerDispatcher();

  late final TUIRoomEngine _roomEngine;
  late final TUILiveListManager _liveListManager;
  late final TUIRoomObserver _roomObserver;
  late final TUILiveListObserver _liveListObserver;

  final _LiveListStateImpl _liveState = _LiveListStateImpl();

  final Log _log = Log.getLiveLog('LiveListStoreImpl');

  LiveListStoreImpl._() {
    RoomEngineLogin.shared.startAutoLogin();
    _roomEngine = TUIRoomEngine.sharedInstance();
    _liveListManager = _roomEngine.getExtension(TUIExtensionType.liveListManager);
    _addObserver();
  }

  @override
  LiveListState get liveState => _liveState;

  @override
  void addLiveListListener(LiveListListener listener) {
    _listenerDispatcher.addListener(listener);
  }

  @override
  void removeLiveListListener(LiveListListener listener) {
    _listenerDispatcher.removeListener(listener);
  }

  @override
  Future<CompletionHandler> fetchLiveList({
    required String cursor,
    required int count,
  }) async {
    Version.printVersion();
    _log.info('API fetchLiveList cursor:$cursor, count:$count');
    final result = await _liveListManager.fetchLiveList(cursor, count);
    if (result.code != TUIError.success || result.data == null) {
      _log.error('Response fetchLiveList onError code:${result.code.rawValue}, message:${result.message}');
      return handleCallback(result);
    }

    _log.info('Response fetchLiveList onSuccess');
    final TUILiveListResult liveListResult = result.data!;
    _liveState.liveListCursorValue.value = liveListResult.cursor;
    final list = liveListResult.liveInfoList.map((liveInfo) => _liveInfoFromEngineLiveInfo(liveInfo)).toList();
    cursor == ''
        ? _liveState.liveListValue.value = list
        : _liveState.liveListValue.value = [..._liveState.liveListValue.value, ...list];
    return handleCallback(result);
  }

  @override
  Future<LiveInfoCompletionHandler> fetchLiveInfo(String liveID) async {
    _log.info('API fetchLiveInfo liveID:$liveID');
    final result = await _liveListManager.getLiveInfo(liveID);
    final handler = LiveInfoCompletionHandler();
    handler.errorCode = result.code.rawValue;
    handler.errorMessage = result.message;
    if (result.code != TUIError.success || result.data == null) {
      _log.error('Response fetchLiveInfo onError code:${result.code.rawValue}, message:${result.message}');
      return handler;
    }
    final newLiveInfo = _liveInfoFromEngineLiveInfo(result.data!);
    handler.liveInfo = newLiveInfo;
    return handler;
  }

  @override
  Future<LiveInfoCompletionHandler> createLive(LiveInfo liveInfo) async {
    Version.printVersion();
    _log.info('API createLive liveInfo:$liveInfo');
    LiveDataReporter.reportComponent();
    if (!_isVoiceRoom(liveInfo)) {
      _enableUnlimitedRoom();
    }
    _enableLiveQos(true);

    StoreFactory.shared.beforeEnterRoom(liveInfo.liveID);
    final result = await _liveListManager.startLive(_engineLiveInfoFromLiveInfo(liveInfo));

    final handler = LiveInfoCompletionHandler();
    handler.errorCode = result.code.rawValue;
    handler.errorMessage = result.message;
    if (result.code != TUIError.success || result.data == null) {
      _log.error('Response createLive onError code:${result.code.rawValue}, message:${result.message}');
      _enableLiveQos(false);
      return handler;
    }

    _log.info('Response createLive onSuccess');
    final newLiveInfo = _liveInfoFromEngineLiveInfo(result.data!);
    _liveState.currentLiveValue.value = newLiveInfo;
    StoreFactory.shared.afterEnterRoom(newLiveInfo);
    handler.liveInfo = newLiveInfo;
    return handler;
  }

  @override
  Future<LiveInfoCompletionHandler> joinLive(String liveID) async {
    Version.printVersion();
    _log.info('API joinLive liveID:$liveID');
    LiveDataReporter.reportComponent();
    _enableLiveQos(true);

    StoreFactory.shared.beforeEnterRoom(liveID);
    final result = await _liveListManager.joinLive(liveID);

    final handler = LiveInfoCompletionHandler();
    handler.errorCode = result.code.rawValue;
    handler.errorMessage = result.message;
    if (result.code != TUIError.success || result.data == null) {
      _log.error('Response joinLive onError code:${result.code.rawValue}, message:${result.message}');
      _enableLiveQos(false);
      return handler;
    }

    _log.info('Response joinLive onSuccess');
    final liveInfo = _liveInfoFromEngineLiveInfo(result.data!);
    _liveState.currentLiveValue.value = liveInfo;
    StoreFactory.shared.afterEnterRoom(liveInfo);
    handler.liveInfo = liveInfo;
    return handler;
  }

  @override
  Future<CompletionHandler> leaveLive() async {
    Version.printVersion();
    _log.info('API leaveLive');
    final currentLive = _liveState.currentLiveValue.value;
    if (currentLive.liveID.isNotEmpty) {
      if (!_isVoiceRoom(currentLive)) {
        _enableLiveQos(false);
      }

      StoreFactory.shared.leaveRoom(currentLive.liveID);
      _liveState.currentLiveValue.value = LiveInfo();
    }
    final result = await _liveListManager.leaveLive();
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response leaveLive onSuccess')
        : _log.error('Response leaveLive onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<StopLiveCompletionHandler> endLive() async {
    Version.printVersion();
    _log.info('API endLive');
    final currentLive = _liveState.currentLiveValue.value;
    if (currentLive.liveID.isNotEmpty) {
      if (!_isVoiceRoom(currentLive)) {
        _enableLiveQos(false);
      }

      StoreFactory.shared.leaveRoom(currentLive.liveID);
      _liveState.currentLiveValue.value = LiveInfo();
    }
    final result = await _liveListManager.stopLive();
    final handler = StopLiveCompletionHandler();
    handler.errorCode = result.code.rawValue;
    handler.errorMessage = result.message;
    handler.statisticsData = result.data ?? TUILiveStatisticsData();
    handler.isSuccess
        ? _log.info('Response endLive onSuccess')
        : _log.error('Response endLive onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> updateLiveInfo({
    required LiveInfo liveInfo,
    required List<ModifyFlag> modifyFlagList,
  }) async {
    _log.info('API updateLiveInfo liveInfo:$liveInfo, modifyFlagList:$modifyFlagList');
    final bitmask = modifyFlagList.fold(0, (value, flag) => value | flag.rawValue);

    String? name = _containsFlag(bitmask: bitmask, flag: ModifyFlag.liveName.rawValue) ? liveInfo.liveName : null;
    String? notice = _containsFlag(bitmask: bitmask, flag: ModifyFlag.notice.rawValue) ? liveInfo.notice : null;
    bool? disableMessage =
        _containsFlag(bitmask: bitmask, flag: ModifyFlag.isMessageDisable.rawValue) ? liveInfo.isMessageDisable : null;
    bool? isPublicVisible =
        _containsFlag(bitmask: bitmask, flag: ModifyFlag.isPublicVisible.rawValue) ? liveInfo.isPublicVisible : null;
    TUISeatMode? seatMode = _containsFlag(bitmask: bitmask, flag: ModifyFlag.seatMode.rawValue)
        ? liveInfo.seatMode == TakeSeatMode.apply
            ? TUISeatMode.applyToTake
            : TUISeatMode.freeToTake
        : null;
    String? coverUrl = _containsFlag(bitmask: bitmask, flag: ModifyFlag.coverUrl.rawValue) ? liveInfo.coverURL : null;
    String? backgroundUrl =
        _containsFlag(bitmask: bitmask, flag: ModifyFlag.backgroundUrl.rawValue) ? liveInfo.backgroundURL : null;
    List<int>? categoryList =
        _containsFlag(bitmask: bitmask, flag: ModifyFlag.categoryList.rawValue) ? liveInfo.categoryList : null;
    int? activityStatus =
        _containsFlag(bitmask: bitmask, flag: ModifyFlag.activityStatus.rawValue) ? liveInfo.activityStatus : null;

    final result = await _liveListManager.setLiveInfo(liveInfo.liveID,
        name: name,
        notice: notice,
        disableMessage: disableMessage,
        isPublicVisible: isPublicVisible,
        takeSeatMode: seatMode,
        coverUrl: coverUrl,
        backgroundUrl: backgroundUrl,
        categoryList: categoryList,
        activityStatus: activityStatus);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response updateLiveInfo onSuccess')
        : _log.error('Response updateLiveInfo onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<MetaDataCompletionHandler> queryMetaData(List<String> keys) async {
    _log.info('API queryMetaData keys:$keys');
    final result = await _roomEngine.getRoomMetadata(keys);
    final handler = MetaDataCompletionHandler();
    handler.errorCode = result.code.rawValue;
    handler.errorMessage = result.message;
    handler.metaData = result.data ?? {};
    handler.isSuccess
        ? _log.info('Response queryMetaData onSuccess')
        : _log.error('Response queryMetaData onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> updateLiveMetaData(Map<String, String> metaData) async {
    _log.info('API updateLiveMetaData metaData:$metaData');
    final result = await _roomEngine.setRoomMetadataByAdmin(metaData);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response updateLiveMetaData onSuccess')
        : _log.error('Response updateLiveMetaData onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  void reset() {
    _log.info('API reset');
    _liveState.currentLiveValue.value = LiveInfo();
    _liveState.liveListValue.value = [];
    _liveState.liveListCursorValue.value = '';
    _listenerDispatcher.cleanup();
  }
}

extension LiveListStoreImplObserver on LiveListStoreImpl {
  void _addObserver() {
    _roomObserver = TUIRoomObserver(onRoomDismissed: (roomId, reason) {
      _listenerDispatcher.notify((listener) {
        listener.onLiveEnded?.call(roomId, _liveEndReasonFromEngineRoomDismissedReason(reason), 'Room dismissed');

        final currentLive = _liveState.currentLiveValue.value;
        if (currentLive.liveID.isNotEmpty && _isVoiceRoom(currentLive)) {
          _enableLiveQos(false);
        }
        StoreFactory.shared.leaveRoom(currentLive.liveID);
        _liveState.currentLiveValue.value = LiveInfo();
      });
    }, onKickedOutOfRoom: (roomId, reason, message) {
      _listenerDispatcher.notify((listener) {
        listener.onKickedOutOfLive?.call(roomId, _liveKickOutReasonFromEngineKickedOutOfRoomReason(reason), message);
      });

      final currentLive = _liveState.currentLiveValue.value;
      if (currentLive.liveID.isNotEmpty && _isVoiceRoom(currentLive)) {
        _enableLiveQos(false);
      }
      StoreFactory.shared.leaveRoom(currentLive.liveID);
      _liveState.currentLiveValue.value = LiveInfo();
    }, onUserSigExpired: () {
      final currentLive = _liveState.currentLiveValue.value;
      if (currentLive.liveID.isNotEmpty && _isVoiceRoom(currentLive)) {
        _enableLiveQos(false);
      }
      if (currentLive.liveID.isNotEmpty) {
        StoreFactory.shared.leaveRoom(currentLive.liveID);
        _liveState.currentLiveValue.value = LiveInfo();
      }
    });

    _liveListObserver = TUILiveListObserver(
      onLiveInfoChanged: (liveInfo, modifyFlagList) {
        final currentLive = _liveState.currentLiveValue.value;
        final convertedLiveInfo = _liveInfoFromEngineLiveInfo(liveInfo);
        if (currentLive.liveID.isNotEmpty && currentLive.liveID == liveInfo.roomId) {
          final updatedLiveInfo = currentLive.updateFromModifyFlags(convertedLiveInfo, modifyFlagList);
          _liveState.currentLiveValue.value = updatedLiveInfo;
        }

        final list = _liveState.liveListValue.value;
        final index = list.indexWhere((info) => liveInfo.roomId == info.liveID);

        if (index != -1) {
          _liveState.liveListValue.value = [
            for (int i = 0; i < list.length; i++)
              if (i == index) list[i].updateFromModifyFlags(convertedLiveInfo, modifyFlagList) else list[i],
          ];
        }
      },
    );

    _roomEngine.addObserver(_roomObserver);
    _liveListManager.addObserver(_liveListObserver);
  }
}

extension on LiveListStoreImpl {
  bool _isVoiceRoom(LiveInfo liveInfo) {
    if (liveInfo.liveID.isEmpty) {
      return false;
    }
    return liveInfo.isVoiceRoom();
  }

  void _enableUnlimitedRoom() {
    try {
      Map<String, dynamic> params = {'enable': true};

      Map<String, dynamic> jsonObject = {'api': 'enableUnlimitedRoom', 'params': params};

      final jsonString = jsonEncode(jsonObject);
      _roomEngine.invokeExperimentalAPI(jsonString);
      // ignore: empty_catches
    } catch (e) {}
  }

  void _enableLiveQos(bool enable) async {
    Map<String, dynamic> enableEngineParams = {'enable': enable};
    Map<String, dynamic> enableEngineJsonObject = {'api': 'enableLiveQos', 'params': enableEngineParams};

    try {
      final enableEngineJsonString = json.encode(enableEngineJsonObject);
      await _roomEngine.invokeExperimentalAPI(enableEngineJsonString);
      // ignore: empty_catches
    } catch (e) {}
  }

  bool _containsFlag({required int bitmask, required int flag}) {
    return (bitmask & flag) == flag;
  }

  LiveKickedOutReason _liveKickOutReasonFromEngineKickedOutOfRoomReason(TUIKickedOutOfRoomReason reason) {
    switch (reason) {
      case TUIKickedOutOfRoomReason.byAdmin:
        return LiveKickedOutReason.byAdmin;
      case TUIKickedOutOfRoomReason.byLoggedOnOtherDevice:
        return LiveKickedOutReason.byLoggedOnOtherDevice;
      case TUIKickedOutOfRoomReason.byServer:
        return LiveKickedOutReason.byServer;
      case TUIKickedOutOfRoomReason.forNetworkDisconnected:
        return LiveKickedOutReason.forNetworkDisconnected;
      case TUIKickedOutOfRoomReason.forJoinRoomStatusInvalidDuringOffline:
        return LiveKickedOutReason.forJoinRoomStatusInvalidDuringOffline;
      case TUIKickedOutOfRoomReason.forCountOfJoinedRoomExceededLimit:
        return LiveKickedOutReason.forCountOfJoinedRoomsExceedLimit;
      // ignore: unreachable_switch_default
      default:
        return LiveKickedOutReason.byAdmin;
    }
  }

  LiveEndedReason _liveEndReasonFromEngineRoomDismissedReason(TUIRoomDismissedReason reason) {
    switch (reason) {
      case TUIRoomDismissedReason.byOwner:
        return LiveEndedReason.endedByHost;
      case TUIRoomDismissedReason.byServer:
        return LiveEndedReason.endedByServer;
    }
  }

  TUILiveInfo _engineLiveInfoFromLiveInfo(LiveInfo liveInfo) {
    final engineLiveInfo = TUILiveInfo();
    engineLiveInfo.roomId = liveInfo.liveID;
    engineLiveInfo.name = liveInfo.liveName;
    engineLiveInfo.notice = liveInfo.notice;
    engineLiveInfo.isMessageDisableForAllUser = liveInfo.isMessageDisable;
    engineLiveInfo.isPublicVisible = liveInfo.isPublicVisible;
    engineLiveInfo.seatMode =
        liveInfo.seatMode == TakeSeatMode.apply ? TUISeatMode.applyToTake : TUISeatMode.freeToTake;
    engineLiveInfo.coverUrl = liveInfo.coverURL;
    engineLiveInfo.backgroundUrl = liveInfo.backgroundURL;
    engineLiveInfo.categoryList = liveInfo.categoryList;
    engineLiveInfo.activityStatus = liveInfo.activityStatus;
    engineLiveInfo.ownerId = liveInfo.liveOwner.userID;
    engineLiveInfo.ownerName = liveInfo.liveOwner.userName;
    engineLiveInfo.ownerAvatarUrl = liveInfo.liveOwner.avatarURL;
    engineLiveInfo.createTime = liveInfo.createTime;
    engineLiveInfo.viewCount = liveInfo.totalViewerCount;

    final config = LiveInfoExtension.getSeatConfiguration(liveInfo.seatTemplate);
    engineLiveInfo.isSeatEnabled = config.isSeatEnabled;
    engineLiveInfo.maxSeatCount = liveInfo.maxSeatCount == 0 ? config.maxSeatCount ?? 0 : liveInfo.maxSeatCount;
    engineLiveInfo.seatLayoutTemplateId =
        liveInfo.seatLayoutTemplateID == 600 ? config.seatLayoutTemplateID : liveInfo.seatLayoutTemplateID;
    engineLiveInfo.keepOwnerOnSeat = config.keepOwnerOnSeat ?? liveInfo.keepOwnerOnSeat;

    return engineLiveInfo;
  }

  LiveInfo _liveInfoFromEngineLiveInfo(TUILiveInfo liveInfo) {
    final owner =
        LiveUserInfo(userID: liveInfo.ownerId, userName: liveInfo.ownerName, avatarURL: liveInfo.ownerAvatarUrl);

    return LiveInfo(
        liveID: liveInfo.roomId,
        liveName: liveInfo.name,
        notice: liveInfo.notice,
        isMessageDisable: liveInfo.isMessageDisableForAllUser,
        isPublicVisible: liveInfo.isPublicVisible,
        isSeatEnabled: liveInfo.isSeatEnabled,
        keepOwnerOnSeat: liveInfo.keepOwnerOnSeat,
        maxSeatCount: liveInfo.maxSeatCount,
        seatMode: liveInfo.seatMode == TUISeatMode.applyToTake ? TakeSeatMode.apply : TakeSeatMode.free,
        seatTemplate: _seatTemplateFromTemplateID(liveInfo.seatLayoutTemplateId, maxSeatCount: liveInfo.maxSeatCount),
        seatLayoutTemplateID: liveInfo.seatLayoutTemplateId,
        coverURL: liveInfo.coverUrl,
        backgroundURL: liveInfo.backgroundUrl,
        categoryList: liveInfo.categoryList,
        activityStatus: liveInfo.activityStatus,
        liveOwner: owner,
        createTime: liveInfo.createTime,
        totalViewerCount: liveInfo.viewCount,
        isGiftEnabled: true,
        metaData: {});
  }

  SeatLayoutTemplate _seatTemplateFromTemplateID(int seatLayoutTemplateID, {int maxSeatCount = 0}) {
    return switch (seatLayoutTemplateID) {
      600 => const VideoDynamicGrid9Seats(),
      601 => const VideoDynamicFloat7Seats(),
      602 => const VideoLeftFocus9Seats(),
      603 => const VideoUniformGrid9Seats(),
      800 => const VideoFixedGrid9Seats(),
      801 => const VideoFixedFloat7Seats(),
      200 => const VideoLandscape4Seats(),
      70 => AudioSalon(maxSeatCount),
      50 => Karaoke(maxSeatCount),
      _ => const VideoDynamicGrid9Seats(),
    };
  }
}
