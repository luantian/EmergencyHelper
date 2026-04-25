import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/api/live/live_seat_store.dart';
import 'package:atomic_x_core/api/live/live_list_store.dart';
import 'package:atomic_x_core/api/device/device_store.dart' as device_store;
import 'package:atomic_x_core/impl/live/live_list_store_define.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:tencent_rtc_sdk/trtc_cloud.dart';
import 'package:tencent_rtc_sdk/trtc_cloud_def.dart';
import 'package:tencent_rtc_sdk/trtc_cloud_listener.dart';

import '../common/future_converter.dart';
import '../common/listener_dispatcher.dart';
import '../common/log.dart';
import 'store_factory.dart';

class _LiveSeatStateImpl implements LiveSeatState {
  final ValueNotifier<List<SeatInfo>> seatListValue = ValueNotifier([]);
  final ValueNotifier<LiveCanvas> canvasValue = ValueNotifier(LiveCanvas());
  final ValueNotifier<Map<String, int>> speakingUsersValue = ValueNotifier({});
  final ValueNotifier<List<AVStatistics>> avStatisticsValue = ValueNotifier([]);

  @override
  ValueListenable<List<SeatInfo>> get seatList => seatListValue;

  @override
  ValueListenable<LiveCanvas> get canvas => canvasValue;

  @override
  ValueListenable<Map<String, int>> get speakingUsers => speakingUsersValue;

  @override
  ValueListenable<List<AVStatistics>> get avStatistics => avStatisticsValue;
}

class LiveSeatStoreImpl extends LiveSeatStore implements IStore {
  final String _liveID;
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();

  final _liveSeatState = _LiveSeatStateImpl();
  final _listenerDispatcher = ListenerDispatcher<LiveSeatListener>();
  late final TUIRoomObserver _roomEngineObserver;
  late final TRTCCloudListener _trtcObserver;
  LiveInfo _liveInfo = LiveInfo();
  SeatFullInfo? _selfSeatInfo;

  final Set<String> hasAudioStreamUserList = <String>{};
  final Set<String> hasVideoStreamUserList = <String>{};

  static const int timeOut = 60;
  final Log _log = Log.getLiveLog('LiveSeatStoreImpl');

  LiveSeatStoreImpl(this._liveID) {
    _initObserver();
  }

  @override
  LiveSeatState get liveSeatState => _liveSeatState;

  @override
  void beforeEnterRoom(String liveID) async {
    _roomEngine.addObserver(_roomEngineObserver);
    TRTCCloud trtcCloud = await TRTCCloud.sharedInstance();
    trtcCloud.registerListener(_trtcObserver);
  }

  @override
  void afterEnterRoom(LiveInfo liveInfo) {
    _liveInfo = liveInfo;
    _initSeatList();
  }

  @override
  void leaveRoom(String liveID) async {
    _listenerDispatcher.cleanup();
    _roomEngine.removeObserver(_roomEngineObserver);
    TRTCCloud trtcCloud = await TRTCCloud.sharedInstance();
    trtcCloud.unRegisterListener(_trtcObserver);
  }

  @override
  void addLiveSeatEventListener(LiveSeatListener listener) {
    _listenerDispatcher.addListener(listener);
  }

  @override
  void removeLiveSeatEventListener(LiveSeatListener listener) {
    _listenerDispatcher.removeListener(listener);
  }

  @override
  Future<CompletionHandler> takeSeat(int seatIndex) async {
    _log.info('API takeSeat seatIndex:$seatIndex');
    final Completer<CompletionHandler> completer = Completer<CompletionHandler>();
    TUIRequestCompletion callback =
        TUIRequestCompletion(onAccepted: (String requestId, TUIUserInfo userInfo, String extensionInfo) {
      _log.info('Response takeSeat onSuccess onAccepted');
      completer.complete(CompletionHandler());
    }, onRejected: (String requestId, TUIUserInfo userInfo, String message, String extensionInfo) {
      _log.info('Response takeSeat onSuccess onRejected');
      completer.complete(CompletionHandler());
    }, onCancelled: (String requestId, TUIUserInfo userInfo) {
      _log.info('Response takeSeat onSuccess onCancelled');
      completer.complete(CompletionHandler());
    }, onTimeout: (String requestId, TUIUserInfo userInfo) {
      _log.info('Response takeSeat onSuccess onTimeout');
      completer.complete(CompletionHandler());
    }, onError: (String requestId, TUIUserInfo userInfo, TUIError error, String message) {
      _log.error('Response takeSeat onError code:${error.rawValue}, message:$message');
      final handler = CompletionHandler();
      handler.errorCode = error.rawValue;
      handler.errorMessage = message;
      completer.complete(handler);
    });
    _roomEngine.takeSeatEx(seatIndex, timeOut, extensionInfo: '', requestCompletion: callback);
    return completer.future;
  }

