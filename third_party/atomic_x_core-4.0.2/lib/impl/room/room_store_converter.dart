// ignore_for_file: unreachable_switch_default
import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' hide DeviceStatus;

extension TUIUserInfoExtension on TUIUserInfo {
  RoomParticipant toRoomParticipant({RoomParticipantStatus? roomStatus}) {
    return RoomParticipant(
      userID: userId,
      userName: userName,
      avatarURL: avatarUrl,
      nameCard: nameCard ?? '',
      role: userRole.toParticipantRole(),
      roomStatus: roomStatus ?? RoomParticipantStatus.scheduled,
      metaData: customInfo,
      microphoneStatus: hasAudioStream == true ? DeviceStatus.on : DeviceStatus.off,
      cameraStatus: hasVideoStream == true ? DeviceStatus.on : DeviceStatus.off,
      screenShareStatus: hasScreenStream == true ? DeviceStatus.on : DeviceStatus.off,
      isMessageDisabled: isMessageDisabled ?? false,
    );
  }

  RoomUser toRoomUser() {
    return RoomUser(
      userID: userId,
      userName: userName,
      avatarURL: avatarUrl,
    );
  }
}

extension RoomParticipantExtension on RoomParticipant {
  RoomUser toRoomUser() {
    return RoomUser(
      userID: userID,
      userName: userName,
      avatarURL: avatarURL,
    );
  }

  RoomParticipant copyWith({
    String? userID,
    String? userName,
    String? avatarURL,
    String? nameCard,
    ParticipantRole? role,
    RoomParticipantStatus? roomStatus,
    DeviceStatus? microphoneStatus,
    DeviceStatus? screenShareStatus,
    DeviceStatus? cameraStatus,
    bool? isMessageDisabled,
    Map<String, String>? metaData,
  }) {
    return RoomParticipant(
      userID: userID ?? this.userID,
      userName: userName ?? this.userName,
      avatarURL: avatarURL ?? this.avatarURL,
      nameCard: nameCard ?? this.nameCard,
      role: role ?? this.role,
      roomStatus: roomStatus ?? this.roomStatus,
      microphoneStatus: microphoneStatus ?? this.microphoneStatus,
      screenShareStatus: screenShareStatus ?? this.screenShareStatus,
      cameraStatus: cameraStatus ?? this.cameraStatus,
      isMessageDisabled: isMessageDisabled ?? this.isMessageDisabled,
      metaData: metaData ?? this.metaData,
    );
  }
}

extension TUIRoleExtension on TUIRole {
  ParticipantRole toParticipantRole() {
    switch (this) {
      case TUIRole.roomOwner:
        return ParticipantRole.owner;
      case TUIRole.administrator:
        return ParticipantRole.admin;
      case TUIRole.generalUser:
      default:
        return ParticipantRole.generalUser;
    }
  }
}

extension DeviceTypeExtension on DeviceType {
  TUIMediaDevice toEngineDevice() {
    switch (this) {
      case DeviceType.camera:
        return TUIMediaDevice.camera;
      case DeviceType.microphone:
        return TUIMediaDevice.microphone;
      case DeviceType.screenShare:
        return TUIMediaDevice.screen;
      default:
        return TUIMediaDevice.camera;
    }
  }
}

extension TUINetworkExtension on TUINetwork {
  NetworkInfo toNetworkInfo() {
    return NetworkInfo(
      userID: userId,
      delay: delay,
      downLoss: downLoss,
      upLoss: upLoss,
      quality: quality.toNetworkQuality(),
    );
  }
}

extension TUINetworkQualityExtension on TUINetworkQuality {
  NetworkQuality toNetworkQuality() {
    switch (this) {
      case TUINetworkQuality.qualityUnknown:
        return NetworkQuality.unknown;
      case TUINetworkQuality.qualityExcellent:
        return NetworkQuality.excellent;
      case TUINetworkQuality.qualityGood:
        return NetworkQuality.good;
      case TUINetworkQuality.qualityPoor:
        return NetworkQuality.poor;
      case TUINetworkQuality.qualityBad:
        return NetworkQuality.bad;
      case TUINetworkQuality.qualityVeryBad:
        return NetworkQuality.veryBad;
      case TUINetworkQuality.qualityDown:
        return NetworkQuality.down;
      default:
        return NetworkQuality.unknown;
    }
  }
}

