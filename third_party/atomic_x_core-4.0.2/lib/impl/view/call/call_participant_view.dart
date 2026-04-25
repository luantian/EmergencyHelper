import 'package:atomic_x_core/api/login/login_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:rtc_room_engine/api/call/tui_call_engine.dart';
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
  @override
  Widget build(BuildContext context) {
    return VideoView(
      onViewCreated: (viewId) {
        String? loggedInUserId = LoginStore.shared.loginState.loginUserInfo?.userID;
        if (widget.participantId == loggedInUserId) {
          setLocalView(viewId);
        } else {
          TUICallEngine.instance.startRemoteView(widget.participantId, viewId);
        }
      },
    );
  }

  setLocalView(int viewId) {
    TUICallEngine.instance.callExperimentalAPI({
      'api': 'setLocalView',
      'params': {
        'videoView': viewId,
      },
    });
  }
}
