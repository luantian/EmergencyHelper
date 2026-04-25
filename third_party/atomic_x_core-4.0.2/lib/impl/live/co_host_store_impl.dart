import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

import '../common/future_converter.dart';
import '../common/listener_dispatcher.dart';
import '../common/log.dart';
import 'store_factory.dart';

class _CoHostStateImpl implements CoHostState {
  final ValueNotifier<CoHostStatus> coHostStatusValue = ValueNotifier(CoHostStatus.disconnected);
  final ValueNotifier<List<SeatUserInfo>> connectedValue = ValueNotifier([]);
  final ValueNotifier<List<SeatUserInfo>> inviteesValue = ValueNotifier([]);
  final ValueNotifier<SeatUserInfo?> applicantValue = ValueNotifier(null);
  final ValueNotifier<List<SeatUserInfo>> candidatesValue = ValueNotifier([]);
  final ValueNotifier<String> candidatesCursorValue = ValueNotifier('');

  @override
  ValueListenable<CoHostStatus> get coHostStatus => coHostStatusValue;

  @override
  ValueListenable<List<SeatUserInfo>> get connected => connectedValue;

  @override
  ValueListenable<List<SeatUserInfo>> get invitees => inviteesValue;

  @override
  ValueListenable<SeatUserInfo?> get applicant => applicantValue;

  @override
  ValueListenable<String> get candidatesCursor => candidatesCursorValue;

  @override
  ValueListenable<List<SeatUserInfo>> get candidates => candidatesValue;
}

class CoHostStoreImpl extends CoHostStore implements IStore {
  final String _liveID;
  late final TUILoginUserInfo _selfUserInfo;
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUILiveConnectionManager _connectionManager;
  late final TUILiveConnectionObserver _connectionObserver;
  late final TUILiveListManager _liveListManager;
  final _pageSizeOfGetCandidates = 20;

  final _coHostState = _CoHostStateImpl();
  final _listenerDispatcher = ListenerDispatcher<CoHostListener>();

  final Log _log = Log.getLiveLog('CoHostStoreImpl');

  CoHostStoreImpl(this._liveID) {
    _selfUserInfo = TUIRoomEngine.getSelfInfo();
    _connectionManager = _roomEngine.getLiveConnectionManager();
    _liveListManager = _roomEngine.getExtension(TUIExtensionType.liveListManager);
    _initObserver();
  }

  @override
  CoHostState get coHostState => _coHostState;

  @override
  void beforeEnterRoom(String liveID) {
    _connectionManager.addObserver(_connectionObserver);
  }

  @override
  void afterEnterRoom(LiveInfo liveInfo) {}

  @override
  void leaveRoom(String liveID) {
    _listenerDispatcher.cleanup();
    _connectionManager.removeObserver(_connectionObserver);
  }

  @override
  void addCoHostListener(CoHostListener listener) {
    _log.info('API addCoHostListener listener:${listener.hashCode}');
    _listenerDispatcher.addListener(listener);
  }

  @override
  void removeCoHostListener(CoHostListener listener) {
    _log.info('API removeCoHostListener listener:${listener.hashCode}');
    _listenerDispatcher.removeListener(listener);
  }

  @override
  Future<CompletionHandler> requestHostConnection({
    required String targetHostLiveID,
    required CoHostLayoutTemplate layoutTemplate,
    required int timeout,
    String extraInfo = '',
  }) async {
    _log.info('API requestHostConnection targetHostLiveID:$targetHostLiveID, timeout:$timeout');
    final seatUserInfo = SeatUserInfo(liveID: targetHostLiveID);
    _coHostState.inviteesValue.value = [..._coHostState.inviteesValue.value, seatUserInfo];
    _setCoHostLayoutTemplate(layoutTemplate);
    final result = await _connectionManager.requestConnection([targetHostLiveID], timeout, extraInfo);
    if (result.code == TUIError.success) {
      final resMap = result.data?.requestMap;
      final value = resMap?[targetHostLiveID];
      if (resMap == null || value == null) {
        _log.error(
            'Response requestHostConnection onError code:${TUIConnectionCode.retry.value()}, reason: not contain liveID, map:$resMap');
        _coHostState.inviteesValue.value =
            _coHostState.inviteesValue.value.where((user) => user.liveID != targetHostLiveID).toList();
        final completionHandler = CompletionHandler();
        completionHandler.errorCode = -1;
        completionHandler.errorMessage = 'requestHostConnection failed';
        return completionHandler;
      }
      if (value == TUIConnectionCode.success.value()) {
        _log.info('Response requestHostConnection onSuccess');
        return handleCallback(result);
      } else {
        _log.error('Response requestHostConnection onError code:$value, reason:result code not success, map:$resMap');
        _coHostState.inviteesValue.value =
            _coHostState.inviteesValue.value.where((user) => user.liveID != targetHostLiveID).toList();
        final completionHandler = CompletionHandler();
        completionHandler.errorCode = value;
        completionHandler.errorMessage = 'requestHostConnection failed';
        return completionHandler;
      }
    } else {
      _log.error('Response requestHostConnection onError code:${result.code.rawValue}, message:${result.message}');
      _coHostState.inviteesValue.value =
          _coHostState.inviteesValue.value.where((user) => user.liveID != targetHostLiveID).toList();
      return handleCallback(result);
    }
  }

