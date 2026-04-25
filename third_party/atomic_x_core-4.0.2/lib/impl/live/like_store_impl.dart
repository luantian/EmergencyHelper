import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

import '../common/future_converter.dart';
import '../common/listener_dispatcher.dart';
import '../common/log.dart';
import '../common/type_converter.dart';
import 'store_factory.dart';

class _LikeStateImpl implements LikeState {
  final ValueNotifier<int> totalLikeCountValue = ValueNotifier<int>(0);

  @override
  ValueListenable<int> get totalLikeCount => totalLikeCountValue;
}

class LikeStoreImpl extends LikeStore implements IStore {
  final String _liveID;
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUILiveGiftManager _likeManager;
  late final TUILiveGiftObserver _likeObserver;

  final _likeState = _LikeStateImpl();
  final _listenerDispatcher = ListenerDispatcher<LikeListener>();
  
  final Log _log = Log.getLiveLog('LikeStoreImpl');

  LikeStoreImpl(this._liveID) {
    _likeManager = _roomEngine.getExtension(TUIExtensionType.liveGiftManager);
    _initObserver();
  }

  @override
  LikeState get likeState => _likeState;

  @override
  void beforeEnterRoom(String liveID) {
    _likeManager.addObserver(_likeObserver);
  }

  @override
  void afterEnterRoom(LiveInfo liveInfo) {}

  @override
  void leaveRoom(String liveID) {
    _likeManager.removeObserver(_likeObserver);
    _listenerDispatcher.cleanup();
  }

  @override
  void addLikeListener(LikeListener listener) {
    _listenerDispatcher.addListener(listener);
  }

  @override
  void removeLikeListener(LikeListener listener) {
    _listenerDispatcher.removeListener(listener);
  }

  @override
  Future<CompletionHandler> sendLike(int count) async {
    _log.info('API sendLike count:$count');
    final result = await _likeManager.sendLike(_liveID, count);
    final handler = handleCallback(result);
    handler.isSuccess 
      ? _log.info('Response sendLike onSuccess')
      : _log.error('Response sendLike onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }
}

extension LikeStoreImplObserver on LikeStoreImpl {
  void _initObserver() {
    _likeObserver = TUILiveGiftObserver(
      onReceiveLikesMessage: (roomId, totalLikesReceived, sender) =>
          _onReceiveLikesMessage(roomId, totalLikesReceived, sender),
    );
  }

  void _onReceiveLikesMessage(String roomId, int totalLikesReceived, TUIUserInfo sender) {
    _log.info('Observer onReceiveLikesMessage roomId:$roomId, totalLikesReceived:$totalLikesReceived, sender:${sender.userId}');
    _likeState.totalLikeCountValue.value = totalLikesReceived;
    final convertedSender = TypeConverter.liveUserInfoFromEngineUserInfo(sender);
    _listenerDispatcher.notify((listener) {
      listener.onReceiveLikesMessage?.call(roomId, totalLikesReceived, convertedSender);
    });
  }
}
