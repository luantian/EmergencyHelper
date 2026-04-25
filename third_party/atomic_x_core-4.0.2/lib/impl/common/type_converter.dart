import 'package:atomic_x_core/api/live/live_audience_store.dart';
import 'package:atomic_x_core/api/live/live_seat_store.dart' as live_seat_store;
import 'package:atomic_x_core/api/device/device_store.dart' as device_store;
import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:rtc_room_engine/api/room/tui_room_define.dart' as tui_room_define;

import 'package:atomic_x_core/api/live/live_seat_store.dart';

class TypeConverter {
  static SeatUserInfo seatUserInfoFromEngineSeatInfo(SeatFullInfo seatInfo, bool isOwner) {
    return SeatUserInfo(
      userID: seatInfo.userId,
      userName: seatInfo.userName,
      avatarURL: seatInfo.userAvatar,
      liveID: seatInfo.roomId,
      role: isOwner ? Role.owner : Role.generalUser,
      allowOpenMicrophone: seatInfo.userMicrophoneStatus != tui_room_define.DeviceStatus.closeByAdmin,
      allowOpenCamera: seatInfo.userCameraStatus != tui_room_define.DeviceStatus.closeByAdmin,
      microphoneStatus: seatInfo.userMicrophoneStatus == tui_room_define.DeviceStatus.opened
          ? device_store.DeviceStatus.on
          : device_store.DeviceStatus.off,
      cameraStatus: seatInfo.userCameraStatus == tui_room_define.DeviceStatus.opened
          ? device_store.DeviceStatus.on
          : device_store.DeviceStatus.off,
      userSuspendStatus: live_seat_store.SuspendStatus.fromValue(seatInfo.userSuspendStatus.value),
    );
  }

  static LiveUserInfo liveUserInfoFromEngineUserInfo(TUIUserInfo? userInfo) {
    return LiveUserInfo(
      userID: userInfo?.userId ?? "",
      userName: userInfo?.userName ?? "",
      avatarURL: userInfo?.avatarUrl ?? "",
    );
  }
}
