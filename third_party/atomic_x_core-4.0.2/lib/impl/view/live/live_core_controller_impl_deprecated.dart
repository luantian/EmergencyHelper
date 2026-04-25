import 'package:atomic_x_core/api/live/deprecated/live_core_controller_deprecated.dart';
import 'package:atomic_x_core/api/live/deprecated/live_core_widget_define_deprecated.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

class LiveCoreControllerImplDeprecated implements LiveCoreControllerDeprecated {

  LiveCoreControllerImplDeprecated();

  @override
  CoreState getCoreState() {
    // TODO: implement getCoreState
    throw UnimplementedError();
  }

  ///*** Device ***///

  @override
  Future<TUIActionCallback> startCamera(bool useFrontCamera) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  void switchCamera(bool isFront) {}

  @override
  void stopCamera() {}

  @override
  void enableMirror(bool enable) {}

  @override
  Future<TUIActionCallback> startMicrophone() {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> unmuteMicrophone() {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  void muteMicrophone() {}

  @override
  void stopMicrophone() {}

  ///*** Room ***///

  @override
  Future<TUIValueCallBack<TUIRoomInfo>> startLiveStream(TUIRoomInfo roomInfo) {
    return Future.value(TUIValueCallBack(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIValueCallBack<TUILiveInfo>> startLiveStreamV2(TUILiveInfo liveInfo) {
    return Future.value(TUIValueCallBack(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> stopLiveStream() {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIValueCallBack<TUILiveStatisticsData>> stopLiveStreamV2() {
    return Future.value(TUIValueCallBack(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIValueCallBack<TUIRoomInfo>> joinLiveStream(String roomId) {
    return Future.value(TUIValueCallBack(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIValueCallBack<TUILiveInfo>> joinLiveStreamV2(String roomId) {
    return Future.value(TUIValueCallBack(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> leaveLiveStream() {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  ///*** CoGuest ***///

  @override
  Future<TUIActionCallback> requestIntraRoomConnection(
      {required String userId, int seatIndex = -1, required int timeout, required bool openCamera}) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> cancelIntraRoomConnection(String userId) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> respondIntraRoomConnection(String userId, bool isAccepted) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> disconnectUser(String userId) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> terminateIntraRoomConnection() {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  ///*** CoHost ***///

  @override
  Future<TUIValueCallBack<TUIConnectionCode?>> requestCrossRoomConnection(String roomId, int timeout) {
    return Future.value(TUIValueCallBack(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> cancelCrossRoomConnection(String roomId) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> respondToCrossRoomConnection(String roomId, bool isAccepted) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> terminateCrossRoomConnection() {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  void registerConnectionObserver(ConnectionObserver observer) {}

  @override
  void unregisterConnectionObserver(ConnectionObserver observer) {}

  ///*** Battle ***///

  @override
  Future<TUIValueCallBack<BattleRequestCallback>> requestBattle(
      TUIBattleConfig config, List<String> userIdList, int timeout) {
    return Future.value(TUIValueCallBack(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> cancelBattle(String battleId, List<String> userIdList) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> respondToBattle(String battleId, bool isAccepted) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  Future<TUIActionCallback> terminateBattle(String battleId) {
    return Future.value(TUIActionCallback(code: TUIError.success, message: ""));
  }

  @override
  void registerBattleObserver(BattleObserver observer) {}

  @override
  void unregisterBattleObserver(BattleObserver observer) {}
}
