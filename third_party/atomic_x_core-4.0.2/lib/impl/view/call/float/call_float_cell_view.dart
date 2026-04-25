import 'package:atomic_x_core/impl/view/call/call_participant_view.dart';
import 'package:flutter/cupertino.dart';

import '../../../../api/call/call_store.dart';
import '../../../../api/device/device_store.dart';

class CallFloatCellView extends StatelessWidget {
  static const Color _backgroundOverlayColor = Color.fromRGBO(45, 45, 45, 0.9);
  static const Color _userNameTextColor = Color.fromRGBO(213, 224, 242, 1);
  
  static const double _largeAvatarSize = 100.0;
  static const double _smallAvatarSize = 50.0;
  static const double _avatarBorderRadius = 8.0;
  static const double _textSpacing = 10.0;
  static const double _userNameFontSize = 18.0;
  
  static const double _defaultTextScaleFactor = 1.0;
  static const double _fullOpacity = 1.0;
  static const double _audioViewTopPositionRatio = 0.25;

  final String userId;
  final bool isInMainView;
  final Widget? defaultAvatar;

  const CallFloatCellView({
    super.key,
    required this.userId,
    required this.isInMainView,
    this.defaultAvatar
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CallParticipantView(participantId: userId),
        ValueListenableBuilder(
          valueListenable: CallStore.shared.state.allParticipants,
          builder: (context, allParticipants, _) {
            CallParticipantInfo? info;
            for (var participant in allParticipants) {
              if (participant.id == userId) {
                info = participant;
              }
            }
            return _getBackgroundImage(context, info);
          },
        ),
      ],
    );
  }

  Widget _getBackgroundImage(BuildContext context, CallParticipantInfo? info) {
    return Visibility(
      visible: _isShowBackgroundImage(info),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: _getUserAvatar(info),
          ),
          Opacity(
            opacity: _fullOpacity,
            child: Container(
              color: _backgroundOverlayColor,
            ),
          ),
          Visibility(
            visible: info?.status == CallParticipantStatus.accept &&
                CallStore.shared.state.activeCall.value.mediaType == CallMediaType.video,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = isInMainView ? _largeAvatarSize : _smallAvatarSize;
                return Center(
                  child: Container(
                    height: size,
                    width: size,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(_avatarBorderRadius)),
                    ),
                    child: _getUserAvatar(info),
                  ),
                );
              },
            ),
          ),
          Visibility(
            visible: CallStore.shared.state.activeCall.value.mediaType == CallMediaType.audio,
            child: Positioned(
              top: MediaQuery.of(context).size.height * _audioViewTopPositionRatio,
              width: MediaQuery.of(context).size.width,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: _largeAvatarSize,
                    width: _largeAvatarSize,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(_avatarBorderRadius)),
                    ),
                    child: _getUserAvatar(info),
                  ),
                  const SizedBox(height: _textSpacing),
                  Text(
                    info != null
                        ? _getUserDisplayName(info)
                        : "",
                    textScaleFactor: _defaultTextScaleFactor,
                    style: const TextStyle(
                      fontSize: _userNameFontSize,
                      color: _userNameTextColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getUserAvatar(CallParticipantInfo? info) {
    if (info != null && info.avatarURL.isNotEmpty) {
      return Image.network(
        info.avatarURL,
        fit: BoxFit.cover,
        errorBuilder:(context, error, stackTrace) {
          return defaultAvatar ?? Container();
        },
      );
    }

    return defaultAvatar ?? Container();
  }

  bool _isShowBackgroundImage(CallParticipantInfo? info) {
    if (info == null) {
      return false;
    }

    return info.id == CallStore.shared.state.selfInfo.value.id
        ? DeviceStore.shared.state.cameraStatus.value == DeviceStatus.off
        : !info.isCameraOpened;
  }

  String _getUserDisplayName(CallParticipantInfo? info) {
    if (info == null) {
      return userId;
    }

    if (info.remark.isNotEmpty) {
      return info.remark;
    } else if (info.name.isNotEmpty) {
      return info.name;
    } else {
      return info.id;
    }
  }
}