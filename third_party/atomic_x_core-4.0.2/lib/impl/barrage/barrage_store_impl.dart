import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

import '../common/future_converter.dart';
import '../common/log.dart';
import '../common/type_converter.dart';
import '../live/store_factory.dart';

class _BarrageStateImpl implements BarrageState {
  final ValueNotifier<List<Barrage>> messageListValue = ValueNotifier([]);
  final ValueNotifier<bool> allowSendMessageValue = ValueNotifier(true);

  @override
  ValueListenable<List<Barrage>> get messageList => messageListValue;

  // @override
  // Not implemented, marked as private. Allowed status is not fetched on room entry.
  // ignore: unused_element
  ValueListenable<bool> get _allowSendMessage => allowSendMessageValue;
}

class BarrageStoreImpl extends BarrageStore implements IStore {
  final String _liveID;
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUIRoomObserver _roomEngineObserver;

  final _BarrageStateImpl _barrageState = _BarrageStateImpl();

  final _selfUserId = TUIRoomEngine.getSelfInfo().userId;
  static const int _maxMessageCount = 1000;
  
  final Log _log = Log.getLiveLog('BarrageStoreImpl');

  BarrageStoreImpl(this._liveID) {
    _initObserver();
  }

  @override
  BarrageState get barrageState => _barrageState;

  @override
  void beforeEnterRoom(String liveID) {
    _roomEngine.addObserver(_roomEngineObserver);
  }

  @override
  void afterEnterRoom(LiveInfo liveInfo) {}

  @override
  void leaveRoom(String liveID) {
    _roomEngine.removeObserver(_roomEngineObserver);
  }

  @override
  Future<CompletionHandler> sendTextMessage({
    String? text,
    Map<String, String>? extensionInfo,
  }) async {
    _log.info('API sendTextMessage text:${text ?? ''}');
    final message = TUIRoomTextMessage()
      ..textContent = text ?? ''
      ..extensionInfo = extensionInfo;
    final result = await _roomEngine.sendTextMessage(message);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response sendTextMessage onSuccess')
      : _log.error('Response sendTextMessage onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> sendCustomMessage({
    required String businessID,
    required String data,
  }) async {
    _log.info('API sendCustomMessage businessID:$businessID');
    final message = TUIRoomCustomMessage()
      ..businessId = businessID
      ..data = data;
    final result = await _roomEngine.sendCustomMessage(message);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response sendCustomMessage onSuccess')
      : _log.error('Response sendCustomMessage onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  void appendLocalTip(Barrage message) {
    _addMessage(message);
  }

  void _addMessage(Barrage barrage) {
    final updatedList = [..._barrageState.messageListValue.value, barrage];
    if (updatedList.length >= _maxMessageCount) {
      updatedList.removeAt(0);
    }
    _barrageState.messageListValue.value = updatedList;
  }
}

extension BarrageStoreImplObserver on BarrageStoreImpl {
  void _initObserver() {
    _roomEngineObserver = TUIRoomObserver(
      onReceiveTextMessage: (message) => _onReceiveTextMessage(message),
      onReceiveCustomMessage: (message) => _onReceiveCustomMessage(message),
      onSendMessageForAllUserDisableChanged: (roomId, isDisable) =>
          _onSendMessageForAllUserDisableChanged(roomId, isDisable),
      onSendMessageForUserDisableChanged: (roomId, userId, isDisable) =>
          _onSendMessageForUserDisableChanged(roomId, userId, isDisable),
    );
  }

  void _onReceiveTextMessage(TUIRoomTextMessage message) {
    if (message.roomId != _liveID) return;
    _log.info('Observer onReceiveTextMessage sender:${message.sender?.userId ?? ''}');
    _addMessage(_barrageFromTextMessage(message));
  }

  void _onReceiveCustomMessage(TUIRoomCustomMessage message) {
    if (message.roomId != _liveID) return;
    _log.info('Observer onReceiveCustomMessage sender:${message.sender?.userId ?? ''}, businessId:${message.businessId}');
    _addMessage(_barrageFromCustomMessage(message));
  }

  void _onSendMessageForAllUserDisableChanged(String roomId, bool isDisable) {
    if (roomId != _liveID) return;
     _log.info('Observer onSendMessageForAllUserDisableChanged roomId:$roomId, isDisable:$isDisable');
    _barrageState.allowSendMessageValue.value = !isDisable;
  }

  void _onSendMessageForUserDisableChanged(String roomId, String userId, bool isDisable) {
    if (roomId != _liveID || userId != _selfUserId) return;
     _log.info('Observer onSendMessageForUserDisableChanged roomId:$roomId, userId:$userId, isDisable:$isDisable');
    _barrageState.allowSendMessageValue.value = !isDisable;
  }

  Barrage _barrageFromTextMessage(TUIRoomTextMessage message) {
    return Barrage(
      liveID: message.roomId,
      sender: TypeConverter.liveUserInfoFromEngineUserInfo(message.sender),
      sequence: message.sequence,
      timestampInSecond: message.timestampInSecond,
      messageType: BarrageType.text,
      textContent: message.textContent,
      extensionInfo: message.extensionInfo,
    );
  }

  Barrage _barrageFromCustomMessage(TUIRoomCustomMessage message) {
    return Barrage(
      liveID: message.roomId,
      sender: TypeConverter.liveUserInfoFromEngineUserInfo(message.sender),
      sequence: message.sequence,
      timestampInSecond: message.timestampInSecond,
      messageType: BarrageType.custom,
      businessID: message.businessId,
      data: message.data,
    );
  }
}