  @override
  Future<CompletionHandler> leaveSeat() async {
    _log.info('API leaveSeat');
    final result = await _roomEngine.leaveSeat();
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response leaveSeat onSuccess')
        : _log.error('Response leaveSeat onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  void muteMicrophone() {
    _log.info('API muteMicrophone');
    _roomEngine.muteLocalAudio();
  }

  @override
  Future<CompletionHandler> unmuteMicrophone() async {
    _log.info('API unmuteMicrophone');
    final result = await _roomEngine.unMuteLocalAudio();
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response unmuteMicrophone onSuccess')
        : _log.error('Response unmuteMicrophone onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> kickUserOutOfSeat(String userID) async {
    _log.info('API kickUserOutOfSeat userID:$userID');
    final result = await _roomEngine.kickUserOffSeatByAdmin(-1, userID);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response kickUserOutOfSeat onSuccess')
        : _log.error('Response kickUserOutOfSeat onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> moveUserToSeat({
    required String userID,
    required int targetIndex,
    MoveSeatPolicy policy = MoveSeatPolicy.abortWhenOccupied,
  }) async {
    _log.info('API moveUserToSeat userID:$userID targetIndex:$targetIndex policy:$policy');
    CompletionHandler handler = CompletionHandler();
    if (userID == TUIRoomEngine.getSelfInfo().userId) {
      final result = _roomEngine.moveToSeat(targetIndex);
      handler = handleCallback(result);
      handler.isSuccess
          ? _log.info('Response moveUserToSeat onSuccess')
          : _log.error('Response moveUserToSeat onError code:${handler.errorCode}, message:${handler.errorMessage}');
      return handler;
    } else {
      final result = await _roomEngine.moveUserToSeatByAdmin(
        userID,
        targetIndex,
        _enginePolicyFromMoveSeatPolicy(policy),
      );
      handler = handleCallback(result);
      handler.isSuccess
          ? _log.info('Response moveUserToSeat onSuccess')
          : _log.error('Response moveUserToSeat onError code:${handler.errorCode}, message:${handler.errorMessage}');
      return handler;
    }
  }

  @override
  Future<CompletionHandler> lockSeat(int seatIndex) async {
    _log.info('API lockSeat seatIndex:$seatIndex');
    TUISeatLockParams params = TUISeatLockParams();
    params.lockSeat = true;
    final result = await _roomEngine.lockSeatByAdmin(seatIndex, params);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response lockSeat onSuccess')
        : _log.error('Response lockSeat onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> unlockSeat(int seatIndex) async {
    _log.info('API unlockSeat seatIndex:$seatIndex');
    TUISeatLockParams params = TUISeatLockParams();
    params.lockSeat = false;
    final result = await _roomEngine.lockSeatByAdmin(seatIndex, params);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response unlockSeat onSuccess')
        : _log.error('Response unlockSeat onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> openRemoteCamera({
    required String userID,
    required DeviceControlPolicy policy,
  }) async {
    _log.info('API openRemoteCamera userID:$userID, policy:$policy');
    final seatInfo = _getSeatFullInfo(userID);
    if (seatInfo == null) {
      final handler = CompletionHandler();
      handler.errorCode = TUIError.errFailed.rawValue;
      handler.errorMessage = 'user not find';
      _log.error('Response openRemoteCamera onError reason:user not find');
      return handler;
    }
    TUISeatLockParams params = TUISeatLockParams();
    params.lockVideo = false;
    params.lockAudio = !seatInfo.userInfo.allowOpenMicrophone;
    final result = await _roomEngine.lockSeatByAdmin(seatInfo.index, params);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response openRemoteCamera onSuccess')
        : _log.error('Response openRemoteCamera onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> closeRemoteCamera(String userID) async {
    _log.info('API closeRemoteCamera userID:$userID');
    final seatInfo = _getSeatFullInfo(userID);
    if (seatInfo == null) {
      final handler = CompletionHandler();
      handler.errorCode = TUIError.errFailed.rawValue;
      handler.errorMessage = 'user not find';
      _log.error('Response closeRemoteCamera onError reason:user not find');
      return handler;
    }
    TUISeatLockParams params = TUISeatLockParams();
    params.lockVideo = true;
    params.lockAudio = !seatInfo.userInfo.allowOpenMicrophone;
    final result = await _roomEngine.lockSeatByAdmin(seatInfo.index, params);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response closeRemoteCamera onSuccess')
        : _log.error('Response closeRemoteCamera onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> openRemoteMicrophone({
    required String userID,
    required DeviceControlPolicy policy,
  }) async {
    _log.info('API openRemoteMicrophone userID:$userID, policy:$policy');
    final seatInfo = _getSeatFullInfo(userID);
    if (seatInfo == null) {
      final handler = CompletionHandler();
      handler.errorCode = TUIError.errFailed.rawValue;
      handler.errorMessage = 'user not find';
      _log.error('Response openRemoteMicrophone onError reason:user not find');
      return handler;
    }
    TUISeatLockParams params = TUISeatLockParams();
    params.lockAudio = false;
    params.lockVideo = !seatInfo.userInfo.allowOpenCamera;
    final result = await _roomEngine.lockSeatByAdmin(seatInfo.index, params);
    final hanndler = handleCallback(result);
    hanndler.isSuccess
        ? _log.info('Response openRemoteMicrophone onSuccess')
        : _log.error(
            'Response openRemoteMicrophone onError code:${hanndler.errorCode}, message:${hanndler.errorMessage}');
    return hanndler;
  }

  @override
  Future<CompletionHandler> closeRemoteMicrophone(String userID) async {
    _log.info('API closeRemoteMicrophone userID:$userID');
    final seatInfo = _getSeatFullInfo(userID);
    if (seatInfo == null) {
      final handler = CompletionHandler();
      handler.errorCode = TUIError.errFailed.rawValue;
      handler.errorMessage = 'user not find';
      _log.error('Response closeRemoteMicrophone onError reason:user not find');
      return handler;
    }
    TUISeatLockParams params = TUISeatLockParams();
    params.lockAudio = true;
    params.lockVideo = !seatInfo.userInfo.allowOpenCamera;
    final result = await _roomEngine.lockSeatByAdmin(seatInfo.index, params);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response closeRemoteMicrophone onSuccess')
        : _log
            .error('Response closeRemoteMicrophone onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  void _updateSeatList(List<SeatFullInfo> seatList) async {
    final liveCanvas = await _queryLiveCanvas();
    if (liveCanvas != null) _liveSeatState.canvasValue.value = liveCanvas;
    _liveSeatState.seatListValue.value = seatList.map(_seatInfoFromSeatFullInfo).toList();
    final seatOfSelf = seatList.firstWhereOrNull((seat) => seat.userId == TUIRoomEngine.getSelfInfo().userId);
    if (seatOfSelf == null) _liveSeatState.avStatisticsValue.value = [];
  }

  Future<LiveCanvas?> _queryLiveCanvas() async {
    Map<String, dynamic> map = {
      "api" : "querySeatLayout",
      "params" : {
        "roomId" : _liveID
      },
    };
    TUIValueCallBack<String> result = await _roomEngine.invokeExperimentalAPI(jsonEncode(map));
    if (result.code != TUIError.success || result.data == null) {
      _log.error("queryLiveCanvas, error=${result.code}, message=${result.message}");
      return null;
    }
    LiveCanvas liveCanvas = LiveCanvas();
    Map<String, dynamic> jsonMap = jsonDecode(result.data!);
    try {
      liveCanvas.w = jsonMap["canvasWidth"] ?? 0;
      liveCanvas.h = jsonMap["canvasHeight"] ?? 0;
      liveCanvas.templateID = jsonMap["templateId"] ?? 0;
    } catch (e) {
      return null;
    }
    return liveCanvas;
  }

  bool _isVoiceRoom() {
    if (_liveInfo.liveID.isEmpty) {
      return false;
    }
    return _liveInfo.isVoiceRoom();
  }

  void _initSeatList() async {
    final seatList = _roomEngine.querySeatList();
    _updateSeatList(seatList);
  }

  SeatInfo? _getSeatFullInfo(String userID) {
    if (userID.isEmpty) {
      return null;
    }
    return liveSeatState.seatList.value.firstWhereOrNull(
      (seat) => seat.userInfo.userID == userID,
    );
  }
}

extension LiveSeatStoreImplObserver on LiveSeatStoreImpl {
  void _initObserver() {
    _roomEngineObserver = TUIRoomObserver(
      onSeatListChangedEx: (roomId, seatList, seatedList, leftList) {
        if (roomId == _liveID) _onSeatListChanged(seatList);
      },
      onUserVoiceVolumeChanged: (volumeMap) => _onUserVoiceVolumeChanged(volumeMap),
      onUserAudioStateChanged: (userId, hasAudio, reason) => _onUserAudioStateChanged(userId, hasAudio),
      onUserVideoStateChanged: (userId, streamType, hasVideo, reason) => _onUserVideoStateChanged(userId, hasVideo),
    );
    _trtcObserver = TRTCCloudListener(onStatistics: (TRTCStatistics statistics) {
      final List<AVStatistics> avStatistics = [];
      statistics.localStatisticsArray?.forEach((localStatistics) {
        avStatistics.add(_localStatisticsToAVStatistics(localStatistics));
      });
      statistics.remoteStatisticsArray?.forEach((remoteStatistics) {
        avStatistics.add(_remoteStatisticsToAVStatistics(remoteStatistics));
      });
      _liveSeatState.avStatisticsValue.value = avStatistics;
    });
  }

  void _onSeatListChanged(List<SeatFullInfo> seatList) {
    final newSeatInfo = seatList.firstWhereOrNull((seat) => seat.userId == TUIRoomEngine.getSelfInfo().userId);

    if (_selfSeatInfo != null && newSeatInfo != null) {
      _notifyVideoLockChange(newSeatInfo);
      _notifyAudioLockChange(newSeatInfo);
    }

    _selfSeatInfo = newSeatInfo;
    _updateSeatList(seatList);
  }

  void _notifyVideoLockChange(SeatFullInfo newSeatInfo) {
    if (_selfSeatInfo!.userCameraStatus == newSeatInfo.userCameraStatus) return;

    final isLocked = newSeatInfo.userCameraStatus == DeviceStatus.closeByAdmin;
    _listenerDispatcher.notify((listener) {
      if (isLocked) {
        listener.onLocalCameraClosedByAdmin?.call();
      } else {
        listener.onLocalCameraOpenedByAdmin?.call(DeviceControlPolicy.unlockOnly);
      }
    });
  }

  void _notifyAudioLockChange(SeatFullInfo newSeatInfo) {
    if (_selfSeatInfo!.userMicrophoneStatus == newSeatInfo.userMicrophoneStatus) return;

    final isLocked = newSeatInfo.userMicrophoneStatus == DeviceStatus.closeByAdmin;
    _listenerDispatcher.notify((listener) {
      if (isLocked) {
        listener.onLocalMicrophoneClosedByAdmin?.call();
      } else {
        listener.onLocalMicrophoneOpenedByAdmin?.call(DeviceControlPolicy.unlockOnly);
      }
    });
  }

  void _onUserVoiceVolumeChanged(Map<String, int> volumeMap) {
    _liveSeatState.speakingUsersValue.value = volumeMap;
  }

  void _onUserAudioStateChanged(String userId, bool hasAudio) {
    if (hasAudio) {
      hasAudioStreamUserList.add(userId);
    } else {
      hasAudioStreamUserList.remove(userId);
    }
    if (_isVoiceRoom()) {
      final microphoneStatus = hasAudio ? device_store.DeviceStatus.on : device_store.DeviceStatus.off;
      final newSeatList = _liveSeatState.seatList.value.map((seat) {
        if (seat.userInfo.userID == userId) {
          final userInfo = SeatUserInfo(
            userID: seat.userInfo.userID,
            userName: seat.userInfo.userName,
            avatarURL: seat.userInfo.avatarURL,
            role: seat.userInfo.role,
            liveID: seat.userInfo.liveID,
            microphoneStatus: microphoneStatus,
            cameraStatus: seat.userInfo.cameraStatus,
            allowOpenMicrophone: seat.userInfo.allowOpenMicrophone,
            allowOpenCamera: seat.userInfo.allowOpenCamera,
          );
          return SeatInfo(
            index: seat.index,
            isLocked: seat.isLocked,
            userInfo: userInfo,
            region: seat.region,
          );
        } else {
          return seat;
        }
      }).toList();
      _liveSeatState.seatListValue.value = newSeatList;
    }
  }

  void _onUserVideoStateChanged(String userId, bool hasVideo) {
    if (hasVideo) {
      hasVideoStreamUserList.add(userId);
    } else {
      hasVideoStreamUserList.remove(userId);
    }
  }

  TUIMoveSeatPolicy _enginePolicyFromMoveSeatPolicy(MoveSeatPolicy policy) {
    switch (policy) {
      case MoveSeatPolicy.abortWhenOccupied:
        return TUIMoveSeatPolicy.abortWhenOccupied;
      case MoveSeatPolicy.forceReplace:
        return TUIMoveSeatPolicy.forceReplace;
      case MoveSeatPolicy.swapPosition:
        return TUIMoveSeatPolicy.swapPosition;
      // ignore: unreachable_switch_default
      default:
        return TUIMoveSeatPolicy.abortWhenOccupied;
    }
  }

  SeatInfo _seatInfoFromSeatFullInfo(SeatFullInfo seatFullInfo) {
    final seatUserInfo = SeatUserInfo(
      userID: seatFullInfo.userId,
      userName: seatFullInfo.userName,
      avatarURL: seatFullInfo.userAvatar,
      liveID: seatFullInfo.roomId,
      microphoneStatus: _deviceStatusFromEngineStatus(seatFullInfo.userMicrophoneStatus),
      cameraStatus: _deviceStatusFromEngineStatus(seatFullInfo.userCameraStatus),
      allowOpenCamera: seatFullInfo.userCameraStatus != DeviceStatus.closeByAdmin,
      allowOpenMicrophone: seatFullInfo.userMicrophoneStatus != DeviceStatus.closeByAdmin,
    );

    final regionInfo = RegionInfo(
      x: seatFullInfo.x,
      y: seatFullInfo.y,
      w: seatFullInfo.width,
      h: seatFullInfo.height,
      zorder: seatFullInfo.zorder,
    );

    return SeatInfo(
      index: seatFullInfo.seatIndex,
      isLocked: seatFullInfo.isSeatLocked,
      userInfo: seatUserInfo,
      region: regionInfo,
    );
  }

  device_store.DeviceStatus _deviceStatusFromEngineStatus(DeviceStatus status) {
    return status == DeviceStatus.opened ? device_store.DeviceStatus.on : device_store.DeviceStatus.off;
  }

  AVStatistics _localStatisticsToAVStatistics(TRTCLocalStatistics statistics) {
    return AVStatistics(
      videoBitrate: statistics.videoBitrate,
      videoWidth: statistics.width,
      videoHeight: statistics.height,
      frameRate: statistics.frameRate,
      audioSampleRate: statistics.audioSampleRate,
      audioBitrate: statistics.audioBitrate,
    );
  }

  AVStatistics _remoteStatisticsToAVStatistics(TRTCRemoteStatistics statistics) {
    return AVStatistics(
      userID: statistics.userId,
      videoBitrate: statistics.videoBitrate,
      videoWidth: statistics.width,
      videoHeight: statistics.height,
      frameRate: statistics.frameRate,
      audioSampleRate: statistics.audioSampleRate,
      audioBitrate: statistics.audioBitrate,
    );
  }
}
