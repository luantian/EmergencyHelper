part of '../../api/device/device_store.dart';

class _DeviceStateImpl implements DeviceState {
  final _microphoneStatus = ValueNotifier(DeviceStatus.off);
  final _cameraStatus = ValueNotifier(DeviceStatus.off);
  final _isFrontCamera = ValueNotifier(true);
  final _currentAudioRoute = ValueNotifier(AudioRoute.speakerphone);
  final _captureVolume = ValueNotifier(100);
  final _microphoneLastError = ValueNotifier<DeviceError>(DeviceError.noError);
  final _currentMicVolume = ValueNotifier<int>(0);
  final _outputVolume = ValueNotifier<int>(100);
  final _cameraLastError = ValueNotifier<DeviceError>(DeviceError.noError);
  final _localMirrorType = ValueNotifier<MirrorType>(MirrorType.auto);
  final _localVideoQuality = ValueNotifier<VideoQuality>(VideoQuality.quality720P);
  final _screenStatus = ValueNotifier<DeviceStatus>(DeviceStatus.off);
  final _networkInfo = ValueNotifier<NetworkInfo>(NetworkInfo());

  @override
  ValueListenable<DeviceStatus> get microphoneStatus => _microphoneStatus;

  @override
  ValueListenable<DeviceStatus> get cameraStatus => _cameraStatus;

  @override
  ValueListenable<bool> get isFrontCamera => _isFrontCamera;

  @override
  ValueListenable<AudioRoute> get currentAudioRoute => _currentAudioRoute;

  @override
  ValueListenable<int> get captureVolume => _captureVolume;

  @override
  ValueListenable<DeviceError> get microphoneLastError => _microphoneLastError;

  @override
  ValueListenable<int> get currentMicVolume => _currentMicVolume;

  @override
  ValueListenable<int> get outputVolume => _outputVolume;

  @override
  ValueListenable<DeviceError> get cameraLastError => _cameraLastError;

  @override
  ValueListenable<MirrorType> get localMirrorType => _localMirrorType;

  @override
  ValueListenable<VideoQuality> get localVideoQuality => _localVideoQuality;

  @override
  ValueListenable<DeviceStatus> get screenStatus => _screenStatus;

  @override
  ValueListenable<NetworkInfo> get networkInfo => _networkInfo;
}

class _DeviceStoreImpl implements DeviceStore {
  final _DeviceStateImpl stateNotifier = _DeviceStateImpl();

  late _DeviceStore deviceStoreImpl;

  final Map<DeviceFocusOwner, _DeviceStore> deviceStoreMap = {};

  @override
  DeviceState get state => stateNotifier;

  _DeviceStoreImpl() {
    setFocus(DeviceFocusOwner.none);
  }

  @override
  void setFocus(DeviceFocusOwner owner) {
    if (owner == DeviceFocusOwner.call) {
      deviceStoreImpl = deviceStoreMap.putIfAbsent(owner, () {
        return _CallDeviceStoreImpl(stateNotifier);
      });
    } else if (owner == DeviceFocusOwner.live || owner == DeviceFocusOwner.room) {
      deviceStoreImpl = deviceStoreMap.putIfAbsent(owner, () {
        return _LiveAndRoomDeviceStoreImpl(stateNotifier);
      });
    } else {
      deviceStoreImpl = deviceStoreMap.putIfAbsent(owner, () {
        return _NoneDeviceStoreImpl(stateNotifier);
      });
    }
  }

  @override
  Future<CompletionHandler> openLocalMicrophone() {
    return deviceStoreImpl.openLocalMicrophone();
  }

  @override
  void closeLocalMicrophone() {
    deviceStoreImpl.closeLocalMicrophone();
  }

  @override
  Future<CompletionHandler> openLocalCamera(bool isFront) {
    return deviceStoreImpl.openLocalCamera(isFront);
  }

  @override
  void closeLocalCamera() {
    deviceStoreImpl.closeLocalCamera();
  }

  @override
  void switchCamera(bool isFront) {
    deviceStoreImpl.switchCamera(isFront);
  }

  @override
  void setAudioRoute(AudioRoute route) {
    deviceStoreImpl.setAudioRoute(route);
  }

  @override
  void setCaptureVolume(int volume) {
    deviceStoreImpl.setCaptureVolume(volume);
  }

  @override
  void setOutputVolume(int volume) {
    deviceStoreImpl.setOutputVolume(volume);
  }

  @override
  void startScreenShare() {
    deviceStoreImpl.startScreenShare();
  }

  @override
  void stopScreenShare() {
    deviceStoreImpl.stopScreenShare();
  }

