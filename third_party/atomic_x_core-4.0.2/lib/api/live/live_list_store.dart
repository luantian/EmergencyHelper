// Copyright (c) 2025 Tencent. All rights reserved.
// Module:   LiveListStore @ AtomicXCore
// Function: Live list related interfaces, managing live room creation, joining, leaving and other operations.

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/live/live_list_store_define.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:flutter/foundation.dart';

import '../../impl/live/store_factory.dart';

/// Take seat mode.
enum TakeSeatMode {
  /// Free to take seat.
  free(0),

  /// Apply to take seat.
  apply(1);

  final int value;

  const TakeSeatMode(this.value);
}

/// Seat layout template for simplifying seat configuration when creating a live room.
sealed class SeatLayoutTemplate {
  const SeatLayoutTemplate();
}

/// Portrait dynamic 9-grid layout for video live streaming.
class VideoDynamicGrid9Seats extends SeatLayoutTemplate {
  const VideoDynamicGrid9Seats();
}

/// Portrait dynamic 1v6 floating layout for video live streaming.
class VideoDynamicFloat7Seats extends SeatLayoutTemplate {
  const VideoDynamicFloat7Seats();
}

/// Portrait left focus 9-grid layout for video live streaming.
class VideoLeftFocus9Seats extends SeatLayoutTemplate {
  const VideoLeftFocus9Seats();
}

/// Portrait uniform 9-grid layout for video live streaming.
class VideoUniformGrid9Seats extends SeatLayoutTemplate {
  const VideoUniformGrid9Seats();
}

/// Portrait static 9-grid layout for video live streaming.
class VideoFixedGrid9Seats extends SeatLayoutTemplate {
  const VideoFixedGrid9Seats();
}

/// Portrait static 1v6 floating layout for video live streaming.
class VideoFixedFloat7Seats extends SeatLayoutTemplate {
  const VideoFixedFloat7Seats();
}

/// Landscape 4-seat layout for video live streaming.
class VideoLandscape4Seats extends SeatLayoutTemplate {
  const VideoLandscape4Seats();
}

/// Audio KTV layout for karaoke scenes with configurable seat count.
class Karaoke extends SeatLayoutTemplate {
  final int seatCount;
  const Karaoke(this.seatCount);
}

/// Audio salon layout for voice chat scenes with configurable seat count.
class AudioSalon extends SeatLayoutTemplate {
  final int seatCount;
  const AudioSalon(this.seatCount);
}

/// Live ended reason.
enum LiveEndedReason {
  /// Ended by host.
  endedByHost(1),

  /// Ended by server.
  endedByServer(2);

  final int value;

  const LiveEndedReason(this.value);
}

/// Kicked out of live room reason.
enum LiveKickedOutReason {
  /// Kicked out by admin.
  byAdmin(0),

  /// Logged on other device.
  byLoggedOnOtherDevice(1),

  /// Kicked out by server.
  byServer(2),

  /// Network disconnected.
  forNetworkDisconnected(3),

  /// Join room status invalid during offline.
  forJoinRoomStatusInvalidDuringOffline(4),

  /// Count of joined rooms exceed limit.
  forCountOfJoinedRoomsExceedLimit(5);

  final int value;

  const LiveKickedOutReason(this.value);
}

/// Live information
///
/// Contains complete property information of the live room, including live ID, name, cover, owner info, etc.
class LiveInfo {
  /// Live ID.
  String liveID;

  /// Live name.
  String liveName;

  /// Live notice.
  String notice;

  /// Whether message is disabled.
  bool isMessageDisable;

  /// Whether publicly visible.
  bool isPublicVisible;

  /// Whether seat is enabled.
  @Deprecated(
    'Deprecated since 3.7, use seatTemplate instead. This parameter will be automatically resolved internally.',
  )
  bool isSeatEnabled;

  /// Whether to keep owner on seat.
  bool keepOwnerOnSeat;

  /// Maximum seat count.
  @Deprecated(
    'Deprecated since 3.7, use seatTemplate instead. This parameter will be automatically resolved internally.',
  )
  int maxSeatCount;

  /// Take seat mode.
  TakeSeatMode seatMode;

  /// Seat layout template for simplifying seat configuration.
  SeatLayoutTemplate seatTemplate;

  /// Seat layout template ID.
  @Deprecated(
    'Deprecated since 3.7, use seatTemplate instead. This parameter will be automatically resolved internally.',
  )
  int seatLayoutTemplateID;

