part of 'live_core_controller_impl.dart';

class InternalState {
  final ValueNotifier<Set<String>> hasVideoStreamUserList = ValueNotifier({});
}

/// Work for LiveCoreController and LiveCoreWidget
extension LiveCoreControllerImplInternal on LiveCoreControllerImpl {
  void init() {
    _logInfo("init");
    _subscribeDataBeforeEnterRoom();
  }

  void unInit() {
    _logInfo("unInit");
    _unsubscribeDataBeforeEnterRoom();
  }

  String getLiveID() {
    return _liveID;
  }

  InternalState getInternalState() {
    return _internalState;
  }

  void setVideoView(String userId, int viewID) {
    final roomEngine = TUIRoomEngine.sharedInstance();
    if (userId == TUIRoomEngine.getSelfInfo().userId) {
      roomEngine.setLocalVideoView(viewID);
    } else {
      roomEngine.setRemoteVideoView(userId, TUIVideoStreamType.cameraStream, viewID);
    }
  }

  void startPlayVideo(String userId) {
    final roomEngine = TUIRoomEngine.sharedInstance();
    roomEngine.startPlayRemoteVideo(
      userId,
      TUIVideoStreamType.cameraStream,
      TUIPlayCallback(
        onPlaying: (userId) => {_logInfo("startPlayVideo, userId=$userId, onPlaying")},
        onLoading: (userId) => {_logInfo("startPlayVideo, userId=$userId, onLoading")},
        onPlayError: (userId, code, message) =>
            {_logError("startPlayVideo, userId=$userId, onPlayError, code=$code, message=$message")},
      ),
    );
  }

  void stopPlayVideo(String userId) {
    TUIRoomEngine.sharedInstance().stopPlayRemoteVideo(userId, TUIVideoStreamType.cameraStream);
  }

  void _subscribeDataBeforeEnterRoom() {
    if (getLiveID().isEmpty) return;
    LiveListStore listListStore = StoreFactory.shared.getStore(liveID: _liveID);
    listListStore.liveState.currentLive.addListener(_onCurrentLiveListener);
  }

  void _unsubscribeDataBeforeEnterRoom() {
    if (getLiveID().isEmpty) return;
    LiveListStore listListStore = StoreFactory.shared.getStore(liveID: _liveID);
    listListStore.liveState.currentLive.removeListener(_onCurrentLiveListener);
  }

  void _subscribeDataAfterEnterRoom() {
    if (_roomObserver != null) return;
    _roomObserver = TUIRoomObserver(
      onRoomDismissed: (String roomId, TUIRoomDismissedReason reason) {
        _logInfo("onRoomDismissed, roomId=$roomId, reason=$reason");
        _unsubscribeDataAfterEnterRoom();
      },
      onKickedOutOfRoom: (String roomId, TUIKickedOutOfRoomReason reason, String message) {
        _logInfo("onKickedOutOfRoom, roomId=$roomId, reason=$reason, message=$message");
        _unsubscribeDataAfterEnterRoom();
      },
      onUserVideoStateChanged: (String userId, TUIVideoStreamType streamType, bool hasVideo, TUIChangeReason reason) {
        _logInfo("onUserVideoStateChanged, userId=$userId, streamType=$streamType, hasVideo=$hasVideo, reason=$reason");
        final list = {..._internalState.hasVideoStreamUserList.value};
        final isRemoteUser = userId != TUIRoomEngine.getSelfInfo().userId;
        if (hasVideo) {
          if (isRemoteUser) startPlayVideo(userId);
          list.add(userId);
        } else {
          if (isRemoteUser) stopPlayVideo(userId);
          list.remove(userId);
        }
        _internalState.hasVideoStreamUserList.value = list;
      },
    );

    LiveSeatStoreImpl liveSeatStore = LiveSeatStore.create(getLiveID()) as LiveSeatStoreImpl;
    for (var userID in liveSeatStore.hasVideoStreamUserList) {
      _roomObserver!.onUserVideoStateChanged
          .call(userID, TUIVideoStreamType.cameraStream, true, TUIChangeReason.changedByAdmin);
    }

    TUIRoomEngine.sharedInstance().addObserver(_roomObserver!);
  }

  void _unsubscribeDataAfterEnterRoom() {
    if (_roomObserver == null) return;
    TUIRoomEngine.sharedInstance().removeObserver(_roomObserver!);
    _roomObserver = null;
  }

  void _onCurrentLiveInfoChanged() {
    if (getLiveID().isEmpty) return;
    LiveListStore listListStore = StoreFactory.shared.getStore(liveID: getLiveID());
    LiveInfo liveInfo = listListStore.liveState.currentLive.value;
    if (liveInfo.liveID == getLiveID()) {
      _subscribeDataAfterEnterRoom();
    } else if (liveInfo.liveID.isEmpty) {
      _unsubscribeDataAfterEnterRoom();
    }
  }

  void _logInfo(String message) {
    _logger.info(message);
  }

  void _logError(String message) {
    _logger.error(message);
  }
}