extension TUIKickedOutOfRoomReasonExtension on TUIKickedOutOfRoomReason {
  KickedOutOfRoomReason toKickedOutReason() {
    switch (this) {
      case TUIKickedOutOfRoomReason.byAdmin:
        return KickedOutOfRoomReason.kickedByAdmin;
      case TUIKickedOutOfRoomReason.byLoggedOnOtherDevice:
        return KickedOutOfRoomReason.replacedByAnotherDevice;
      case TUIKickedOutOfRoomReason.byServer:
        return KickedOutOfRoomReason.kickedByServer;
      case TUIKickedOutOfRoomReason.forNetworkDisconnected:
        return KickedOutOfRoomReason.connectionTimeout;
      case TUIKickedOutOfRoomReason.forJoinRoomStatusInvalidDuringOffline:
        return KickedOutOfRoomReason.invalidStatusOnReconnect;
      case TUIKickedOutOfRoomReason.forCountOfJoinedRoomExceededLimit:
        return KickedOutOfRoomReason.roomLimitExceeded;
      default:
        return KickedOutOfRoomReason.kickedByServer;
    }
  }
}

extension TUIConferenceStatusExtension on TUIConferenceStatus {
  RoomStatus toRoomStatus() {
    switch (this) {
      case TUIConferenceStatus.none:
      case TUIConferenceStatus.notStarted:
        return RoomStatus.scheduled;
      case TUIConferenceStatus.running:
        return RoomStatus.running;
      default:
        return RoomStatus.scheduled;
    }
  }
}

extension TUIRoomInfoExtension on TUIRoomInfo {
  RoomInfo toRoomInfo({RoomStatus roomStatus = RoomStatus.running}) {
    return RoomInfo(
      roomID: roomId,
      roomName: name ?? "",
      password: password,
      isAllMicrophoneDisabled: isMicrophoneDisableForAllUser,
      isAllCameraDisabled: isCameraDisableForAllUser,
      isAllMessageDisabled: isMessageDisableForAllUser,
      isAllScreenShareDisabled: isScreenShareDisableForAllUser,
      roomOwner: RoomUser(
        userID: ownerId,
        userName: ownerName ?? "",
        avatarURL: ownerAvatarUrl ?? "",
      ),
      participantCount: memberCount,
      createTime: createTime,
      roomStatus: roomStatus,
    );
  }
}

extension TUIConferenceInfoExtension on TUIConferenceInfo {
  RoomInfo toRoomInfo() {
    final engineRoomInfo = basicRoomInfo;
    return RoomInfo(
      roomID: engineRoomInfo.roomId,
      roomName: engineRoomInfo.name ?? "",
      password: engineRoomInfo.password,
      isAllMicrophoneDisabled: engineRoomInfo.isMicrophoneDisableForAllUser,
      isAllCameraDisabled: engineRoomInfo.isCameraDisableForAllUser,
      isAllMessageDisabled: engineRoomInfo.isMessageDisableForAllUser,
      isAllScreenShareDisabled: engineRoomInfo.isScreenShareDisableForAllUser,
      roomOwner: RoomUser(
        userID: engineRoomInfo.ownerId,
        userName: engineRoomInfo.ownerName ?? "",
        avatarURL: engineRoomInfo.ownerAvatarUrl ?? "",
      ),
      participantCount: engineRoomInfo.memberCount,
      createTime: engineRoomInfo.createTime,
      scheduledStartTime: scheduleStartTime ?? 0,
      scheduledEndTime: scheduleEndTime ?? 0,
      startReminderInSeconds: reminderSecondsBeforeStart ?? 0,
      roomStatus: status.toRoomStatus(),
    );
  }
}

extension RoomOptionsExtension on CreateRoomOptions {
  TUIRoomInfo toEngineRoomInfo(String roomID) {
    final roomInfo = TUIRoomInfo(roomId: roomID);
    roomInfo.roomType = TUIRoomType.conference;
    roomInfo.name = roomName;
    roomInfo.password = password;
    roomInfo.isCameraDisableForAllUser = isAllCameraDisabled;
    roomInfo.isMicrophoneDisableForAllUser = isAllMicrophoneDisabled;
    roomInfo.isMessageDisableForAllUser = isAllMessageDisabled;
    roomInfo.isScreenShareDisableForAllUser = isAllScreenShareDisabled;
    return roomInfo;
  }
}

extension ScheduleRoomOptionsExtension on ScheduleRoomOptions {
  TUIConferenceInfo toEngineConferenceInfo(String roomID) {
    final basicRoomInfo = TUIRoomInfo(roomId: roomID);
    basicRoomInfo.roomType = TUIRoomType.conference;
    basicRoomInfo.name = roomName;
    basicRoomInfo.password = password;
    basicRoomInfo.isCameraDisableForAllUser = isAllCameraDisabled;
    basicRoomInfo.isMicrophoneDisableForAllUser = isAllMicrophoneDisabled;
    basicRoomInfo.isMessageDisableForAllUser = isAllMessageDisabled;
    basicRoomInfo.isScreenShareDisableForAllUser = isAllScreenShareDisabled;
    final conferenceInfo = TUIConferenceInfo(basicRoomInfo: basicRoomInfo);
    conferenceInfo.scheduleStartTime = scheduleStartTime;
    conferenceInfo.scheduleEndTime = scheduleEndTime;
    conferenceInfo.scheduleAttendees = scheduleAttendees;
    conferenceInfo.reminderSecondsBeforeStart = reminderSecondsBeforeStart;
    return conferenceInfo;
  }
}

