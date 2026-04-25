import 'package:atomic_x_core/api/device/device_store.dart';
import 'package:atomic_x_core/impl/view/live/live_core_controller_impl.dart';
import 'package:flutter/material.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' hide DeviceStatus;

class VideoWidget extends StatefulWidget {
  final LiveCoreControllerImpl controller;
  final String userId;

  const VideoWidget({super.key, required this.controller, required this.userId});

  @override
  State<StatefulWidget> createState() {
    return VideoWidgetState();
  }
}

class VideoWidgetState extends State<VideoWidget> {
  int _nativeViewPtr = 0;

  late final _cameraStatusListener = _onCameraStatusChanged;

  @override
  void initState() {
    super.initState();
    if (_isSelfVideoWidget()) DeviceStore.shared.state.cameraStatus.addListener(_cameraStatusListener);
  }

  @override
  void dispose() {
    if (_isSelfVideoWidget()) DeviceStore.shared.state.cameraStatus.removeListener(_cameraStatusListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId.isEmpty) {
      return const SizedBox.shrink();
    }
    final widgetKey = widget.userId;
    return Container(
      color: Colors.transparent,
      child: VideoView(
        key: ValueKey(widgetKey),
        onViewCreated: (id) {
          _onViewCreated(id);
        },
        onViewDisposed: (id) {
          _onViewDisposed();
        },
      ),
    );
  }

  bool _isSelfVideoWidget() {
    return widget.userId == TUIRoomEngine.getSelfInfo().userId;
  }

  void _onViewCreated(int viewID) {
    _nativeViewPtr = viewID;
    if (_isSelfVideoWidget()) {
      if (DeviceStore.shared.state.cameraStatus.value == DeviceStatus.on) {
        widget.controller.setVideoView(widget.userId, _nativeViewPtr);
      }
    } else {
      widget.controller.setVideoView(widget.userId, _nativeViewPtr);
      widget.controller.startPlayVideo(widget.userId);
    }
  }

  void _onViewDisposed() {
    _nativeViewPtr = 0;
    if (!_isSelfVideoWidget()) {
      if (widget.controller.getInternalState().hasVideoStreamUserList.value.any((user) => user == widget.userId)) {
        return;
      }
      widget.controller.stopPlayVideo(widget.userId);
    }
  }

  void _onCameraStatusChanged() {
    if (DeviceStore.shared.state.cameraStatus.value == DeviceStatus.on && _nativeViewPtr != 0) {
      widget.controller.setVideoView(widget.userId, _nativeViewPtr);
    }
  }
}
