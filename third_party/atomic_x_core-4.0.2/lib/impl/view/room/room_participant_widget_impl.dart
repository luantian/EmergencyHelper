part of 'package:atomic_x_core/api/view/room/room_participant_widget.dart';

class _ViewConstants {
  static const double clickActionMaxMoveDistance = 10.0;
  static const double scaleMaximum = 5.0;
  static const double scaleMinimum = 1.0;
}

class _VideoStreamConstants {
  static const double hdThresholdWidthPx = 960.0;
  static const int maxHdStreamCount = 5;
}

class _RoomParticipantWidgetState extends State<RoomParticipantWidget> {
  final _log = Log.getRoomLog('RoomParticipantWidgetImpl');

  Offset? _touchDownPoint;
  bool _isClickAction = false;
  int _pointerCount = 0;

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _initialScale = 1.0;
  Offset _initialOffset = Offset.zero;
  bool _isScaleGestureActive = false;
  Matrix4 _transformMatrix = Matrix4.identity();

  int? _viewID;
  TRTCCloud? _trtcCloud;
  TUIRoomEngine? _roomEngine;

  double _lastWidth = 0.0;

  RoomParticipantControllerImpl get _controller => widget.controller as RoomParticipantControllerImpl;

  @override
  void initState() {
    super.initState();
    _log.info('RoomParticipantView init ${_controller._participant.userID}');
    _initializeEngine();

    _controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _log.info('RoomParticipantView dispose ${_controller._participant.userID}');
    _controller.removeListener(_onControllerUpdate);
    _destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth != _lastWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onLayoutWidthChanged(constraints.maxWidth, _lastWidth);
            _lastWidth = constraints.maxWidth;
          });
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent event) {
            _incrementPointerCount();
            if (_pointerCount == 1) {
              _touchDownPoint = event.position;
              _isClickAction = true;
            } else {
              _isClickAction = false;
            }
          },
          onPointerMove: (PointerMoveEvent event) {
            if (_pointerCount == 1 && _touchDownPoint != null) {
              final distance = (event.position - _touchDownPoint!).distance;
              if (distance >= _ViewConstants.clickActionMaxMoveDistance) {
                _isClickAction = false;
              }
            }
          },
          onPointerUp: (PointerUpEvent event) {
            if (_pointerCount == 1 && _isClickAction) {
              if (_controller._streamType == VideoStreamType.screen && _controller._clickAction != null) {
                _controller._clickAction!();
              }
            }

            _decrementPointerCount();
          },
          onPointerCancel: (PointerCancelEvent event) {
            _decrementPointerCount();
          },
          child: RawGestureDetector(
            gestures: _controller._streamType == VideoStreamType.screen
                ? {
                    _ScreenShareScaleRecognizer: GestureRecognizerFactoryWithHandlers<_ScreenShareScaleRecognizer>(
                      () => _ScreenShareScaleRecognizer(),
                      (_ScreenShareScaleRecognizer instance) {
                        instance
                          ..onStart = _onScaleStart
                          ..onUpdate = _onScaleUpdate
                          ..onEnd = _onScaleEnd;
                      },
                    ),
                  }
                : {
                    ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                      () => ScaleGestureRecognizer(),
                      (ScaleGestureRecognizer instance) {
                        instance
                          ..onStart = _onScaleStart
                          ..onUpdate = _onScaleUpdate
                          ..onEnd = _onScaleEnd;
                      },
                    ),
                  },
            behavior: HitTestBehavior.opaque,
            child: Transform(
              transform: _transformMatrix,
              child: _buildVideoView(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoView() {
    return VideoView(
      onViewCreated: (viewID) {
        _viewID = viewID;
        if (_isReady()) {
          _initView(_controller._streamType, _controller._participant);
        }
      },
      onViewDisposed: (id) {
        _onVideoViewDisposed();
      },
    );
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});

      if (!_controller._isActive) {
        _stop();
        return;
      }

      if (_isReady()) {
        _initView(_controller._streamType, _controller._participant);
      }
    }
  }

  Future<void> _initializeEngine() async {
    _trtcCloud = await TRTCCloud.sharedInstance();
    _roomEngine = TUIRoomEngine.sharedInstance();

    if (_isReady() && _viewID != null) {
      _initView(_controller._streamType, _controller._participant);
    }
  }

  bool _isReady() {
    return _controller._isActive && _trtcCloud != null && _roomEngine != null;
  }

  void _initView(VideoStreamType streamType, RoomParticipant participant) {
    final loginUserID = LoginStore.shared.loginState.loginUserInfo?.userID ?? '';

    if (loginUserID.isEmpty) {
      _log.warn('Invalid login userId');
      return;
    }
    if (_controller._fillMode != null) {
      _applyFillMode(streamType, participant, _controller._fillMode!);
    }

    final userID = participant.userID;
    if (userID == loginUserID) {
      if (_viewID != null) {
        VideoStreamManager.shared.setLocalVideoView(_viewID!);
      }
      return;
    }

    switch (streamType) {
      case VideoStreamType.camera:
        _initRemoteCameraView(participant);
        break;
      case VideoStreamType.screen:
        _initRemoteScreenShareView(participant);
        break;
    }
  }

  void _onVideoViewDisposed() {
    final userID = _controller._participant.userID;
    final currentUserID = LoginStore.shared.loginState.loginUserInfo?.userID;
    if (userID == currentUserID || _viewID == null) {
      _viewID = null;
      return;
    }

    final videoManager = VideoStreamManager.shared;
    final viewID = _viewID!;

    switch (_controller._streamType) {
      case VideoStreamType.camera:
        videoManager.stopPlayCameraStream(userID: userID, viewID: viewID);
        break;
      case VideoStreamType.screen:
        videoManager.stopPlayScreenShareStream(userID: userID, viewID: viewID);
        break;
    }

    _viewID = null;
  }

  void _initRemoteCameraView(RoomParticipant participant) {
    if (participant.cameraStatus == DeviceStatus.on && _viewID != null) {
      VideoStreamManager.shared
          .startPlayCameraStream(userID: participant.userID, viewID: _viewID!, viewWidth: _lastWidth);
    } else if (_viewID != null) {
      VideoStreamManager.shared.stopPlayCameraStream(userID: participant.userID, viewID: _viewID!);
    }
  }

  void _initRemoteScreenShareView(RoomParticipant participant) {
    if (participant.screenShareStatus == DeviceStatus.on && _viewID != null) {
      VideoStreamManager.shared.startPlayScreenShareStream(userID: participant.userID, viewID: _viewID!);
    } else if (_viewID != null) {
      VideoStreamManager.shared.stopPlayScreenShareStream(userID: participant.userID, viewID: _viewID!);
    }
  }

  void _applyFillMode(VideoStreamType streamType, RoomParticipant participant, FillMode fillMode) {
    VideoStreamManager.shared.setFillMode(userID: participant.userID, streamType: streamType, fillMode: fillMode);
  }

  void _stop() {
    final selfUserId = LoginStore.shared.loginState.loginUserInfo?.userID;
    if (selfUserId == null || selfUserId.isEmpty) {
      _log.warn('Invalid login userId');
      return;
    }

    if (_controller._participant.userID == selfUserId) {
      VideoStreamManager.shared.setLocalVideoView(0);
      return;
    }
    if (_viewID == null) return;
    switch (_controller._streamType) {
      case VideoStreamType.camera:
        VideoStreamManager.shared.stopPlayCameraStream(userID: _controller._participant.userID, viewID: _viewID!);
        break;
      case VideoStreamType.screen:
        VideoStreamManager.shared.stopPlayScreenShareStream(userID: _controller._participant.userID, viewID: _viewID!);
        break;
    }
  }

  void _destroy() {
    final userID = _controller._participant.userID;

    if (userID.isEmpty || _viewID == null) {
      return;
    }

    switch (_controller._streamType) {
      case VideoStreamType.camera:
        VideoStreamManager.shared.stopPlayCameraStream(userID: userID, viewID: _viewID!);
        break;
      case VideoStreamType.screen:
        VideoStreamManager.shared.stopPlayScreenShareStream(userID: userID, viewID: _viewID!);
        break;
    }
  }

  void _onLayoutWidthChanged(double width, double oldWidth) {
    if (width != oldWidth && _isReady()) {
      final userID = _controller._participant.userID;
      final needSwitch = VideoStreamManager.shared.needSwitchStreamType(userID: userID, viewWidth: width);
      if (needSwitch && _viewID != null) {
        VideoStreamManager.shared.startPlayCameraStream(userID: userID, viewID: _viewID!, viewWidth: width);
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_controller._streamType != VideoStreamType.screen || _isScaleGestureActive) return;

    _initialScale = _scale;
    _initialOffset = _offset;
    _isScaleGestureActive = true;

    if (details.pointerCount == 1) {
      _isClickAction = true;
      _touchDownPoint = details.focalPoint;
    } else {
      _isClickAction = false;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_controller._streamType != VideoStreamType.screen) return;

    final size = context.size;
    if (size == null) return;

    if (details.pointerCount == 2 && !_isScaleGestureActive) {
      _initialScale = _scale;
      _initialOffset = _offset;
      _isScaleGestureActive = true;
      _isClickAction = false;
    }

    if (details.pointerCount == 1) {
      _handleSingleFingerDrag(details, size);
    } else if (details.pointerCount == 2) {
      _isClickAction = false;
      _handleTwoFingerScaling(details, size);
    } else if (details.pointerCount > 2) {
      _isClickAction = false;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_controller._streamType != VideoStreamType.screen) return;
    _resetTouchState();
  }

  void _handleSingleFingerDrag(ScaleUpdateDetails details, Size size) {
    if (_scale <= 1.0 || _touchDownPoint == null) return;

    final deltaX = details.focalPoint.dx - _touchDownPoint!.dx;
    final deltaY = details.focalPoint.dy - _touchDownPoint!.dy;

    if (deltaX.abs() >= _ViewConstants.clickActionMaxMoveDistance ||
        deltaY.abs() >= _ViewConstants.clickActionMaxMoveDistance) {
      _isClickAction = false;

      setState(() {
        _offset = _clampOffset(
          _initialOffset + Offset(deltaX, deltaY),
          _scale,
          size,
        );
        _updateTransformMatrix(size);
      });
    }
  }

  void _handleTwoFingerScaling(ScaleUpdateDetails details, Size size) {
    setState(() {
      final newScale = (_initialScale * details.scale).clamp(
        _ViewConstants.scaleMinimum,
        _ViewConstants.scaleMaximum,
      );

      // Calculate the focal point relative to the view center
      final focalPointX = details.localFocalPoint.dx - size.width / 2;
      final focalPointY = details.localFocalPoint.dy - size.height / 2;

      if (newScale > 1.0) {
        // Calculate new offset to keep the focal point stationary during scaling
        final scaleDelta = newScale / _initialScale;
        _offset = Offset(
          _initialOffset.dx + focalPointX - focalPointX * scaleDelta,
          _initialOffset.dy + focalPointY - focalPointY * scaleDelta,
        );
        _offset = _clampOffset(_offset, newScale, size);
      } else {
        _offset = Offset.zero;
      }

      _scale = newScale;
      _updateTransformMatrix(size);
    });
  }

  void _updateTransformMatrix(Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    _transformMatrix = Matrix4.identity()
      ..translate(centerX, centerY)
      ..translate(_offset.dx, _offset.dy)
      ..scale(_scale)
      ..translate(-centerX, -centerY);
  }

  Offset _clampOffset(Offset offset, double scale, Size size) {
    if (scale <= 1.0) return Offset.zero;

    final maxOffsetX = (size.width * (scale - 1.0)) / 2;
    final maxOffsetY = (size.height * (scale - 1.0)) / 2;

    return Offset(
      offset.dx.clamp(-maxOffsetX, maxOffsetX),
      offset.dy.clamp(-maxOffsetY, maxOffsetY),
    );
  }

  void _incrementPointerCount() {
    _pointerCount++;
  }

  void _decrementPointerCount() {
    if (_pointerCount > 0) _pointerCount--;

    if (_pointerCount == 0) {
      _isScaleGestureActive = false;
      _resetTouchState();
    }
  }

  void _resetTouchState() {
    _isClickAction = false;
    _touchDownPoint = null;
  }
}

