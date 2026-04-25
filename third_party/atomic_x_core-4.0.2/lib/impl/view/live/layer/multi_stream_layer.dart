import 'package:flutter/material.dart';

import 'package:atomic_x_core/api/live/live_seat_store.dart';
import 'package:atomic_x_core/impl/view/live/live_core_controller_impl.dart';
import 'package:atomic_x_core/impl/live/store_factory.dart';
import 'package:atomic_x_core/impl/view/live/item/video_widget.dart';
import 'package:atomic_x_core/impl/view/live/layer/seat_layout_mixin.dart';
import 'package:atomic_x_core/impl/view/live/layer/template_layout_delegate.dart';

class MultiStreamLayer extends StatelessWidget with SeatLayoutMixin {
  final LiveCoreControllerImpl controller;
  final Size layoutSize;

  const MultiStreamLayer({super.key, required this.controller, required this.layoutSize});

  @override
  Widget build(BuildContext context) {
    final liveID = controller.getLiveID();
    LiveSeatStore liveSeatStore = StoreFactory.shared.getStore(liveID: liveID);
    return ListenableBuilder(
      listenable: Listenable.merge(
          [controller.getInternalState().hasVideoStreamUserList, liveSeatStore.liveSeatState.seatList]),
      builder: (context, _) {
        final userIds = controller.getInternalState().hasVideoStreamUserList.value;
        var mixUserId = userIds.firstWhere((userId) => userId.contains("_feedback_"), orElse: () => "");
        if (mixUserId.isNotEmpty) {
          return const SizedBox.shrink();
        }
        InternalSeatLayout seatLayout =
            InternalSeatLayout(liveSeatStore.liveSeatState.seatList.value, liveSeatStore.liveSeatState.canvas.value);
        Size size = calculateSizeBySeatLayout(seatLayout, layoutSize);
        return CustomMultiChildLayout(
          delegate:
              TemplateLayoutDelegate(seatLayout: seatLayout, layoutSize: size, scaleXRatio: getScaleXRatio(context)),
          children: <Widget>[
            for (final seat in seatLayout.seatList)
              LayoutId(
                  id: "${seat.userInfo.liveID}_${seat.index}",
                  child: VideoWidget(controller: controller, userId: seat.userInfo.userID)),
          ],
        );
      },
    );
  }
}
