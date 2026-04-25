import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

import '../common/future_converter.dart';
import '../common/listener_dispatcher.dart';
import '../common/log.dart';
import 'store_factory.dart';

class _BattleStateImpl implements BattleState {
  final ValueNotifier<BattleInfo?> currentBattleInfoValue = ValueNotifier(null);
  final ValueNotifier<List<SeatUserInfo>> battleUsersValue = ValueNotifier([]);
  final ValueNotifier<Map<String, int>> battleScoreValue = ValueNotifier({});

  @override
  ValueListenable<BattleInfo?> get currentBattleInfo => currentBattleInfoValue;

  @override
  ValueListenable<List<SeatUserInfo>> get battleUsers => battleUsersValue;

  @override
  ValueListenable<Map<String, int>> get battleScore => battleScoreValue;
}

class BattleStoreImpl extends BattleStore implements IStore {
  // ignore: unused_field
  final String _liveID;
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUILiveBattleManager _battleManager;
  late final TUILiveBattleObserver _battleObserver;

  final _battleState = _BattleStateImpl();
  final _listenerDispatcher = ListenerDispatcher<BattleListener>();
  
  final Log _log = Log.getLiveLog('BattleStoreImpl');

  BattleStoreImpl(this._liveID) {
    _battleManager = _roomEngine.getLiveBattleManager();
    _initObserver();
  }

  @override
  BattleState get battleState => _battleState;

  @override
  void beforeEnterRoom(String liveID) {
    _battleManager.addObserver(_battleObserver);
  }

  @override
  void afterEnterRoom(LiveInfo liveInfo) {}

  @override
  void leaveRoom(String liveID) {
    _listenerDispatcher.cleanup();
    _battleManager.removeObserver(_battleObserver);
  }

  @override
  void addBattleListener(BattleListener listener) {
    _log.info('API addBattleListener listener:${listener.hashCode}');
    _listenerDispatcher.addListener(listener);
  }

  @override
  void removeBattleListener(BattleListener listener) {
    _log.info('API removeBattleListener listener:${listener.hashCode}');
    _listenerDispatcher.removeListener(listener);
  }

  @override
  Future<BattleRequestCompletionHandler> requestBattle({
    required BattleConfig config,
    required List<String> userIDList,
    required int timeout,
  }) async {
    _log.info('API requestBattle config:$config, userIDList:$userIDList, timeout:$timeout');
    final result = await _battleManager.requestBattle(_engineBattleConfigFromBattleConfig(config), userIDList, timeout);
    var resultHandler = BattleRequestCompletionHandler();
    if (result.code == TUIError.success) {
      _log.info("Response requestBattle onSuccess");
      resultHandler.resultMap = result.data?.requestMap;
      resultHandler.battleInfo = _battleInfoFromEngineBattleInfo(result.data?.battleInfo ?? TUIBattleInfo());
      return resultHandler;
    } else {
      _log.error("Response requestBattle onError code:${result.code.rawValue}, message:${result.message}");
      resultHandler.errorCode = result.code.rawValue;
      resultHandler.errorMessage = result.message;
      return resultHandler;
    }
  }

