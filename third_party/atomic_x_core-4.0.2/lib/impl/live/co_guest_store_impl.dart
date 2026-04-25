import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/api/live/co_guest_store.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' hide DeviceStatus;

import '../../api/define.dart';
import '../../api/device/device_store.dart';
import '../../api/live/live_audience_store.dart';
import '../../api/live/live_list_store.dart';
import '../../api/live/live_seat_store.dart';
import '../../impl/live/live_list_store_define.dart';
import '../common/listener_dispatcher.dart';
import '../common/type_converter.dart';
import '../common/future_converter.dart';
import '../common/log.dart';
import 'store_factory.dart';

class _CoGuestStateImpl implements CoGuestState {
  final ValueNotifier<List<SeatUserInfo>> connectedValue = ValueNotifier([]);
  final ValueNotifier<List<LiveUserInfo>> inviteesValue = ValueNotifier([]);
  final ValueNotifier<List<LiveUserInfo>> applicantsValue = ValueNotifier([]);
  final ValueNotifier<List<LiveUserInfo>> candidatesValue = ValueNotifier([]);

  @override
  ValueListenable<List<SeatUserInfo>> get connected => connectedValue;

  @override
  ValueListenable<List<LiveUserInfo>> get invitees => inviteesValue;

  @override
  ValueListenable<List<LiveUserInfo>> get applicants => applicantsValue;

  @override
  ValueListenable<List<LiveUserInfo>> get candidates => candidatesValue;
}

class CoGuestStoreImpl extends CoGuestStore implements IStore {
  final _CoGuestStateImpl _coGuestState = _CoGuestStateImpl();
  final ListenerDispatcher<HostListener> _hostListenerDispatcher = ListenerDispatcher();
  final ListenerDispatcher<GuestListener> _guestListenerDispatcher = ListenerDispatcher();
  final String liveID;
  final TUIRoomEngine _roomEngine = TUIRoomEngine.sharedInstance();
  late final TUIRoomObserver _roomEngineObserver;
  LiveInfo? _liveInfo;
  final Set<String> _hasAudioStreamUserList = {};
  final Map<String, TUIRequest> _applyMap = {};
  final Map<String, TUIRequest> _inviteMap = {};
  TUIRequest? _guestApplicationSent;
  TUIRequest? _guestInvitationReceived;

  final Log _log = Log.getLiveLog('CoGuestStoreImpl');

  CoGuestStoreImpl(this.liveID) {
    _initObserver();
  }

  @override
  void beforeEnterRoom(String liveID) {
    _roomEngine.addObserver(_roomEngineObserver);
  }

  @override
  void afterEnterRoom(LiveInfo liveInfo) {
    _liveInfo = liveInfo;
    _initConnectedList();
    if (isOwner()) {
      _initSeatApplicationList();
    }
  }

  @override
  void leaveRoom(String liveID) {
    _hostListenerDispatcher.cleanup();
    _guestListenerDispatcher.cleanup();
    _roomEngine.removeObserver(_roomEngineObserver);
  }

  @override
  CoGuestState get coGuestState => _coGuestState;

  @override
  void addHostListener(HostListener listener) {
    _log.info('API addHostListener listener:${listener.hashCode}');
    _hostListenerDispatcher.addListener(listener);
  }

  @override
  void removeHostListener(HostListener listener) {
    _log.info('API removeHostListener listener:${listener.hashCode}');
    _hostListenerDispatcher.removeListener(listener);
  }

  @override
  void addGuestListener(GuestListener listener) {
    _log.info('API addGuestListener listener:${listener.hashCode}');
    _guestListenerDispatcher.addListener(listener);
  }

  @override
  void removeGuestListener(GuestListener listener) {
    _log.info('API removeGuestListener listener:${listener.hashCode}');
    _guestListenerDispatcher.removeListener(listener);
  }

