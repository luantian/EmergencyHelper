import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

import '../common/log.dart';
import 'store_factory.dart';

class _LiveSummaryStateImpl implements LiveSummaryState {
  final ValueNotifier<LiveSummaryData> summaryDataValue = ValueNotifier(LiveSummaryData());

  @override
  ValueListenable<LiveSummaryData> get summaryData => summaryDataValue;
}

class LiveSummaryStoreImpl extends LiveSummaryStore implements IStore {
  final String _liveID;
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUILiveListManager _liveListManager;
  late final TUILiveListObserver _liveListObserver;
  final _liveSummaryState = _LiveSummaryStateImpl();

  Timer? _durationTimer;
  static const _durationInterval = Duration(seconds: 1);
  static const _maxInt = 0x7FFFFFFFFFFFFFFF;
  
  final Log _log = Log.getLiveLog('LiveSummaryStoreImpl');

  LiveSummaryStoreImpl(this._liveID) {
    _liveListManager = _roomEngine.getExtension(TUIExtensionType.liveListManager);
    _initObserver();
  }

  @override
  LiveSummaryState get liveSummaryState => _liveSummaryState;

  @override
  void beforeEnterRoom(String liveID) {
    _liveListManager.addObserver(_liveListObserver);
  }

  @override
  void afterEnterRoom(LiveInfo liveInfo) {
    _initStatisticsData();
  }

  @override
  void leaveRoom(String liveID) {
    _liveListManager.removeObserver(_liveListObserver);
    _stopDurationTimer();
  }

  void _initStatisticsData() async {
    final result = await _liveListManager.getLiveStatistics(_liveID);
    if (result.code == TUIError.success) {
      _liveSummaryState.summaryDataValue.value = LiveSummaryData(
        totalDuration: result.data?.liveDuration ?? 0,
        totalViewers: result.data?.totalViewers ?? 0,
        totalGiftsSent: result.data?.totalGiftsSent ?? 0,
        totalGiftUniqueSenders: result.data?.totalUniqueGiftSenders ?? 0,
        totalGiftCoins: result.data?.totalGiftCoins ?? 0,
        totalLikesReceived: result.data?.totalLikesReceived ?? 0,
        totalMessageSent: result.data?.totalMessageCount ?? 0,
      );
      _startDurationTimer();
    } else {
      _log.error('initStatisticsData onError code:${result.code.rawValue}, message:${result.message}');
    }
  }

  void _startDurationTimer() {
    _stopDurationTimer();
    _durationTimer = Timer.periodic(
      _durationInterval,
      (_) => _incrementDuration(),
    );
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _incrementDuration() {
    const increment = 1000;
    final currentData = _liveSummaryState.summaryDataValue.value;
    final current = currentData.totalDuration;

    final updatedData = LiveSummaryData(
      totalDuration: current <= (_maxInt - increment) ? current + increment : _maxInt,
      totalViewers: currentData.totalViewers,
      totalGiftsSent: currentData.totalGiftsSent,
      totalGiftUniqueSenders: currentData.totalGiftUniqueSenders,
      totalGiftCoins: currentData.totalGiftCoins,
      totalLikesReceived: currentData.totalLikesReceived,
      totalMessageSent: currentData.totalMessageSent,
    );

    _liveSummaryState.summaryDataValue.value = updatedData;
  }
}

extension LiveSummaryStoreImplObserver on LiveSummaryStoreImpl {
  void _initObserver() {
    _liveListObserver = TUILiveListObserver(
      onLiveStatisticsChanged: (roomId, statisticsData, modifyFlag) =>
          _onLiveStatisticsChanged(roomId, statisticsData, modifyFlag),
    );
  }

  void _onLiveStatisticsChanged(
    String roomId,
    TUILiveStatisticsData statisticsData,
    List<TUILiveStatisticsModifyFlag> modifyFlag,
  ) {
    if (roomId != _liveID) return;
    final currentData = _liveSummaryState.summaryDataValue.value;
    final newData = LiveSummaryData(
      totalDuration: currentData.totalDuration,
      totalViewers: modifyFlag.contains(TUILiveStatisticsModifyFlag.totalViewers)
          ? statisticsData.totalViewers
          : currentData.totalViewers,
      totalGiftsSent: modifyFlag.contains(TUILiveStatisticsModifyFlag.totalGiftsSent)
          ? statisticsData.totalGiftsSent
          : currentData.totalGiftsSent,
      totalGiftCoins: modifyFlag.contains(TUILiveStatisticsModifyFlag.totalGiftCoins)
          ? statisticsData.totalGiftCoins
          : currentData.totalGiftCoins,
      totalGiftUniqueSenders: modifyFlag.contains(TUILiveStatisticsModifyFlag.totalUniqueGiftSenders)
          ? statisticsData.totalUniqueGiftSenders
          : currentData.totalGiftUniqueSenders,
      totalLikesReceived: modifyFlag.contains(TUILiveStatisticsModifyFlag.totalLikesReceived)
          ? statisticsData.totalLikesReceived
          : currentData.totalLikesReceived,
      totalMessageSent: modifyFlag.contains(TUILiveStatisticsModifyFlag.totalMessageCount)
          ? statisticsData.totalMessageCount
          : currentData.totalMessageSent,
    );
    _liveSummaryState.summaryDataValue.value = newData;
  }
}