  /// Cover URL.
  String coverURL;

  /// Background URL.
  String backgroundURL;

  /// Category list.
  List<int> categoryList;

  /// Activity status.
  int activityStatus;

  /// Live owner info.
  LiveUserInfo liveOwner;

  /// Create time.
  int createTime;

  /// Total viewer count.
  int totalViewerCount;

  /// Whether gift is enabled.
  bool isGiftEnabled;

  /// Metadata.
  Map<String, String> metaData;

  LiveInfo({
    this.liveID = '',
    this.liveName = '',
    this.notice = '',
    this.isMessageDisable = false,
    this.isPublicVisible = true,
    bool? isSeatEnabled,
    bool? keepOwnerOnSeat,
    int? maxSeatCount,
    this.seatMode = TakeSeatMode.apply,
    this.seatTemplate = const VideoDynamicGrid9Seats(),
    int? seatLayoutTemplateID,
    this.coverURL = '',
    this.backgroundURL = '',
    List<int>? categoryList,
    this.activityStatus = 0,
    LiveUserInfo? liveOwner,
    this.createTime = 0,
    this.totalViewerCount = 0,
    this.isGiftEnabled = true,
    Map<String, String>? metaData,
  })  : isSeatEnabled = LiveInfoExtension.getSeatConfiguration(seatTemplate).isSeatEnabled,
        maxSeatCount = (maxSeatCount == null || maxSeatCount == 0)
            ? (LiveInfoExtension.getSeatConfiguration(seatTemplate).maxSeatCount ?? 0)
            : maxSeatCount,
        seatLayoutTemplateID = (seatLayoutTemplateID == null || seatLayoutTemplateID == 600)
            ? LiveInfoExtension.getSeatConfiguration(seatTemplate).seatLayoutTemplateID
            : seatLayoutTemplateID,
        keepOwnerOnSeat =
            keepOwnerOnSeat ?? LiveInfoExtension.getSeatConfiguration(seatTemplate).keepOwnerOnSeat ?? false,
        categoryList = categoryList ?? [],
        liveOwner = liveOwner ?? LiveUserInfo(),
        metaData = metaData ?? {};
}

enum ModifyFlag {
  none(0),
  liveName(1 << 0),
  notice(1 << 1),
  isMessageDisable(1 << 2),
  isPublicVisible(1 << 5),
  seatMode(1 << 6),
  coverUrl(1 << 7),
  backgroundUrl(1 << 8),
  categoryList(1 << 9),
  activityStatus(1 << 10),
  seatLayoutTemplateId(1 << 11);

  final int rawValue;

  const ModifyFlag(this.rawValue);
}

/// Live list state
///
/// Contains live list, cursor and current live info.
abstract class LiveListState {
  /// Live list.
  ValueListenable<List<LiveInfo>> get liveList;

  /// Live list cursor.
  ValueListenable<String> get liveListCursor;

  /// Current live info.
  ValueListenable<LiveInfo> get currentLive;
}

/// Live list events
///
///
class LiveListListener {
  /// Live ended event.
  /// - [liveID] : Live ID
  /// - [reason] : Ended reason
  /// - [message] : Message
  void Function(String liveID, LiveEndedReason reason, String message)? onLiveEnded;

  /// Kicked out of live room event.
  /// - [liveID] : Live ID
  /// - [reason] : Kicked out reason
  /// - [message] : Message
  void Function(String liveID, LiveKickedOutReason reason, String message)? onKickedOutOfLive;

  LiveListListener({this.onLiveEnded, this.onKickedOutOfLive});
}

/// Live info completion handler for Dart.
///
/// Completion handler for live info operations in Dart, containing the result live info.
class LiveInfoCompletionHandler extends CompletionHandler {
  /// Live info returned on success.
  LiveInfo liveInfo = LiveInfo();
}

/// Stop live completion handler for Dart.
///
/// Completion handler for stop live operations in Dart, containing the live statistics data.
class StopLiveCompletionHandler extends CompletionHandler {
  /// Live statistics data returned on success.
  TUILiveStatisticsData statisticsData = TUILiveStatisticsData();
}

/// Metadata completion handler for Dart.
///
/// Completion handler for metadata operations in Dart, containing the metadata result.
class MetaDataCompletionHandler extends CompletionHandler {
  /// Metadata returned on success.
  Map<String, String> metaData = {};
}