  @override
  Future<CompletionHandler> applyForSeat({
    required int seatIndex,
    required int timeout,
    String? extraInfo,
  }) async {
    _log.info("API applyForSeat seatIndex:$seatIndex, timeout:$timeout, extraInfo:$extraInfo");
    final handler = CompletionHandler();
    final Completer<CompletionHandler> completer = Completer();
    final requestCallback = TUIRequestCompletion(onAccepted: (requestID, userInfo, extensionInfo) {
      _log.info(
          "Response applyForSeat onSuccess onAccepted, requestID=$requestID, userInfo=${userInfo.userId}, extensionInfo=$extensionInfo");
      _guestApplicationSent = null;
      final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(userInfo);
      _guestListenerDispatcher.notify((listener) {
        listener.onGuestApplicationResponded?.call(true, liveUserInfo);
      });
      _handleCompleter(completer: completer, handler: handler);
    }, onRejected: (requestID, userInfo, message, extensionInfo) {
      _log.info(
          "Response applyForSeat onSuccess onRejected, requestID=$requestID, userInfo=${userInfo.userId}, message=$message, extensionInfo=$extensionInfo");
      _guestApplicationSent = null;
      final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(userInfo);
      _guestListenerDispatcher.notify((listener) {
        listener.onGuestApplicationResponded?.call(false, liveUserInfo);
      });
      _handleCompleter(completer: completer, handler: handler);
    }, onCancelled: (requestID, userInfo) {
      _log.info("Response applyForSeat onSuccess onCancelled, requestID=$requestID, userInfo=${userInfo.userId}");
      _guestApplicationSent = null;
      _handleCompleter(completer: completer, handler: handler);
    }, onTimeout: (requestID, userInfo) {
      _log.info("Response applyForSeat onSuccess onTimeout, requestID=$requestID, userInfo=${userInfo.userId}");
      _guestApplicationSent = null;
      _guestListenerDispatcher.notify((listener) {
        listener.onGuestApplicationNoResponse?.call(NoResponseReason.timeout);
      });
      _handleCompleter(completer: completer, handler: handler);
    }, onError: (requestID, userInfo, error, message) {
      _log.error(
          "Response applyForSeat onError, requestID=$requestID, userInfo=${userInfo.userId}, code:${error.rawValue}, message:$message");
      handler.errorCode = error.rawValue;
      handler.errorMessage = message;
      _handleCompleter(completer: completer, handler: handler);
    });
    final request =
        _roomEngine.takeSeatEx(seatIndex, timeout, extensionInfo: extraInfo ?? '', requestCompletion: requestCallback);
    _guestApplicationSent = request;
    return completer.future;
  }

  @override
  Future<CompletionHandler> cancelApplication() async {
    _log.info("API cancelApplication");
    final handler = CompletionHandler();
    if (_guestApplicationSent == null) {
      _log.error(
          "Response cancelApplication onError code:${TUIError.errFailed.rawValue}, message:No application is requesting");
      handler.errorCode = TUIError.errFailed.rawValue;
      handler.errorMessage = 'No application is requesting';
      return handler;
    }

    final result = await _roomEngine.cancelRequest(_guestApplicationSent?.requestId ?? '');
    if (result.code == TUIError.success) {
      _log.info("Response cancelApplication onSuccess");
      _guestApplicationSent = null;
    } else {
      _log.error("Response cancelApplication onError code:${result.code.rawValue}, message:${result.message}");
    }
    return handleCallback(result);
  }

  @override
  Future<CompletionHandler> acceptApplication(String userID) {
    _log.info("API acceptApplication userID:$userID");
    return _responseApplication(true, userID);
  }

  @override
  Future<CompletionHandler> rejectApplication(String userID) {
    _log.info("API rejectApplication userID:$userID");
    return _responseApplication(false, userID);
  }