class VideoStreamManager {
  static final VideoStreamManager shared = VideoStreamManager._();

  final _log = Log.getRoomLog('VideoStreamManager');

  TRTCCloud? _trtcCloud;
  TUIRoomEngine? _roomEngine;

  final Set<String> _hdStreamUsers = {};
  final Map<String, _VideoStreamInfo> _playCameraStreams = {};
  _VideoStreamInfo? _playScreenStream;

  VideoStreamManager._() {
    _initializeEngine();
  }

  Future<void> _initializeEngine() async {
    _roomEngine = TUIRoomEngine.sharedInstance();
    _trtcCloud = await TRTCCloud.sharedInstance();
  }

  void setLocalVideoView(int viewId) {
    _roomEngine?.setLocalVideoView(viewId);
  }

  void startPlayCameraStream({required String userID, required int viewID, required double viewWidth}) {
    if (userID.isEmpty) {
      _log.warn('Invalid userID provided');
      return;
    }

    final streamType = _decideVideoStreamType(viewWidth);
    _log.info('API startPlayCameraStream userId:$userID, viewID:$viewID, streamType:$streamType');

    final streamInfo = _VideoStreamInfo(userID: userID, streamType: streamType, viewID: viewID);
    if (_playCameraStreams[userID] == streamInfo) {
      _log.info('same user operation, ignore');
      return;
    }

    if (_playCameraStreams[userID]?.streamType == TUIVideoStreamType.cameraStream) {
      _hdStreamUsers.remove(userID);
    }

    _roomEngine?.setRemoteVideoView(userID, streamType, viewID);

    final playCallback = TUIPlayCallback(
      onPlaying: (userId) {
        _log.info('Response startPlayCameraStream onPlaying:userId:$userId');
      },
      onLoading: (userId) {
        _log.info('Response startPlayCameraStream onLoading:userId:$userId');
      },
      onPlayError: (userId, code, message) {
        _log.error('Response startPlayCameraStream onError:userId:$userId, code:$code, message:$message');
      },
    );
    _roomEngine?.startPlayRemoteVideo(userID, streamType, playCallback);

    _playCameraStreams[userID] = streamInfo;
    if (streamType == TUIVideoStreamType.cameraStream) {
      _hdStreamUsers.add(userID);
    }
  }