  @override
  Future<CompletionHandler> cancelHostConnection(String toHostLiveID) async {
    _log.info('API cancelHostConnection toHostLiveID:$toHostLiveID');
    _coHostState.inviteesValue.value =
        _coHostState.inviteesValue.value.where((user) => user.liveID != toHostLiveID).toList();
    final result = await _connectionManager.cancelConnectionRequest([toHostLiveID]);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response cancelHostConnection onSuccess')
        : _log
            .error('Response cancelHostConnection onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> acceptHostConnection(String fromHostLiveID) async {
    _log.info('API acceptHostConnection fromHostLiveID:$fromHostLiveID');
    _coHostState.applicantValue.value = null;
    final result = await _connectionManager.acceptConnection(fromHostLiveID);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response acceptHostConnection onSuccess')
        : _log
            .error('Response acceptHostConnection onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> rejectHostConnection(String fromHostLiveID) async {
    _log.info('API rejectHostConnection fromHostLiveID:$fromHostLiveID');
    _coHostState.applicantValue.value = null;
    final result = await _connectionManager.rejectConnection(fromHostLiveID);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response rejectHostConnection onSuccess')
        : _log
            .error('Response rejectHostConnection onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> exitHostConnection() async {
    _log.info('API exitHostConnection');
    _coHostState.connectedValue.value = [];
    final result = await _connectionManager.disconnect();
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response exitHostConnection onSuccess')
        : _log.error('Response exitHostConnection onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> getCoHostCandidates(String cursor) async {
    _log.info("API getCoHostCandidates cursor=$cursor, _pageSizeOfGetCandidates=$_pageSizeOfGetCandidates");
    final result = await _liveListManager.fetchLiveList(cursor, _pageSizeOfGetCandidates);
    final handler = handleCallback(result);
    if (handler.isSuccess && result.data != null) {
      final liveInfoList = result.data!.liveInfoList;
      final newList = liveInfoList.map((item) => _convertToSeatUserInfo(item)).toList();
      final existingLiveList = [..._coHostState.connectedValue.value];
      if (cursor.isNotEmpty) existingLiveList.addAll(_coHostState.candidatesValue.value);
      final existingLiveIds = existingLiveList.map((item) => item.liveID).toSet();
      newList.removeWhere((seatUserInfo) => existingLiveIds.contains(seatUserInfo.liveID));
      if (cursor.isEmpty) {
        _coHostState.candidatesValue.value = newList;
      } else {
        _coHostState.candidatesValue.value = [..._coHostState.candidatesValue.value, ...newList];
      }
      _coHostState.candidatesCursorValue.value = result.data!.cursor;
    }
    handler.isSuccess
        ? _log.info('Response getCoHostCandidates onSuccess')
        : _log.error('Response getCoHostCandidates onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  @override
  Future<CompletionHandler> muteRemoteHostAudio({
    required String liveID,
    required bool isMuted,
  }) async {
    _log.info('API muteRemoteHostAudio liveID:$liveID, isMuted:$isMuted');
    final result = await _connectionManager.muteConnection(liveID, isMuted);
    final handler = handleCallback(result);
    handler.isSuccess
        ? _log.info('Response muteRemoteHostAudio onSuccess')
        : _log.error('Response muteRemoteHostAudio onError code:${handler.errorCode}, message:${handler.errorMessage}');
    return handler;
  }

  _setCoHostLayoutTemplate(CoHostLayoutTemplate layoutTemplate) async {
    try {
      final params = <String, dynamic>{
        'templateId': layoutTemplate.value,
      };

      final requestObj = <String, dynamic>{
        'api': 'setCoHostLayoutTemplateId',
        'params': params,
      };

      final jsonString = jsonEncode(requestObj);
      await _roomEngine.invokeExperimentalAPI(jsonString);
    } catch (e) {
      _log.error('setCoHostLayoutTemplateId failed. error:$e');
    }
  }
}

extension CoHostStoreImplObserver on CoHostStoreImpl {
  void _initObserver() {
    _connectionObserver = TUILiveConnectionObserver(
      onConnectionUserListChanged: (connectedList, joinedList, leavedList) =>
          _onConnectionUserListChanged(connectedList, joinedList, leavedList),
      onConnectionRequestReceived: (inviter, inviteeList, extensionInfo) =>
          _onConnectionRequestReceived(inviter, extensionInfo),
      onConnectionRequestCancelled: (inviter) => _onConnectionRequestCancelled(inviter),
      onConnectionRequestAccept: (invitee) => _onConnectionRequestAccept(invitee),
      onConnectionRequestReject: (invitee) => _onConnectionRequestReject(invitee),
      onConnectionRequestTimeout: (inviter, invitee) => _onConnectionRequestTimeout(inviter, invitee),
    );
  }

  void _onConnectionUserListChanged(
      List<TUIConnectionUser> connectedList, List<TUIConnectionUser> joinedList, List<TUIConnectionUser> leavedList) {
    _log.info(
        'Observer onConnectionUserListChanged connectedList:$connectedList, joinedList:$joinedList, leavedList:$leavedList');
    _coHostState.coHostStatusValue.value = connectedList.any((item) => item.userId == _selfUserInfo.userId)
        ? CoHostStatus.connected
        : CoHostStatus.disconnected;
    _coHostState.connectedValue.value = connectedList.map((item) => _seatUserInfoFromConnectionUser(item)).toList();

    for (var user in joinedList) {
      final seatUserInfo = _seatUserInfoFromConnectionUser(user);
      _listenerDispatcher.notify((listener) {
        listener.onCoHostUserJoined?.call(seatUserInfo);
      });
    }
    for (var user in leavedList) {
      final seatUserInfo = _seatUserInfoFromConnectionUser(user);
      _listenerDispatcher.notify((listener) {
        listener.onCoHostUserLeft?.call(seatUserInfo);
      });
    }
  }

  void _onConnectionRequestReceived(TUIConnectionUser inviter, String extensionInfo) {
    _log.info('Observer onConnectionRequestReceived inviter:$inviter, extensionInfo:$extensionInfo');
    _coHostState.applicantValue.value = _seatUserInfoFromConnectionUser(inviter);
    final seatUserInfo = _seatUserInfoFromConnectionUser(inviter);
    _listenerDispatcher.notify((listener) {
      listener.onCoHostRequestReceived?.call(seatUserInfo, extensionInfo);
    });
  }

  void _onConnectionRequestCancelled(TUIConnectionUser inviter) {
    _log.info('Observer onConnectionRequestCancelled inviter:$inviter');
    _coHostState.applicantValue.value = null;
    final invitee = SeatUserInfo(
        liveID: _liveID,
        userID: _selfUserInfo.userId,
        userName: _selfUserInfo.userName ?? '',
        avatarURL: _selfUserInfo.avatarUrl ?? '');
    final seatUserInfo = _seatUserInfoFromConnectionUser(inviter);
    _listenerDispatcher.notify((listener) {
      listener.onCoHostRequestCancelled?.call(seatUserInfo, invitee);
    });
  }

  void _onConnectionRequestAccept(TUIConnectionUser invitee) {
    _log.info('Observer onConnectionRequestAccept invitee:$invitee');
    _coHostState.inviteesValue.value =
        _coHostState.inviteesValue.value.where((user) => user.liveID != invitee.roomId).toList();
    final seatUserInfo = _seatUserInfoFromConnectionUser(invitee);
    _listenerDispatcher.notify((listener) {
      listener.onCoHostRequestAccepted?.call(seatUserInfo);
    });
  }

  void _onConnectionRequestReject(TUIConnectionUser invitee) {
    _log.info('Observer onConnectionRequestReject invitee:$invitee');
    _coHostState.inviteesValue.value =
        _coHostState.inviteesValue.value.where((user) => user.liveID != invitee.roomId).toList();
    final seatUserInfo = _seatUserInfoFromConnectionUser(invitee);
    _listenerDispatcher.notify((listener) {
      listener.onCoHostRequestRejected?.call(seatUserInfo);
    });
  }

  void _onConnectionRequestTimeout(TUIConnectionUser inviter, TUIConnectionUser invitee) {
    _log.info('Observer onConnectionRequestTimeout inviter:$inviter, invitee:$invitee');
    if (inviter.roomId == _liveID) {
      _coHostState.inviteesValue.value = [];
    } else {
      _coHostState.applicantValue.value = null;
    }
    final inviterSeatUserInfo = _seatUserInfoFromConnectionUser(inviter);
    final inviteeSeatUserInfo = _seatUserInfoFromConnectionUser(invitee);
    _listenerDispatcher.notify((listener) {
      listener.onCoHostRequestTimeout?.call(
        inviterSeatUserInfo,
        inviteeSeatUserInfo,
      );
    });
  }

  SeatUserInfo _seatUserInfoFromConnectionUser(TUIConnectionUser user) {
    return SeatUserInfo(liveID: user.roomId, userID: user.userId, userName: user.userName, avatarURL: user.avatarUrl);
  }

  SeatUserInfo _convertToSeatUserInfo(TUILiveInfo liveInfo) {
    return SeatUserInfo(
        liveID: liveInfo.roomId,
        userID: liveInfo.ownerId,
        userName: liveInfo.ownerName,
        avatarURL: liveInfo.ownerAvatarUrl);
  }
}