  @override
  void switchMirror(MirrorType mirrorType) {
    deviceStoreImpl.switchMirror(mirrorType);
  }

  @override
  void updateVideoQuality(VideoQuality quality) {
    deviceStoreImpl.updateVideoQuality(quality);
  }

  @override
  void reset() {
    deviceStoreImpl.reset();
  }
}

class _CallDeviceStoreImpl extends _DeviceStore {
  _CallDeviceStoreImpl(super.deviceState);

  @override
  DeviceState get state => deviceState;

  @override
  void closeLocalCamera() {
    TUICallEngine.instance.closeCamera();
    deviceState._cameraStatus.value = DeviceStatus.off;
  }

  @override
  void switchCamera(bool isFront) {
    TUICallEngine.instance.switchCamera(isFront ? TUICamera.front : TUICamera.back);
    deviceState._isFrontCamera.value = isFront;
  }

  @override
  void closeLocalMicrophone() {
    TUICallEngine.instance.closeMicrophone();
    deviceState._microphoneStatus.value = DeviceStatus.off;
  }

  @override
  Future<CompletionHandler> openLocalCamera(bool isFront) {
    TUICallEngine.instance.callExperimentalAPI({
      'api': 'openCamera',
      'params': {'isFront': isFront},
    });
    deviceState._cameraStatus.value = DeviceStatus.on;
    deviceState._isFrontCamera.value = isFront;
    return Future.value(CompletionHandler());
  }

  @override
  Future<CompletionHandler> openLocalMicrophone() {
    return TUICallEngine.instance.openMicrophone().then((result) {
      CompletionHandler completionHandler = CompletionHandler();
      DeviceError deviceError = _TypeConvert._deviceErrorFromEngineError(result.code);
      deviceState._microphoneLastError.value = deviceError;
      deviceState._microphoneStatus.value = deviceError == DeviceError.noError ? DeviceStatus.on : DeviceStatus.off;

      completionHandler.errorCode = result.code.rawValue;
      completionHandler.errorMessage = result.message;
      return completionHandler;
    });
  }

  @override
  void setAudioRoute(AudioRoute route) {
    TUIAudioPlaybackDevice audioPlaybackDevice =
        route == AudioRoute.earpiece ? TUIAudioPlaybackDevice.earpiece : TUIAudioPlaybackDevice.speakerphone;
    TUICallEngine.instance.selectAudioPlaybackDevice(audioPlaybackDevice);
    deviceState._currentAudioRoute.value = route;
  }

  @override
  void reset() {
    setAudioRoute(AudioRoute.speakerphone);
    closeLocalMicrophone();
    closeLocalCamera();
    deviceState._cameraLastError.value = DeviceError.noError;
    deviceState._microphoneLastError.value = DeviceError.noError;
    deviceState._isFrontCamera.value = true;
  }
}

class _LiveAndRoomDeviceStoreImpl extends _DeviceStore {
  static final Map<TUINetworkQuality, NetworkQuality> kTUINetworkQualityMap = {
    TUINetworkQuality.qualityExcellent: NetworkQuality.excellent,
    TUINetworkQuality.qualityGood: NetworkQuality.good,
    TUINetworkQuality.qualityPoor: NetworkQuality.poor,
    TUINetworkQuality.qualityBad: NetworkQuality.bad,
    TUINetworkQuality.qualityVeryBad: NetworkQuality.veryBad,
    TUINetworkQuality.qualityDown: NetworkQuality.down,
    TUINetworkQuality.qualityUnknown: NetworkQuality.unknown,
  };

  static final Map<VideoQuality, TUIVideoQuality> kVideoQualityMap = {
    VideoQuality.quality360P: TUIVideoQuality.videoQuality_360P,
    VideoQuality.quality540P: TUIVideoQuality.videoQuality_540P,
    VideoQuality.quality720P: TUIVideoQuality.videoQuality_720P,
    VideoQuality.quality1080P: TUIVideoQuality.videoQuality_1080P,
  };

  final TUIRoomEngine roomEngine = TUIRoomEngine.sharedInstance();

  @override
  DeviceState get state => deviceState;

  final Log _log = Log.getLiveLog('LiveDeviceStoreImpl');

  _LiveAndRoomDeviceStoreImpl(super.deviceState) {
    init();
  }

