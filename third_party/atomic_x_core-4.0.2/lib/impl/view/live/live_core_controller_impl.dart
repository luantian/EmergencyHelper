import 'dart:convert';

import 'package:atomic_x_core/api/live/deprecated/live_core_widget_define_deprecated.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/common/log.dart';
import 'package:atomic_x_core/impl/live/store_factory.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:flutter/cupertino.dart';

import 'package:atomic_x_core/api/live/deprecated/live_core_controller_deprecated.dart';
import 'package:atomic_x_core/impl/view/live/live_core_controller_impl_deprecated.dart';

import '../../live/live_data_reporter.dart';
import '../../live/live_seat_store_impl.dart';

part 'live_core_controller_impl_internal.dart';

class LiveCoreControllerImpl implements LiveCoreController, LiveCoreControllerDeprecated {
  final Log _logger = Log.getLiveLog("LiveCoreControllerImpl");
  late final LiveCoreControllerImplDeprecated _deprecatedController;

  String _liveID = "";
  TUIRoomObserver? _roomObserver;
  final InternalState _internalState = InternalState();
  late final CoreViewType _coreViewType;
  late final VoidCallback _onCurrentLiveListener;

  LiveCoreControllerImpl(CoreViewType type) {
    _coreViewType = type;
    DeviceStore.shared.setFocus(DeviceFocusOwner.live);
    _deprecatedController = LiveCoreControllerImplDeprecated();
    _onCurrentLiveListener = _onCurrentLiveInfoChanged;
  }

  @override
  void setLiveID(String liveID) {
    _logInfo("setLiveID, liveID=$liveID");
    _liveID = liveID;
  }

  @override
  void startPreviewLiveStream(String roomID, bool isMuteAudio, TUIPlayCallback? playCallback) {}

  @override
  void stopPreviewLiveStream(String roomID) {}

  static void callExperimentalAPI(String jsonStr) {
    try {
      final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;

      if (jsonMap['api'] == 'setFramework' && jsonMap['params'] is Map<String, dynamic>) {
        final params = jsonMap['params'] as Map<String, dynamic>;

        if (params.containsKey('component') && params['component'] is int) {
          LiveDataReporter.dataReportComponent = params['component'] as int;
        }
      }
    } catch (e) {
      // Ignore JSON parsing errors
    } finally {
      TUIRoomEngine.sharedInstance().invokeExperimentalAPI(jsonStr);
    }
  }

  @Deprecated("Deprecated")
  @override
  CoreState getCoreState() {
    return _deprecatedController.getCoreState();
  }

  ///*** Device ***///

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> startCamera(bool useFrontCamera) {
    return _deprecatedController.startCamera(useFrontCamera);
  }

  @Deprecated("Deprecated")
  @override
  void switchCamera(bool isFront) {
    _deprecatedController.switchCamera(isFront);
  }

  @Deprecated("Deprecated")
  @override
  void stopCamera() {
    _deprecatedController.stopCamera();
  }

  @Deprecated("Deprecated")
  @override
  void enableMirror(bool enable) {
    _deprecatedController.enableMirror(enable);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> startMicrophone() {
    return _deprecatedController.startMicrophone();
  }

  @Deprecated("Deprecated")
  @override
  void stopMicrophone() {
    _deprecatedController.stopMicrophone();
  }

  @Deprecated("Deprecated")
  @override
  void muteMicrophone() {
    _deprecatedController.muteMicrophone();
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> unmuteMicrophone() {
    return _deprecatedController.unmuteMicrophone();
  }

  ///*** Room ***///

  @Deprecated("Deprecated")
  @override
  Future<TUIValueCallBack<TUIRoomInfo>> startLiveStream(TUIRoomInfo roomInfo) {
    return _deprecatedController.startLiveStream(roomInfo);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIValueCallBack<TUILiveInfo>> startLiveStreamV2(TUILiveInfo liveInfo) {
    return _deprecatedController.startLiveStreamV2(liveInfo);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIValueCallBack<TUIRoomInfo>> joinLiveStream(String roomId) {
    return _deprecatedController.joinLiveStream(roomId);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIValueCallBack<TUILiveInfo>> joinLiveStreamV2(String roomId) {
    return _deprecatedController.joinLiveStreamV2(roomId);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> stopLiveStream() {
    return _deprecatedController.stopLiveStream();
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIValueCallBack<TUILiveStatisticsData>> stopLiveStreamV2() {
    return _deprecatedController.stopLiveStreamV2();
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> leaveLiveStream() {
    return _deprecatedController.leaveLiveStream();
  }

  ///*** CoGuest ***///

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> requestIntraRoomConnection(
      {required String userId, int seatIndex = -1, required int timeout, required bool openCamera}) {
    return _deprecatedController.requestIntraRoomConnection(userId: userId, timeout: timeout, openCamera: openCamera);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> respondIntraRoomConnection(String userId, bool isAccepted) {
    return _deprecatedController.respondIntraRoomConnection(userId, isAccepted);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> cancelIntraRoomConnection(String userId) {
    return _deprecatedController.cancelIntraRoomConnection(userId);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> terminateIntraRoomConnection() {
    return _deprecatedController.terminateIntraRoomConnection();
  }

  ///*** CoHost ***///

  @Deprecated("Deprecated")
  @override
  void registerConnectionObserver(ConnectionObserver observer) {
    _deprecatedController.registerConnectionObserver(observer);
  }

  @Deprecated("Deprecated")
  @override
  void unregisterConnectionObserver(ConnectionObserver observer) {
    _deprecatedController.unregisterConnectionObserver(observer);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> disconnectUser(String userId) {
    return _deprecatedController.disconnectUser(userId);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIValueCallBack<TUIConnectionCode?>> requestCrossRoomConnection(String roomId, int timeout) {
    return _deprecatedController.requestCrossRoomConnection(roomId, timeout);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> respondToCrossRoomConnection(String roomId, bool isAccepted) {
    return _deprecatedController.respondToCrossRoomConnection(roomId, isAccepted);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> cancelCrossRoomConnection(String roomId) {
    return _deprecatedController.cancelCrossRoomConnection(roomId);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> terminateCrossRoomConnection() {
    return _deprecatedController.terminateCrossRoomConnection();
  }

  ///*** Battle ***///

  @Deprecated("Deprecated")
  @override
  void registerBattleObserver(BattleObserver observer) {
    _deprecatedController.registerBattleObserver(observer);
  }

  @Deprecated("Deprecated")
  @override
  void unregisterBattleObserver(BattleObserver observer) {
    _deprecatedController.unregisterBattleObserver(observer);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIValueCallBack<BattleRequestCallback>> requestBattle(
      TUIBattleConfig config, List<String> userIdList, int timeout) {
    return _deprecatedController.requestBattle(config, userIdList, timeout);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> respondToBattle(String battleId, bool isAccepted) {
    return _deprecatedController.respondToBattle(battleId, isAccepted);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> cancelBattle(String battleId, List<String> userIdList) {
    return _deprecatedController.cancelBattle(battleId, userIdList);
  }

  @Deprecated("Deprecated")
  @override
  Future<TUIActionCallback> terminateBattle(String battleId) {
    return _deprecatedController.terminateBattle(battleId);
  }
}
