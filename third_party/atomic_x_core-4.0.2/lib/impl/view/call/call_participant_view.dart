import 'package:atomic_x_core/api/call/call_store.dart';
import 'package:atomic_x_core/api/device/device_store.dart';
import 'package:atomic_x_core/api/login/login_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:rtc_room_engine/api/call/tui_call_engine.dart';
import 'package:rtc_room_engine/api/common/tui_common_define.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

class CallParticipantView extends StatefulWidget {
  final String participantId;
  final TUIVideoStreamType mediaType;

  const CallParticipantView({
    super.key,
    required this.participantId,
    this.mediaType = TUIVideoStreamType.cameraStream,
  });

  @override
  State<StatefulWidget> createState() => _CallParticipantViewState();
}

class _CallParticipantViewState extends State<CallParticipantView> {
  int? _myViewId;

  @override
  void initState() {
    super.initState();
    debugPrint('[TRTC-DEBUG][CallParticipantView] initState: participantId=${widget.participantId} mediaType=${widget.mediaType}');
    final selfInfoId = CallStore.shared.state.selfInfo.value.id;
    debugPrint('[TRTC-DEBUG][CallParticipantView] CallStore.selfInfo.id=$selfInfoId');
  }

  @override
  void didUpdateWidget(CallParticipantView oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return VideoView(
      onViewCreated: (viewId) {
        debugPrint('[TRTC-DEBUG][CallParticipantView] VideoView.onViewCreated: viewId=$viewId');
        String? loggedInUserId = LoginStore.shared.loginState.loginUserInfo?.userID;
        debugPrint('[TRTC-DEBUG][CallParticipantView] LoginStore.loginUserInfo?.userID=$loggedInUserId');
        if (loggedInUserId == null || loggedInUserId.isEmpty) {
          loggedInUserId = CallStore.shared.state.selfInfo.value.id;
          debugPrint('[TRTC-DEBUG][CallParticipantView] fallback to CallStore.selfInfo.id=$loggedInUserId');
        }
        final isLocal = widget.participantId == loggedInUserId;
        debugPrint('[TRTC-DEBUG][CallParticipantView] isLocal=$isLocal (participantId="${widget.participantId}" == loggedInUserId="$loggedInUserId")');
        if (isLocal) {
          _myViewId = viewId;
          debugPrint('[TRTC-DEBUG][CallParticipantView] storing local viewId=$viewId');
          // If another local view already registered, this is a duplicate (e.g. PiP).
          // Don't overwrite the active viewId, and don't open camera on a stale view.
          if (localCallViewId != null && localCallViewId != 0) {
            debugPrint('[TRTC-DEBUG][CallParticipantView] duplicate local view, active viewId=$localCallViewId, closing');
            _myViewId = null;
            return;
          }
          setLocalCallViewId(viewId);
          // Note: TUICamera.back opens front camera on this SDK version.
          debugPrint('[TRTC-DEBUG][CallParticipantView] calling TUICallEngine.openCamera(front, viewId=$viewId)');
          TUICallEngine.instance.openCamera(TUICamera.back, viewId);
          DeviceStore.shared.updateCameraStatus(true, isFront: true);
          debugPrint('[TRTC-DEBUG][CallParticipantView] openCamera returned');
        } else {
          debugPrint('[TRTC-DEBUG][CallParticipantView] calling TUICallEngine.startRemoteView(userId=${widget.participantId}, viewId=$viewId)');
          TUICallEngine.instance.startRemoteView(widget.participantId, viewId);
        }
      },
      onViewDisposed: (viewId) {
        // Only clear if this is the view that currently holds the active viewId.
        // Multiple CallParticipantView instances may exist temporarily during
        // AnimatedSwitcher transitions — clearing on any disposal would break
        // the surviving instance.
        if (widget.participantId == _getLocalUserId() && viewId == _myViewId) {
          debugPrint('[TRTC-DEBUG][CallParticipantView] local view disposed, clearing viewId');
          setLocalCallViewId(0);
          _myViewId = null;
        }
      },
    );
  }

  String? _getLocalUserId() {
    String? loggedInUserId = LoginStore.shared.loginState.loginUserInfo?.userID;
    if (loggedInUserId == null || loggedInUserId.isEmpty) {
      loggedInUserId = CallStore.shared.state.selfInfo.value.id;
    }
    return loggedInUserId.isEmpty ? null : loggedInUserId;
  }
}