  void init() {
    roomEngine.addObserver(TUIRoomObserver(
      onUserVideoStateChanged: (String userId, TUIVideoStreamType streamType, bool hasVideo, TUIChangeReason reason) {
        if (userId == TUIRoomEngine.getSelfInfo().userId && streamType == TUIVideoStreamType.screenStream) {
          deviceState._screenStatus.value = hasVideo ? DeviceStatus.on : DeviceStatus.off;
        }
      },
      onUserVoiceVolumeChanged: (Map<String, int> volumeMap) {
        deviceState._currentMicVolume.value = volumeMap[TUIRoomEngine.getSelfInfo().userId] ?? 0;
      },
      onUserNetworkQualityChanged: (Map<String, TUINetwork> networkMap) {
        TUINetwork? tuiNetwork = networkMap[TUIRoomEngine.getSelfInfo().userId];
        if (tuiNetwork != null) {
          deviceState._networkInfo.value = NetworkInfo(
              userID: tuiNetwork.userId,
              quality: kTUINetworkQualityMap[tuiNetwork.quality]!,
              upLoss: tuiNetwork.upLoss,
              downLoss: tuiNetwork.downLoss,
              delay: tuiNetwork.delay);
        }
      },
      onError: (TUIError errorCode, String message) {
        if (errorCode == TUIError.errCameraOccupy) {
          DeviceError deviceError = _TypeConvert._deviceErrorFromEngineError(errorCode);
          deviceState._cameraLastError.value = deviceError;
        } else if (errorCode == TUIError.errStartScreenSharingFailed ||
            errorCode == TUIError.errGetScreenSharingTargetFailed) {
          deviceState._screenStatus.value = DeviceStatus.off;
        }
      },
    ));
  }

  @override
  void closeLocalCamera() {
    _log.info('API closeLocalCamera');
    roomEngine.closeLocalCamera();
    deviceState._cameraStatus.value = DeviceStatus.off;
  }

  @override
  void closeLocalMicrophone() {
    _log.info('API closeLocalMicrophone');
    roomEngine.closeLocalMicrophone();
    deviceState._microphoneStatus.value = DeviceStatus.off;
  }

  @override
  Future<CompletionHandler> openLocalCamera(bool isFront) {
    _log.info('API openLocalCamera isFront:$isFront');
    VideoQuality videoQuality = deviceState._localVideoQuality.value;
    TUIVideoQuality tuiVideoQuality = kVideoQualityMap[videoQuality]!;
    return roomEngine.openLocalCamera(isFront, tuiVideoQuality).then((result) {
      CompletionHandler completionHandler = CompletionHandler();
      DeviceError deviceError = _TypeConvert._deviceErrorFromEngineError(result.code);
      deviceState._cameraLastError.value = deviceError;
      deviceState._cameraStatus.value = deviceError == DeviceError.noError ? DeviceStatus.on : DeviceStatus.off;
      deviceState._isFrontCamera.value = isFront;
      completionHandler.errorCode = result.code.rawValue;
      completionHandler.errorMessage = result.message;
      completionHandler.isSuccess
          ? _log.info('API openLocalCamera onSuccess')
          : _log.info(
              'API openLocalCamera onError code:${completionHandler.errorCode} message:${completionHandler.errorMessage}');
      return completionHandler;
    });
  }

  @override
  Future<CompletionHandler> openLocalMicrophone() {
    _log.info('API openLocalMicrophone');
    return roomEngine.openLocalMicrophone(TUIAudioQuality.audioProfileDefault).then((result) {
      CompletionHandler completionHandler = CompletionHandler();
      DeviceError deviceError = _TypeConvert._deviceErrorFromEngineError(result.code);
      deviceState._microphoneLastError.value = deviceError;
      deviceState._microphoneStatus.value = deviceError == DeviceError.noError ? DeviceStatus.on : DeviceStatus.off;

      completionHandler.errorCode = result.code.rawValue;
      completionHandler.errorMessage = result.message;
      completionHandler.isSuccess
          ? _log.info('API openLocalMicrophone onSuccess')
          : _log.info(
              'API openLocalMicrophone onError code:${completionHandler.errorCode} message:${completionHandler.errorMessage}');
      return completionHandler;
    });
  }

  @override
  void setAudioRoute(AudioRoute route) {
    _log.info('API setAudioRoute route:$route');
    TUIAudioRoute audioRoute = route == AudioRoute.earpiece ? TUIAudioRoute.earpiece : TUIAudioRoute.speakerphone;
    roomEngine.getMediaDeviceManager().setAudioRoute(audioRoute);
    deviceState._currentAudioRoute.value = route;
  }

  @override
  void setCaptureVolume(int volume) {
    _log.info('API setCaptureVolume volume:$volume');
    TRTCCloud.sharedInstance().then((trtcCloud) {
      trtcCloud.setAudioCaptureVolume(volume);
      deviceState._captureVolume.value = volume;
    });
  }

  @override
  void setOutputVolume(int volume) {
    _log.info('API setOutputVolume volume:$volume');
    TRTCCloud.sharedInstance().then((trtcCloud) {
      trtcCloud.getAudioEffectManager().setVoiceCaptureVolume(volume);
      deviceState._outputVolume.value = volume;
    });
  }