extension RoomInfoExtension on RoomInfo {
  RoomInfo copyWith({
    String? roomID,
    String? roomName,
    RoomUser? roomOwner,
    RoomType? roomType,
    int? participantCount,
    int? audienceCount,
    int? createTime,
    RoomStatus? roomStatus,
    int? scheduledStartTime,
    int? scheduledEndTime,
    int? startReminderInSeconds,
    List<RoomUser>? scheduleAttendees,
    String? password,
    bool? isAllMicrophoneDisabled,
    bool? isAllCameraDisabled,
    bool? isAllMessageDisabled,
    bool? isAllScreenShareDisabled,
  }) {
    return RoomInfo(
      roomID: roomID ?? this.roomID,
      roomName: roomName ?? this.roomName,
      roomOwner: roomOwner ?? this.roomOwner,
      roomType: roomType ?? this.roomType,
      participantCount: participantCount ?? this.participantCount,
      audienceCount: audienceCount ?? this.audienceCount,
      createTime: createTime ?? this.createTime,
      roomStatus: roomStatus ?? this.roomStatus,
      scheduledStartTime: scheduledStartTime ?? this.scheduledStartTime,
      scheduledEndTime: scheduledEndTime ?? this.scheduledEndTime,
      startReminderInSeconds: startReminderInSeconds ?? this.startReminderInSeconds,
      scheduleAttendees: scheduleAttendees ?? this.scheduleAttendees,
      password: password ?? this.password,
      isAllMicrophoneDisabled: isAllMicrophoneDisabled ?? this.isAllMicrophoneDisabled,
      isAllCameraDisabled: isAllCameraDisabled ?? this.isAllCameraDisabled,
      isAllMessageDisabled: isAllMessageDisabled ?? this.isAllMessageDisabled,
      isAllScreenShareDisabled: isAllScreenShareDisabled ?? this.isAllScreenShareDisabled,
    );
  }

  RoomInfo updateFromModifyFlags(
    RoomInfo source,
    List<TUIConferenceModifyFlag> flags,
  ) {
    return copyWith(
      roomName: flags.contains(TUIConferenceModifyFlag.roomName) ? source.roomName : null,
      scheduledStartTime: flags.contains(TUIConferenceModifyFlag.scheduleStartTime) ? source.scheduledStartTime : null,
      scheduledEndTime: flags.contains(TUIConferenceModifyFlag.scheduleEndTime) ? source.scheduledEndTime : null,
    );
  }
}

extension TUIInvitationCodeExtension on TUIInvitationCode {
  RoomCallResult toRoomCallResult() {
    switch (this) {
      case TUIInvitationCode.success:
        return RoomCallResult.success;
      case TUIInvitationCode.alreadyInInvitationList:
        return RoomCallResult.alreadyInCalling;
      case TUIInvitationCode.alreadyInConference:
        return RoomCallResult.alreadyInRoom;
    }
  }
}

extension TUIInvitationStatusExtension on TUIInvitationStatus {
  RoomCallStatus toRoomCallStatus() {
    switch (this) {
      case TUIInvitationStatus.pending:
        return RoomCallStatus.calling;
      case TUIInvitationStatus.timeout:
        return RoomCallStatus.timeout;
      case TUIInvitationStatus.rejected:
        return RoomCallStatus.rejected;
      default:
        return RoomCallStatus.none;
    }
  }

  RoomParticipantStatus toRoomParticipantStatus() {
    switch (this) {
      case TUIInvitationStatus.pending:
        return RoomParticipantStatus.inCalling;
      case TUIInvitationStatus.timeout:
        return RoomParticipantStatus.callTimeout;
      case TUIInvitationStatus.rejected:
        return RoomParticipantStatus.callRejected;
      default:
        return RoomParticipantStatus.inRoom;
    }
  }
}

extension TUIInvitationExtension on TUIInvitation {
  RoomCall toRoomCall() {
    return RoomCall(
      caller: inviter?.toRoomUser(),
      callee: invitee?.toRoomUser(),
      status: status.toRoomCallStatus(),
    );
  }
}