  @override
  Future<CompletionHandler> inviteToSeat({
    required String inviteeID,
    required int seatIndex,
    required int timeout,
    String? extraInfo,
  }) async {
    _log.info("API inviteToSeat inviteeID:$inviteeID, seatIndex:$seatIndex, timeout:$timeout, extraInfo:$extraInfo");
    final handler = CompletionHandler();
    Completer<CompletionHandler> completer = Completer();
    final requestCallback = TUIRequestCompletion(onAccepted: (requestID, userInfo, extensionInfo) {
      _log.info(
          "Response inviteToSeat onSuccess onAccepted, requestID=$requestID, userInfo=${userInfo.userId}, extensionInfo=$extensionInfo");
      _removeInviteRequest(userInfo.userId);
      final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(userInfo);
      _hostListenerDispatcher.notify((listener) {
        listener.onHostInvitationResponded?.call(true, liveUserInfo);
      });
      _handleCompleter(completer: completer, handler: handler);
    }, onRejected: (requestID, userInfo, message, extensionInfo) {
      _log.info(
          "Response inviteToSeat onSuccess onRejected, requestID=$requestID, userInfo=${userInfo.userId}, message=$message, extensionInfo=$extensionInfo");
      _removeInviteRequest(userInfo.userId);
      final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(userInfo);
      _hostListenerDispatcher.notify((listener) {
        listener.onHostInvitationResponded?.call(false, liveUserInfo);
      });
      _handleCompleter(completer: completer, handler: handler);
    }, onCancelled: (requestID, userInfo) {
      _log.info("Response inviteToSeat onSuccess onCancelled, requestID=$requestID, userInfo=${userInfo.userId}");
      _removeInviteRequest(userInfo.userId);
      _handleCompleter(completer: completer, handler: handler);
    }, onTimeout: (requestID, userInfo) {
      _log.info("Response inviteToSeat onSuccess onTimeout, requestID=$requestID, userInfo=${userInfo.userId}");
      _removeInviteRequest(userInfo.userId);
      final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(userInfo);
      _hostListenerDispatcher.notify((listener) {
        listener.onHostInvitationNoResponse?.call(liveUserInfo, NoResponseReason.timeout);
      });
      _handleCompleter(completer: completer, handler: handler);
    }, onError: (requestID, userInfo, error, message) {
      _log.info(
          "Response inviteToSeat onError, requestID=$requestID, userInfo=${userInfo.userId}, code:${error.rawValue}, message:$message");
      handler.errorCode = error.rawValue;
      handler.errorMessage = message;
      _handleCompleter(completer: completer, handler: handler);
    });
    final request = _roomEngine.takeUserOnSeatByAdminEx(seatIndex, inviteeID, timeout,
        extensionInfo: extraInfo ?? '', requestCompletion: requestCallback);
    _addInviteRequest(request);
    return completer.future;
  }

  @override
  Future<CompletionHandler> cancelInvitation(String inviteeID) async {
    _log.info("API cancelInvitation inviteeID:$inviteeID");
    final handler = CompletionHandler();
    final request = _inviteMap[inviteeID];
    if (request == null) {
      handler.errorCode = TUIError.errFailed.rawValue;
      handler.errorMessage = 'No invitation is requesting';
      _log.error("Response cancelInvitation onError reason: No invitation is requesting");
      return handler;
    }

    final result = await _roomEngine.cancelRequest(request.requestId);
    if (result.code == TUIError.success) {
      _removeInviteRequest(inviteeID);
    }
    handler.isSuccess
        ? _log.info("Response cancelInvitation onSuccess")
        : _log.error("Response cancelInvitation onError code:${result.code.rawValue}, message:${result.message}");
    return handler;
  }

  @override
  Future<CompletionHandler> acceptInvitation(String inviterID) {
    _log.info("API acceptInvitation inviterID:$inviterID");
    return _responseInvitation(true, inviterID);
  }

  @override
  Future<CompletionHandler> rejectInvitation(String inviterID) {
    _log.info("API rejectInvitation inviterID:$inviterID");
    return _responseInvitation(false, inviterID);
  }

  @override
  Future<CompletionHandler> disconnect() async {
    final result = await _roomEngine.leaveSeat();
    final handler = handleCallback(result);
    if (handler.isSuccess) {
      _log.info("Response disconnect onSuccess");
    } else {
      _log.error("Response disconnect onError code:${result.code.rawValue}, message:${result.message}");
    }
    return handler;
  }
}

extension on CoGuestStoreImpl {
  bool isOwner() {
    if (_liveInfo?.liveOwner.userID == null) {
      return false;
    }
    if (_liveInfo!.liveOwner.userID.isEmpty) {
      return false;
    }
    return TUIRoomEngine.getSelfInfo().userId == _liveInfo!.liveOwner.userID;
  }