  @override
  Future<CompletionHandler> cancelBattleRequest({
    required String battleID,
    required List<String> userIDList,
  }) async {
    _log.info('API cancelBattleRequest battleID:$battleID, userIDList:$userIDList ');
    final result = await _battleManager.cancelBattleRequest(battleID, userIDList);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response cancelBattleRequest onSuccess')
      : _log.error('Response cancelBattleRequest onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> acceptBattle(String battleID) async {
    _log.info('API acceptBattle battleID:$battleID');
    final result = await _battleManager.acceptBattle(battleID);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response acceptBattle onSuccess')
      : _log.error('Response acceptBattle onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> rejectBattle(String battleID) async {
    _log.info('API rejectBattle battleID:$battleID');
    final result = await _battleManager.rejectBattle(battleID);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response rejectBattle onSuccess')
      : _log.error('Response rejectBattle onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> exitBattle(String battleID) async {
    _log.info('API exitBattle battleID:$battleID');
    final result = await _battleManager.exitBattle(battleID);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response exitBattle onSuccess')
      : _log.error('Response exitBattle onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }
}

extension BattleStoreImplObserver on BattleStoreImpl {
  void _initObserver() {
    _battleObserver = TUILiveBattleObserver(
      onBattleStarted: (battleInfo) => _onBattleStarted(battleInfo),
      onBattleEnded: (battleInfo, reason) => _onBattleEnded(battleInfo, reason),
      onUserJoinBattle: (battleId, battleUser) => _onUserJoinBattle(battleId, battleUser),
      onUserExitBattle: (battleId, battleUser) => _onUserExitBattle(battleId, battleUser),
      onBattleScoreChanged: (battleId, battleUserList) => _onBattleScoreChanged(battleId, battleUserList),
      onBattleRequestReceived: (battleInfo, inviter, invitee) => _onBattleRequestReceived(battleInfo, inviter, invitee),
      onBattleRequestCancelled: (battleInfo, inviter, invitee) =>
          _onBattleRequestCancelled(battleInfo, inviter, invitee),
      onBattleRequestTimeout: (battleInfo, inviter, invitee) => _onBattleRequestTimeout(battleInfo, inviter, invitee),
      onBattleRequestAccept: (battleInfo, inviter, invitee) => _onBattleRequestAccept(battleInfo, inviter, invitee),
      onBattleRequestReject: (battleInfo, inviter, invitee) => _onBattleRequestReject(battleInfo, inviter, invitee),
    );
  }

  void _onBattleStarted(TUIBattleInfo battleInfo) {
    _log.info('Observer onBattleStarted battleId:${battleInfo.battleId}');
    final inviter = _seatUserInfoFromBattleUser(battleInfo.inviter);
    final inviteeList = battleInfo.inviteeList.map((user) => _seatUserInfoFromBattleUser(user)).toList();
    final info = _battleInfoFromEngineBattleInfo(battleInfo);
    _battleState.battleUsersValue.value = [inviter, ...inviteeList];
    _battleState.currentBattleInfoValue.value = info;
    _listenerDispatcher.notify((listener) => listener.onBattleStarted?.call(info, inviter, inviteeList));
  }

  void _onBattleEnded(TUIBattleInfo battleInfo, TUIBattleStoppedReason reason) {
     _log.info('Observer onBattleEnded battleInfo:$battleInfo, reason:$reason');
    _battleState.currentBattleInfoValue.value = null;
    _battleState.battleUsersValue.value = [];
    final convertedBattleInfo = _battleInfoFromEngineBattleInfo(battleInfo);
    final convertedReason = _battleEndedReasonFromEngineReason(reason);
    _listenerDispatcher.notify((listener) => listener.onBattleEnded?.call(convertedBattleInfo, convertedReason));
  }

  void _onUserJoinBattle(String battleID, TUIBattleUser battleUser) {
     _log.info('Observer onUserJoinBattle battleID:$battleID, battleUser:$battleUser');
    final convertedUser = _seatUserInfoFromBattleUser(battleUser);
    _battleState.battleUsersValue.value = [..._battleState.battleUsersValue.value, convertedUser];
    _listenerDispatcher.notify((listener) => listener.onUserJoinBattle?.call(battleID, convertedUser));
  }

  void _onUserExitBattle(String battleID, TUIBattleUser battleUser) {
    _log.info('Observer onUserExitBattle battleID:$battleID, battleUser:$battleUser');
    _battleState.battleUsersValue.value =
        _battleState.battleUsersValue.value.where((item) => item.userID != battleUser.userId).toList();
    _battleState.battleScoreValue.value = Map.from(_battleState.battleScoreValue.value)..remove(battleID);
    final convertedUser = _seatUserInfoFromBattleUser(battleUser);
    _listenerDispatcher.notify((listener) => listener.onUserExitBattle?.call(battleID, convertedUser));
  }

  void _onBattleScoreChanged(String battleID, List<TUIBattleUser> battleUserList) {
    _log.info('Observer onBattleScoreChanged battleID:$battleID, battleUserList:$battleUserList');
    final scores = {for (var user in battleUserList) user.userId: user.score};
    _battleState.battleScoreValue.value = scores;
  }

  void _onBattleRequestReceived(TUIBattleInfo battleInfo, TUIBattleUser inviter, TUIBattleUser invitee) {
    _log.info('Observer onBattleRequestReceived battleInfo:$battleInfo, inviter:$inviter, invitee:$invitee');
    final convertedInviter = _seatUserInfoFromBattleUser(inviter);
    final convertedInvitee = _seatUserInfoFromBattleUser(invitee);
    _listenerDispatcher.notify(
      (listener) => listener.onBattleRequestReceived?.call(
        battleInfo.battleId,
        convertedInviter,
        convertedInvitee,
      ),
    );
  }

  void _onBattleRequestCancelled(TUIBattleInfo battleInfo, TUIBattleUser inviter, TUIBattleUser invitee) {
     _log.info('Observer _onBattleRequestCancelled battleInfo:$battleInfo, inviter:$inviter, invitee:$invitee');
    final convertedInviter = _seatUserInfoFromBattleUser(inviter);
    final convertedInvitee = _seatUserInfoFromBattleUser(invitee);
    _listenerDispatcher.notify(
      (listener) => listener.onBattleRequestCancelled?.call(
        battleInfo.battleId,
        convertedInviter,
        convertedInvitee,
      ),
    );
  }

  void _onBattleRequestTimeout(TUIBattleInfo battleInfo, TUIBattleUser inviter, TUIBattleUser invitee) {
     _log.info('Observer onBattleRequestTimeout battleInfo:$battleInfo, inviter:$inviter, invitee:$invitee');
    final convertedInviter = _seatUserInfoFromBattleUser(inviter);
    final convertedInvitee = _seatUserInfoFromBattleUser(invitee);
    _listenerDispatcher.notify((listener) => listener.onBattleRequestTimeout?.call(
          battleInfo.battleId,
          convertedInviter,
          convertedInvitee,
        ));
  }

  void _onBattleRequestAccept(TUIBattleInfo battleInfo, TUIBattleUser inviter, TUIBattleUser invitee) {
    _log.info('Observer onBattleRequestAccept battleInfo:$battleInfo, inviter:$inviter, invitee:$invitee');
    final convertedInviter = _seatUserInfoFromBattleUser(inviter);
    final convertedInvitee = _seatUserInfoFromBattleUser(invitee);
    _listenerDispatcher.notify(
      (listener) => listener.onBattleRequestAccept?.call(
        battleInfo.battleId,
        convertedInviter,
        convertedInvitee,
      ),
    );
  }

  void _onBattleRequestReject(TUIBattleInfo battleInfo, TUIBattleUser inviter, TUIBattleUser invitee) {
    _log.info('Observer onBattleRequestReject battleInfo:$battleInfo, inviter:$inviter, invitee:$invitee');
    final convertedInviter = _seatUserInfoFromBattleUser(inviter);
    final convertedInvitee = _seatUserInfoFromBattleUser(invitee);
    _listenerDispatcher.notify(
          (listener) => listener.onBattleRequestReject?.call(
        battleInfo.battleId,
        convertedInviter,
        convertedInvitee,
      ),
    );
  }

  SeatUserInfo _seatUserInfoFromBattleUser(TUIBattleUser user) {
    return SeatUserInfo(liveID: user.roomId, userID: user.userId, userName: user.userName, avatarURL: user.avatarUrl);
  }

  TUIBattleConfig _engineBattleConfigFromBattleConfig(BattleConfig config) {
    var resConfig = TUIBattleConfig();
    resConfig.duration = config.duration;
    resConfig.needResponse = config.needResponse;
    resConfig.extensionInfo = config.extensionInfo;
    return resConfig;
  }

  BattleConfig _battleConfigFromEngineBattleConfig(TUIBattleConfig config) {
    return BattleConfig(
      duration: config.duration,
      needResponse: config.needResponse,
      extensionInfo: config.extensionInfo,
    );
  }

  BattleInfo _battleInfoFromEngineBattleInfo(TUIBattleInfo battleInfo) {
    return BattleInfo(
      battleID: battleInfo.battleId,
      config: _battleConfigFromEngineBattleConfig(battleInfo.config),
      startTime: battleInfo.startTime,
      endTime: battleInfo.endTime,
    );
  }

  BattleEndedReason _battleEndedReasonFromEngineReason(TUIBattleStoppedReason reason) {
    return reason == TUIBattleStoppedReason.otherExit ? BattleEndedReason.allMemberExit : BattleEndedReason.timeOver;
  }
}