extension CallRejectionReasonExtension on CallRejectionReason {
  TUIInvitationRejectedReason toEngineRejectedReason() {
    switch (this) {
      case CallRejectionReason.rejected:
        return TUIInvitationRejectedReason.rejectToEnter;
      case CallRejectionReason.inOtherRoom:
        return TUIInvitationRejectedReason.inOtherConference;
      default:
        return TUIInvitationRejectedReason.rejectToEnter;
    }
  }
}

extension TUIInvitationRejectedReasonExtension on TUIInvitationRejectedReason {
  CallRejectionReason toCallRejectionReason() {
    switch (this) {
      case TUIInvitationRejectedReason.rejectToEnter:
        return CallRejectionReason.rejected;
      case TUIInvitationRejectedReason.inOtherConference:
        return CallRejectionReason.inOtherRoom;
      default:
        return CallRejectionReason.rejected;
    }
  }
}

extension RoomUserFromJson on RoomUser {
  static RoomUser fromJson(Map<String, dynamic> json) {
    return RoomUser(
      userID: json['userID'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      avatarURL: json['avatarURL'] as String? ?? '',
    );
  }
}

extension RoomInfoFromJson on RoomInfo {
  static RoomInfo fromJson(Map<String, dynamic> json) {
    final roomOwnerJson = json['roomOwner'] as Map<String, dynamic>?;
    final attendeesJson = json['scheduleAttendees'] as List<dynamic>?;

    return RoomInfo(
      roomID: json['roomID'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      roomOwner: roomOwnerJson != null ? RoomUserFromJson.fromJson(roomOwnerJson) : null,
      roomType: _parseRoomType(json['roomType'] as int?),
      participantCount: json['participantCount'] as int? ?? 0,
      audienceCount: json['audienceCount'] as int? ?? 0,
      createTime: json['createTime'] as int? ?? 0,
      roomStatus: _parseRoomStatus(json['roomStatus'] as int?),
      scheduledStartTime: json['scheduledStartTime'] as int? ?? 0,
      scheduledEndTime: json['scheduledEndTime'] as int? ?? 0,
      startReminderInSeconds: json['startReminderInSeconds'] as int? ?? 0,
      scheduleAttendees: attendeesJson?.map((e) => RoomUserFromJson.fromJson(e as Map<String, dynamic>)).toList(),
      password: json['password'] as String?,
      isAllMicrophoneDisabled: json['isAllMicrophoneDisabled'] as bool? ?? false,
      isAllCameraDisabled: json['isAllCameraDisabled'] as bool? ?? false,
      isAllMessageDisabled: json['isAllMessageDisabled'] as bool? ?? false,
      isAllScreenShareDisabled: json['isAllScreenShareDisabled'] as bool? ?? false,
    );
  }

  static RoomInfo? fromJsonString(String? data) {
    if (data == null || data.isEmpty) return null;
    final json = jsonDecode(data);
    if (json is! Map<String, dynamic>) return null;
    final roomInfoJson = json['roomInfo'];
    if (roomInfoJson is! Map<String, dynamic>) return null;
    return fromJson(roomInfoJson);
  }

  static RoomType _parseRoomType(int? value) {
    if (value == null) return RoomType.standard;
    return RoomType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RoomType.standard,
    );
  }

  static RoomStatus _parseRoomStatus(int? value) {
    if (value == null) return RoomStatus.scheduled;
    return RoomStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RoomStatus.scheduled,
    );
  }
}

extension RoomParticipantFromJson on RoomParticipant {
  static RoomParticipant fromJson(Map<String, dynamic> json) {
    return RoomParticipant(
      userID: json['userID'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      avatarURL: json['avatarURL'] as String? ?? '',
      nameCard: json['nameCard'] as String? ?? '',
      role: _parseParticipantRole(json['role'] as int?),
      roomStatus: _parseRoomParticipantStatus(json['roomStatus'] as int?),
      microphoneStatus: _parseDeviceStatus(json['microphoneStatus'] as int?),
      cameraStatus: _parseDeviceStatus(json['cameraStatus'] as int?),
      screenShareStatus: _parseDeviceStatus(json['screenShareStatus'] as int?),
      isMessageDisabled: json['isMessageDisabled'] as bool? ?? false,
      metaData: (json['metaData'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  static ParticipantRole _parseParticipantRole(int? value) {
    if (value == null) return ParticipantRole.generalUser;
    return ParticipantRole.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ParticipantRole.generalUser,
    );
  }

  static RoomParticipantStatus _parseRoomParticipantStatus(int? value) {
    if (value == null) return RoomParticipantStatus.scheduled;
    return RoomParticipantStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RoomParticipantStatus.scheduled,
    );
  }

  static DeviceStatus _parseDeviceStatus(int? value) {
    if (value == null) return DeviceStatus.off;
    return DeviceStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DeviceStatus.off,
    );
  }
}