  void _initObserver() {
    _roomEngineObserver = TUIRoomObserver(onRequestReceived: (request) {
      switch (request.requestAction) {
        case TUIRequestAction.requestToTakeSeat:
          _log.info("Observer onGuestApplicationReceived guestUser:${request.fromUser.userId}");
          _addApplyRequest(request);
          final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(request.fromUser);
          _hostListenerDispatcher.notify((listener) {
            listener.onGuestApplicationReceived?.call(liveUserInfo);
          });
          break;
        case TUIRequestAction.requestRemoteUserOnSeat:
          _log.info("Observer onHostInvitationReceived hostUser:${request.fromUser.userId}");
          _guestInvitationReceived = request;
          final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(request.fromUser);
          _guestListenerDispatcher.notify((listener) {
            listener.onHostInvitationReceived?.call(liveUserInfo);
          });
          break;
        default:
          break;
      }
    }, onRequestCancelled: (request, operateUser) {
      switch (request.requestAction) {
        case TUIRequestAction.requestToTakeSeat:
          _log.info("Observer onGuestApplicationCancelled guestUser:${request.fromUser.userId}");
          _removeApplyRequest(request.fromUser.userId);
          final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(request.fromUser);
          _hostListenerDispatcher.notify((listener) {
            listener.onGuestApplicationCancelled?.call(liveUserInfo);
          });
          break;
        case TUIRequestAction.requestRemoteUserOnSeat:
          _log.info("Observer onHostInvitationCancelled hostUser:${request.fromUser.userId}");
          _guestInvitationReceived = null;
          final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(request.fromUser);
          _guestListenerDispatcher.notify((listener) {
            listener.onHostInvitationCancelled?.call(liveUserInfo);
          });
          break;
        default:
          break;
      }
    }, onRequestProcessed: (request, operateUser) {
      if (request.requestAction == TUIRequestAction.requestToTakeSeat) {
        _log.info(
            "Observer onGuestApplicationProcessedByOtherHost guestUser:${request.fromUser.userId}, hostUser:${operateUser.userId}");
        _removeApplyRequest(request.fromUser.userId);
        final guestLiveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(request.fromUser);
        final hostLiveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(operateUser);
        _hostListenerDispatcher.notify((listener) {
          listener.onGuestApplicationProcessedByOtherHost?.call(guestLiveUserInfo, hostLiveUserInfo);
        });
      }
    }, onSeatListChangedEx: (roomId, seatList, seatedList, leftList) {
      if (roomId != liveID) return;
      _updateConnectedList(seatList);
    }, onUserAudioStateChanged: (userID, hasAudio, reason) {
      if (hasAudio) {
        _hasAudioStreamUserList.add(userID);
      } else {
        _hasAudioStreamUserList.remove(userID);
      }

      final microphoneStatus = hasAudio ? DeviceStatus.on : DeviceStatus.off;
      _coGuestState.connectedValue.value = _coGuestState.connected.value.toList().map((seatUser) {
        if (seatUser.userID == userID) {
          return SeatUserInfo(
              userID: seatUser.userID,
              userName: seatUser.userName,
              avatarURL: seatUser.avatarURL,
              role: seatUser.role,
              liveID: seatUser.liveID,
              microphoneStatus: microphoneStatus,
              allowOpenMicrophone: seatUser.allowOpenMicrophone,
              cameraStatus: seatUser.cameraStatus,
              allowOpenCamera: seatUser.allowOpenCamera);
        }
        return seatUser;
      }).toList();
    }, onKickedOffSeatEx: (seatIndex, operateUser, extensionInfo) {
      _log.info(
          "Observer onKickedOffSeatEx seatIndex:$seatIndex, hostUser:${operateUser.userId}, extensionInfo:$extensionInfo");
      final liveUserInfo = TypeConverter.liveUserInfoFromEngineUserInfo(operateUser);
      _guestListenerDispatcher.notify((listener) {
        listener.onKickedOffSeat?.call(seatIndex, liveUserInfo);
      });
    });
  }

  void _initConnectedList() async {
    final result = _roomEngine.querySeatList();
    _updateConnectedList(result);
    _leaveSeatWhenEnterRoomByAudience();
  }

