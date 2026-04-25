part of 'package:atomic_x_core/api/view/live/live_core_widget.dart';

class _LiveCoreWidgetState extends State<LiveCoreWidget> {
  late final LiveCoreControllerImpl controller;
  final Log _logger = Log.getLiveLog("LiveCoreWidget");

  @override
  void initState() {
    super.initState();
    _logger.info("initState");
    controller = widget.controller as LiveCoreControllerImpl;
    controller.init();
    final currentLive = LiveListStore.shared.liveState.currentLive;
    if (currentLive.value.liveID.isEmpty) return;
    if (currentLive is TriggerableValueNotifier) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) (currentLive as TriggerableValueNotifier).notify();
      });
    }
  }

  @override
  void dispose() {
    _logger.info("dispose");
    controller.unInit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Stack(children: [
        LiveStreamWidgetContainer(controller: controller, videoWidgetBuilder: widget.videoWidgetBuilder),
      ]),
    );
  }
}
