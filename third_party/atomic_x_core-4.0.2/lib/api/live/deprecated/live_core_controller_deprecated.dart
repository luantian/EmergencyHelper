import 'package:rtc_room_engine/api/extension/tui_live_battle_manager.dart';
import 'package:rtc_room_engine/api/extension/tui_live_connection_manager.dart';
import 'package:rtc_room_engine/api/extension/tui_live_list_manager.dart';
import 'package:rtc_room_engine/api/room/tui_room_define.dart';

import 'live_core_widget_define_deprecated.dart';

@Deprecated("Deprecated")
abstract class LiveCoreControllerDeprecated {

  CoreState getCoreState();

  ///*** Device ***///

  Future<TUIActionCallback> startCamera(bool useFrontCamera);

  void switchCamera(bool isFront);

  void stopCamera();

  void enableMirror(bool enable);

  Future<TUIActionCallback> startMicrophone();

  Future<TUIActionCallback> unmuteMicrophone();

  void muteMicrophone();

  void stopMicrophone();

  ///*** Room ***///

  Future<TUIValueCallBack<TUIRoomInfo>> startLiveStream(TUIRoomInfo roomInfo);

  Future<TUIValueCallBack<TUILiveInfo>> startLiveStreamV2(TUILiveInfo liveInfo);

  Future<TUIActionCallback> stopLiveStream();

  Future<TUIValueCallBack<TUILiveStatisticsData>> stopLiveStreamV2();

  Future<TUIValueCallBack<TUIRoomInfo>> joinLiveStream(String roomId);

  Future<TUIValueCallBack<TUILiveInfo>> joinLiveStreamV2(String roomId);

  Future<TUIActionCallback> leaveLiveStream();

  ///*** CoGuest ***///

  Future<TUIActionCallback> requestIntraRoomConnection(
      {required String userId, int seatIndex = -1, required int timeout, required bool openCamera});

  Future<TUIActionCallback> cancelIntraRoomConnection(String userId);

  Future<TUIActionCallback> respondIntraRoomConnection(String userId, bool isAccepted);

  Future<TUIActionCallback> disconnectUser(String userId);

  Future<TUIActionCallback> terminateIntraRoomConnection();

  ///*** CoHost ***///

  Future<TUIValueCallBack<TUIConnectionCode?>> requestCrossRoomConnection(String roomId, int timeout);

  Future<TUIActionCallback> cancelCrossRoomConnection(String roomId);

  Future<TUIActionCallback> respondToCrossRoomConnection(String roomId, bool isAccepted);

  Future<TUIActionCallback> terminateCrossRoomConnection();

  void registerConnectionObserver(ConnectionObserver observer);

  void unregisterConnectionObserver(ConnectionObserver observer);

  ///*** Battle ***///

  Future<TUIValueCallBack<BattleRequestCallback>> requestBattle(
      TUIBattleConfig config, List<String> userIdList, int timeout);

  Future<TUIActionCallback> cancelBattle(String battleId, List<String> userIdList);

  Future<TUIActionCallback> respondToBattle(String battleId, bool isAccepted);

  Future<TUIActionCallback> terminateBattle(String battleId);

  void registerBattleObserver(BattleObserver observer);

  void unregisterBattleObserver(BattleObserver observer);
}