  void stopPlayCameraStream({required String userID, required int viewID, bool needClearView = false}) {
    _log.info('API stopPlayCameraStream userId:$userID');
    if (userID.isEmpty) {
      _log.warn('Invalid userID provided');
      return;
    }

    final streamInfo = _playCameraStreams[userID];
    if (streamInfo == null) return;

    _roomEngine?.stopPlayRemoteVideo(userID, TUIVideoStreamType.cameraStream);
    _roomEngine?.stopPlayRemoteVideo(userID, TUIVideoStreamType.cameraStreamLow);
    if (needClearView) {
      _roomEngine?.setRemoteVideoView(userID, TUIVideoStreamType.cameraStream, 0);
      _roomEngine?.setRemoteVideoView(userID, TUIVideoStreamType.cameraStreamLow, 0);
    }

    _hdStreamUsers.remove(userID);
    _playCameraStreams.remove(userID);
  }

  void startPlayScreenShareStream({required String userID, required int viewID}) {
    _log.info('API startPlayScreenShareStream userId:$userID, viewID:$viewID');
    if (userID.isEmpty) {
      _log.warn('Invalid userID provided');
      return;
    }

    final streamInfo = _VideoStreamInfo(userID: userID, streamType: TUIVideoStreamType.screenStream, viewID: viewID);
    if (_playScreenStream == streamInfo) {
      _log.info('same user operation, ignore');
      return;
    }

    _roomEngine?.setRemoteVideoView(userID, TUIVideoStreamType.screenStream, viewID);

    final playCallback = TUIPlayCallback(onPlaying: (userId) {
      _log.info('Response startPlayScreenShareStream onPlaying:userId:$userId');
    }, onLoading: (userId) {
      _log.info('Response startPlayScreenShareStream onLoading:userId:$userId');
    }, onPlayError: (userId, code, message) {
      _log.error('Response startPlayScreenShareStream onError:userId:$userId, code:$code, message:$message');
    });
    _roomEngine?.startPlayRemoteVideo(userID, TUIVideoStreamType.screenStream, playCallback);

    _playScreenStream = streamInfo;
  }