  @override
  void startScreenShare() {
    _log.info('API startScreenShare');
    roomEngine.startScreenSharing();
    deviceState._screenStatus.value = DeviceStatus.on;
  }

  @override
  void stopScreenShare() {
    _log.info('API stopScreenShare');
    roomEngine.stopScreenSharing();
    deviceState._screenStatus.value = DeviceStatus.off;
  }

  @override
  void switchCamera(bool isFront) {
    _log.info('API switchCamera isFront:$isFront');
    roomEngine.getMediaDeviceManager().switchCamera(isFront);
    deviceState._isFrontCamera.value = isFront;
  }

  @override
  void switchMirror(MirrorType mirrorType) {
    _log.info('API switchMirror mirrorType:$mirrorType');
    TRTCVideoMirrorType type = TRTCVideoMirrorType.auto;
    if (mirrorType == MirrorType.enable) {
      type = TRTCVideoMirrorType.enable;
    } else if (mirrorType == MirrorType.disable) {
      type = TRTCVideoMirrorType.disable;
    }
    TRTCRenderParams params = TRTCRenderParams(mirrorType: type);
    TRTCCloud.sharedInstance().then((trtcCloud) {
      trtcCloud.setLocalRenderParams(params);
      deviceState._localMirrorType.value = mirrorType;
    });
  }

  @override
  void updateVideoQuality(VideoQuality quality) {
    _log.info('API updateVideoQuality quality:$quality');
    roomEngine.updateVideoQuality(kVideoQualityMap[quality]!);
    deviceState._localVideoQuality.value = quality;
  }

  @override
  void reset() {
    _log.info('API reset');
    setCaptureVolume(100);
    setOutputVolume(100);
    setAudioRoute(AudioRoute.speakerphone);
    switchMirror(MirrorType.auto);
    updateVideoQuality(VideoQuality.quality720P);
    closeLocalMicrophone();
    closeLocalCamera();
    stopScreenShare();
    deviceState._cameraLastError.value = DeviceError.noError;
    deviceState._microphoneLastError.value = DeviceError.noError;
    deviceState._currentMicVolume.value = 0;
    deviceState._isFrontCamera.value = true;
    deviceState._networkInfo.value = NetworkInfo();
  }
}

class _NoneDeviceStoreImpl extends _DeviceStore {
  _NoneDeviceStoreImpl(super.deviceState);
}

class _DeviceStore implements DeviceStore {
  final _DeviceStateImpl deviceState;

  _DeviceStore(this.deviceState);

  @override
  DeviceState get state => deviceState;

  @override
  Future<CompletionHandler> openLocalCamera(bool isFront) {
    CompletionHandler completionHandler = CompletionHandler();
    completionHandler.errorCode = DeviceError.unknownError.value;
    completionHandler.errorMessage = 'focus owner is unknown';
    return Future.value(completionHandler);
  }

  @override
  Future<CompletionHandler> openLocalMicrophone() {
    CompletionHandler completionHandler = CompletionHandler();
    completionHandler.errorCode = DeviceError.unknownError.value;
    completionHandler.errorMessage = 'focus owner is unknown';
    return Future.value(completionHandler);
  }

  @override
  void closeLocalCamera() {}

  @override
  void closeLocalMicrophone() {}

  @override
  void setAudioRoute(AudioRoute route) {}

  @override
  void setCaptureVolume(int volume) {}

  @override
  void setFocus(DeviceFocusOwner owner) {}

  @override
  void setOutputVolume(int volume) {}

  @override
  void startScreenShare() {}

  @override
  void stopScreenShare() {}

  @override
  void switchCamera(bool isFront) {}

  @override
  void switchMirror(MirrorType mirrorType) {}

  @override
  void updateVideoQuality(VideoQuality quality) {}

  @override
  void reset() {}
}

class _TypeConvert {
  static DeviceError _deviceErrorFromEngineError(TUIError error) {
    switch (error) {
      case TUIError.success:
        return DeviceError.noError;
      case TUIError.errCameraOccupy:
        return DeviceError.occupiedError;
      case TUIError.errCameraDeviceEmpty:
      case TUIError.errMicrophoneDeviceEmpty:
        return DeviceError.noDeviceDetected;
      case TUIError.errOpenCameraNeedPermissionFromAdmin:
      case TUIError.errOpenMicrophoneNeedPermissionFromAdmin:
      case TUIError.errOpenScreenShareNeedPermissionFromAdmin:
        return DeviceError.noSystemPermission;
      default:
        return DeviceError.unknownError;
    }
  }
}
