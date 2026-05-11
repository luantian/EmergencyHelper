import 'dart:ui';

import 'package:atomic_x_core/impl/view/call/call_participant_view.dart';
import 'package:flutter/material.dart';

import '../../../../api/call/call_store.dart';
import '../../../../api/device/device_store.dart';

class CallPipView extends StatefulWidget {
  final Widget? defaultAvatar;

  const CallPipView({
    super.key,
    this.defaultAvatar,
  });

  @override
  State<StatefulWidget> createState() => _CallPipViewState();
}

class _CallPipViewState extends State<CallPipView> {
  static const int _minVolumeToDisplay = 10;
  static const Duration _animationDuration = Duration(milliseconds: 300);
  static const double _backgroundBlurSigmaX = 50.0;
  static const double _backgroundBlurSigmaY = 50.0;
  static const double _backgroundOpacity = 0.3;
  static const Color _backgroundColor = Color.fromRGBO(45, 45, 45, 0.8);
  static const double _avatarContainerSize = 120.0;
  static const double _avatarBorderRadius = 8.0;

  CallParticipantInfo? _lastDisplayedUser;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: CallStore.shared.state.allParticipants,
      builder: (context, allParticipants, child) {
        return ValueListenableBuilder(
          valueListenable: CallStore.shared.state.speakerVolumes,
          builder: (context, speakerVolumes, child) {
            var activeCall = CallStore.shared.state.activeCall.value;
            if (activeCall.chatGroupId.isEmpty && activeCall.inviteeIds.length == 1) {
              for (var info in allParticipants) {
                if (info.id != CallStore.shared.state.selfInfo.value.id) {
                  return _buildDisplayUserPipView(info);
                }
              }
            }

            _lastDisplayedUser ??= CallStore.shared.state.selfInfo.value;
            
            String? speakingUserId;
            speakerVolumes.forEach((userId, volume) {
              if (volume > _minVolumeToDisplay && speakingUserId == null) {
                speakingUserId = userId;
              }
            });

            if (speakingUserId != null) {
              for (var info in allParticipants) {
                if (info.id == speakingUserId) {
                  _lastDisplayedUser = info;
                  break;
                }
              }
            }

            return _buildDisplayUserPipView(_lastDisplayedUser
                ?? CallStore.shared.state.selfInfo.value);
          },
        );
      },
    );
  }

  _buildDisplayUserPipView(CallParticipantInfo info) {
    return AnimatedSwitcher(
      duration: _animationDuration,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: Stack(
        key: ValueKey(info.id),
        alignment: Alignment.center,
        children: [
          CallParticipantView(
            key: ValueKey(info.id),
            participantId: info.id,
          ),
          Visibility(
            visible: _isShowBackgroundImage(info),
            child: _buildBackground(info),
          ),
        ],
      ),
    );
  }

  _buildBackground(CallParticipantInfo info) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          constraints: const BoxConstraints.expand(),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _backgroundBlurSigmaX, sigmaY: _backgroundBlurSigmaY),
            child: Container(
              color: Colors.black.withOpacity(_backgroundOpacity),
              child: _getUserAvatar(info),
            ),
          ),
        ),
        Opacity(
          opacity: 1,
          child: Container(
            color: _backgroundColor,
          ),
        ),
        Container(
          height: _avatarContainerSize,
          width: _avatarContainerSize,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(_avatarBorderRadius)),
          ),
          child: _getUserAvatar(info),
        ),
      ],
    );
  }

  Widget _getUserAvatar(CallParticipantInfo info) {
    if (info.avatarURL.isNotEmpty) {
      return Image.network(
        info.avatarURL,
        fit: BoxFit.cover,
        errorBuilder:(context, error, stackTrace) {
          return widget.defaultAvatar ?? Container();
        },
      );
    }

    return widget.defaultAvatar ?? Container();
  }


  bool _isShowBackgroundImage(CallParticipantInfo info) {
    final isSelf = info.id == CallStore.shared.state.selfInfo.value.id;
    if (isSelf) {
      return DeviceStore.shared.state.cameraStatus.value == DeviceStatus.off;
    }
    return !info.isCameraOpened &&
        info.status != CallParticipantStatus.accept;
  }
}