  void stopPlayScreenShareStream({required String userID, required int viewID, bool needClearView = false}) {
    _log.info('API stopPlayScreenShareStream userId:$userID');
    if (userID.isEmpty) {
      _log.warn('Invalid userID provided');
      return;
    }

    if (_playScreenStream?.viewID != viewID) return;
    _roomEngine?.stopPlayRemoteVideo(userID, TUIVideoStreamType.screenStream);
    if (needClearView) {
      _roomEngine?.setRemoteVideoView(userID, TUIVideoStreamType.screenStream, 0);
    }
    _playScreenStream = null;
  }

  bool needSwitchStreamType({required String userID, required double viewWidth}) {
    final streamInfo = _playCameraStreams[userID];
    if (streamInfo == null) return false;

    final decideStreamType = _decideVideoStreamType(viewWidth);
    return decideStreamType != streamInfo.streamType;
  }

  void setFillMode({required String userID, required VideoStreamType streamType, required FillMode fillMode}) {
    final loginUserID = LoginStore.shared.loginState.loginUserInfo?.userID ?? '';
    if (loginUserID.isEmpty) {
      _log.error('Invalid login userId');
      return;
    }

    final trtcFillMode = fillMode == FillMode.fill ? TRTCVideoFillMode.fill : TRTCVideoFillMode.fit;

    if (userID == loginUserID) {
      _trtcCloud?.setLocalRenderParams(TRTCRenderParams(fillMode: trtcFillMode));
      return;
    }

    switch (streamType) {
      case VideoStreamType.camera:
        _trtcCloud?.setRemoteRenderParams(userID, TRTCVideoStreamType.big, TRTCRenderParams(fillMode: trtcFillMode));
        _trtcCloud?.setRemoteRenderParams(userID, TRTCVideoStreamType.small, TRTCRenderParams(fillMode: trtcFillMode));
        break;
      case VideoStreamType.screen:
        _trtcCloud?.setRemoteRenderParams(userID, TRTCVideoStreamType.sub, TRTCRenderParams(fillMode: trtcFillMode));
        break;
    }
  }

  TUIVideoStreamType _decideVideoStreamType(double viewWidth) {
    final hdStreamCount = _hdStreamUsers.length;
    if (hdStreamCount >= _VideoStreamConstants.maxHdStreamCount &&
        viewWidth <= _VideoStreamConstants.hdThresholdWidthPx) {
      return TUIVideoStreamType.cameraStreamLow;
    }
    return TUIVideoStreamType.cameraStream;
  }
}

class _VideoStreamInfo {
  final String userID;
  final TUIVideoStreamType streamType;
  final int viewID;

  _VideoStreamInfo({
    required this.userID,
    required this.streamType,
    required this.viewID,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _VideoStreamInfo &&
        other.userID == userID &&
        other.streamType == streamType &&
        other.viewID == viewID;
  }

  @override
  int get hashCode => userID.hashCode ^ streamType.hashCode ^ viewID.hashCode;
}

class _ScreenShareScaleRecognizer extends ScaleGestureRecognizer {
  int _pointerCount = 0;

  @override
  void addPointer(PointerDownEvent event) {
    _pointerCount++;
    super.addPointer(event);

    if (_pointerCount >= 2) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointerCount = 0;
    super.didStopTrackingLastPointer(pointer);
  }
}