  void _updateConnectedList(List<SeatFullInfo> seatList) {
    _coGuestState.connectedValue.value =
        seatList.where((seat) => seat.userId.isNotEmpty && seat.roomId == liveID).toList().map((seat) {
      final isOwner = _liveInfo?.liveOwner.userID == seat.userId;
      return TypeConverter.seatUserInfoFromEngineSeatInfo(seat, isOwner);
    }).toList();
  }

  void _leaveSeatWhenEnterRoomByAudience() {
    if (isOwner()) return;
    if (_liveInfo?.isVoiceRoom() == true) return;
    if (!_coGuestState.connected.value.any((seatUserInfo) => seatUserInfo.userID == TUIRoomEngine.getSelfInfo().userId)) return;
    disconnect();
  }

  void _initSeatApplicationList() async {
    final result = await _roomEngine.getSeatApplicationList();
    if (result.code == TUIError.success && result.data != null) {
      final seatApplicationList = result.data!;
      for (var seatApplication in seatApplicationList) {
        _addInviteRequest(seatApplication);
      }
    }
  }

  Future<CompletionHandler> _responseApplication(bool isAccept, String userID) async {
    CompletionHandler handler = CompletionHandler();
    final request = _applyMap[userID];
    if (request == null) {
      handler.errorCode = TUIError.errFailed.rawValue;
      handler.errorMessage = 'Not receiving requests';
      _log.error("Response responseApplication onError reason:Not receiving requests");
      return handler;
    }

    final result = await _roomEngine.responseRemoteRequest(request.requestId, isAccept);
    if (result.code == TUIError.success) {
      _removeApplyRequest(userID);
    }
    handler = handleCallback(result);
    if (handler.isSuccess) {
      _log.info("Response responseApplication onSuccess");
    } else {
      _log.error("Response responseApplication onError code:${handler.errorCode}, message:${handler.errorMessage}");
    }
    return handler;
  }

  Future<CompletionHandler> _responseInvitation(bool isAccept, String userID) async {
    CompletionHandler handler = CompletionHandler();
    if (_guestInvitationReceived == null) {
      handler.errorCode = TUIError.errFailed.rawValue;
      handler.errorMessage = 'Not receiving requests';
      _log.error("Response responseInvitation onError reason:Not receiving requests");
      return handler;
    }

    final result = await _roomEngine.responseRemoteRequest(_guestInvitationReceived!.requestId, isAccept);
    if (result.code == TUIError.success) {
      _guestInvitationReceived == null;
    }
    handler = handleCallback(result);
    if (handler.isSuccess) {
      _log.info("Response responseInvitation onSuccess");
    } else {
      _log.error("Response responseInvitation onError code:${handler.errorCode}, message:${handler.errorMessage}");
    }
    return handler;
  }

  void _addApplyRequest(TUIRequest request) {
    _coGuestState.applicantsValue.value = [
      ..._coGuestState.applicants.value,
      TypeConverter.liveUserInfoFromEngineUserInfo(request.fromUser)
    ];
    _applyMap[request.fromUser.userId] = request;
  }

  void _addInviteRequest(TUIRequest request) {
    _coGuestState.inviteesValue.value = [
      ..._coGuestState.invitees.value,
      TypeConverter.liveUserInfoFromEngineUserInfo(request.toUser)
    ];
    _inviteMap[request.toUser.userId] = request;
  }

  void _removeApplyRequest(String userID) {
    _applyMap.remove(userID);
    _coGuestState.applicantsValue.value =
        _coGuestState.applicants.value.toList().where((applicant) => applicant.userID != userID).toList();
  }

  void _removeInviteRequest(String userID) {
    _inviteMap.remove(userID);
    _coGuestState.inviteesValue.value =
        _coGuestState.invitees.value.toList().where((invitee) => invitee.userID != userID).toList();
  }
}

extension on CoGuestStoreImpl {
  void _handleCompleter({required Completer<CompletionHandler> completer, required CompletionHandler handler}) async {
    if (completer.isCompleted) return;
    completer.complete(handler);
  }
}
