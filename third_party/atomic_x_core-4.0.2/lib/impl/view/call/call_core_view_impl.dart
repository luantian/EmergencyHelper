part of '../../../api/view/call/call_core_view.dart';


class CallCoreControllerImpl extends CallCoreController {
  CallCoreControllerImpl() {
    final activeCall = CallStore.shared.state.activeCall.value;

    if (activeCall.chatGroupId.isNotEmpty || activeCall.inviteeIds.length > 1) {
      _currentTemplate.value = CallLayoutTemplate.grid;
    } else {
      _currentTemplate.value = CallLayoutTemplate.float;
    }
  }

  @override
  void setLayoutTemplate(CallLayoutTemplate template) {
    Log.getCallLog("CallCoreView").info("setLayoutTemplate layout: $template");
    final activeCall = CallStore.shared.state.activeCall.value;
    if (template == CallLayoutTemplate.float && activeCall.inviteeIds.length > 1) {
      Log.getCallLog("CallCoreView").error("setLayoutTemplate fail. The Float layout type only supports a single invited participant.");
      return;
    }
    _currentTemplate.value = template;
  }

  @override
  void dispose() {
    _currentTemplate.dispose();
  }
}

class _CallCoreViewState extends State<CallCoreView> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller._currentTemplate,
      builder: (context, template, child) {
        switch (template) {
          case CallLayoutTemplate.float:
            return CallFloatView(
              defaultAvatar: widget.defaultAvatar,
            );
          case CallLayoutTemplate.grid:
            return CallGridView(
              loadingAnimation: widget.loadingAnimation,
              defaultAvatar: widget.defaultAvatar,
              volumeIcons: widget.volumeIcons,
              networkQualityIcons: widget.networkQualityIcons,
            );
          case CallLayoutTemplate.pip:
            return CallPipView(
              defaultAvatar: widget.defaultAvatar,
            );
          default:
            return CallGridView(
              loadingAnimation: widget.loadingAnimation,
              defaultAvatar: widget.defaultAvatar,
              volumeIcons: widget.volumeIcons,
              networkQualityIcons: widget.networkQualityIcons,
            );
        }
      },
    );
  }
}