/// Live list related interfaces, managing live room creation, joining, leaving and other operations.
///
/// `LiveListStore` Live room list management class for managing live room related business.
/// `LiveListStore` provides a complete set of live room management APIs, including creating live, joining live, leaving live, ending live and other functions.
/// Through this class, you can manage the lifecycle of live rooms.
///
/// ### Key Features
///
/// - **Live List**：Get and manage live room list
/// - **Live Creation**：Create new live rooms
/// - **Live Joining**：Join existing live rooms
/// - **Live Management**：Update live info, end live and other operations
/// - **Event Listening**：Listen for live ended, kicked out and other events
///
/// > **Important**: Use the [LiveListStore.shared] singleton object to get the `LiveListStore` instance.
///
/// > **Note**: Live state updates are delivered through the [liveState] publisher. Subscribe to it to receive real-time updates of live data.
///
/// ### Live Management Operations Overview
///
/// | Operation | Method | Description |
/// |---------|------|-----------|
/// | Get List | [fetchLiveList] | Get live room list |
/// | Get Info | [fetchLiveInfo] | Get specified live room info |
/// | Create Live | [createLive] | Create new live room |
/// | Join Live | [joinLive] | Join existing live room |
/// | Leave Live | [leaveLive] | Leave current live room |
/// | End Live | [endLive] | End current live |
/// | Update Info | [updateLiveInfo] | Update live room info |
///
/// ## Topics
///
/// ### Getting Instance
/// - [LiveListStore.shared] : Singleton object
///
/// ### Observing State and Events
/// - [liveState] : Live list state
/// - [addLiveListListener]/[removeLiveListListener] : Live list event callbacks
///
/// ### Live List
/// - [fetchLiveList] : Get live list
/// - [fetchLiveInfo] : Get live info
///
/// ### Live Operations
/// - [createLive] : Create live
/// - [joinLive] : Join live
/// - [leaveLive] : Leave live
/// - [endLive] : End live
/// - [updateLiveInfo] : Update live info
///
/// ### Metadata Operations
/// - [queryMetaData] : Query metadata
/// - [updateLiveMetaData] : Update metadata
///
/// ## See Also
///
/// - [LiveInfo]
/// - [LiveListState]
/// - [LiveListListener]
/// - [TakeSeatMode]
/// - [LiveEndedReason]
/// - [LiveKickedOutReason]
abstract class LiveListStore {
  /// Singleton object
  static LiveListStore get shared => StoreFactory.shared.getStore<LiveListStore>();

  /// Live list state
  LiveListState get liveState;

  /// Get live list
  ///
  /// - [cursor] : Cursor.
  /// - [count] : Count.
  Future<CompletionHandler> fetchLiveList({
    required String cursor,
    required int count,
  });

  /// Get live info
  ///
  /// - [liveID] : Live room ID.
  /// - [completion] : Completion callback.
  Future<LiveInfoCompletionHandler> fetchLiveInfo(String liveID);

  /// Create live
  ///
  /// - [liveInfo] : Live info.
  Future<LiveInfoCompletionHandler> createLive(LiveInfo liveInfo);

  /// Join live
  ///
  /// - [liveID] : Live ID.
  Future<LiveInfoCompletionHandler> joinLive(String liveID);

  /// Leave live
  ///
  Future<CompletionHandler> leaveLive();

  /// End live
  ///
  Future<StopLiveCompletionHandler> endLive();

  /// Update live info
  ///
  /// - [liveInfo] : Live info.
  /// - [modifyFlag] : Modify flag.
  Future<CompletionHandler> updateLiveInfo({
    required LiveInfo liveInfo,
    required List<ModifyFlag> modifyFlagList,
  });

  /// Query metadata
  ///
  /// - [keys] : Key list.
  Future<MetaDataCompletionHandler> queryMetaData(List<String> keys);

  /// Update live metadata
  ///
  /// - [metaData] : Metadata.
  Future<CompletionHandler> updateLiveMetaData(Map<String, String> metaData);

  /// Reset to default state
  void reset();

  /// Add live list event listener
  ///
  /// - [listener] : Listener
  void addLiveListListener(LiveListListener listener);

  /// Remove live list event listener
  ///
  /// - [listener] : Listener
  void removeLiveListListener(LiveListListener listener);
}
