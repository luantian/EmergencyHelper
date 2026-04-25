import 'dart:math';

import 'package:flutter/material.dart';

import 'package:atomic_x_core/api/live/live_seat_store.dart';
import 'package:atomic_x_core/impl/view/live/live_core_controller_impl.dart';
import 'package:atomic_x_core/impl/live/store_factory.dart';
import 'package:atomic_x_core/impl/view/live/item/video_widget.dart';
import 'package:atomic_x_core/impl/view/live/layer/seat_layout_mixin.dart';

class MixStreamLayer extends StatelessWidget with SeatLayoutMixin {
  final LiveCoreControllerImpl controller;
  final Size layoutSize;

  const MixStreamLayer({super.key, required this.controller, required this.layoutSize});

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
            InternalSeatLayout seatLayout = InternalSeatLayout(
                liveSeatStore.liveSeatState.seatList.value, liveSeatStore.liveSeatState.canvas.value);
            if (isFullScreenLayoutBySeatLayout(seatLayout)) {
              return VideoWidget(controller: controller, userId: mixUserId);
            } else {
              final size = calculateSizeBySeatLayout(seatLayout, layoutSize);
              return SizedBox(
                  width: size.width,
                  height: size.height,
                  child: ClipRect(
                    clipper: _RectangleClipper(seatLayout: seatLayout),
                    child: VideoWidget(controller: controller, userId: mixUserId),
                  ));
            }
          } else {
            return const SizedBox.shrink();
          }
        });
  }
}

class _RectangleClipper extends CustomClipper<Rect> {
  final InternalSeatLayout seatLayout;

  _RectangleClipper({required this.seatLayout});

  @override
  Rect getClip(Size size) {
    var centerTop = double.infinity;
    var centerBottom = 0.0;
    for (SeatInfo seat in seatLayout.seatList) {
      centerTop = min(seat.region.y.toDouble(), centerTop);
      centerBottom = max(seat.region.y.toDouble() + seat.region.h, centerBottom);
    }

    // Center rect of view
    final realRectTop = centerTop / seatLayout.canvas.h * size.height;
    final realRectBottom = centerBottom / seatLayout.canvas.h * size.height;
    return Rect.fromLTRB(0, realRectTop, size.width, realRectBottom);
  }

  @override
  bool shouldReclip(covariant _RectangleClipper oldClipper) {
    return oldClipper.seatLayout != seatLayout;
  }
}
