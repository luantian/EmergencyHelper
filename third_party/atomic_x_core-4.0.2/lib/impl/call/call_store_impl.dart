part of '../../api/call/call_store.dart';

class _CallStateImpl implements CallState {
  final ValueNotifier<CallInfo> activeCallValue = ValueNotifier(CallInfo._());
  final ValueNotifier<List<CallInfo>> recentCallsValue = ValueNotifier([]);
  final ValueNotifier<String> cursorValue = ValueNotifier('');

  final ValueNotifier<CallParticipantInfo> selfInfoValue =
      ValueNotifier<CallParticipantInfo>(CallParticipantInfo._());
  final ValueNotifier<List<CallParticipantInfo>> allParticipantsValue =
      ValueNotifier<List<CallParticipantInfo>>([]);
  final ValueNotifier<Map<String, int>> speakerVolumesValue =
      ValueNotifier<Map<String, int>>({});
  final ValueNotifier<Map<String, NetworkQuality>> networkQualitiesValue =
      ValueNotifier<Map<String, NetworkQuality>>({});

  @override
  ValueListenable<CallInfo> get activeCall => activeCallValue;

  @override
  ValueListenable<List<CallInfo>> get recentCalls => recentCallsValue;

  @override
  ValueListenable<String> get cursor => cursorValue;

  @override
  ValueListenable<CallParticipantInfo> get selfInfo => selfInfoValue;

  @override
  ValueListenable<List<CallParticipantInfo>> get allParticipants =>
      allParticipantsValue;

  @override
  ValueListenable<Map<String, int>> get speakerVolumes => speakerVolumesValue;

  @override
  ValueListenable<Map<String, NetworkQuality>> get networkQualities =>
      networkQualitiesValue;
}

class _CallStoreImpl implements CallStore {
  _CallStateImpl stateNotifier = _CallStateImpl();
  ListenerDispatcher<CallEventListener> listenerDispatcher =
      ListenerDispatcher();

  @override
  CallState get state => stateNotifier;

  late engine.TUICallObserver _callObserver;

  Timer? _timer;
  int _duration = 0;

  _CallStoreImpl() {
    LoginStore.shared.addListener(_loginStoreListener);

    _callObserver = _getCallObserver();
    engine.TUICallEngine.instance.addObserver(_callObserver);
  }

  _loginStoreListener() {
    LoginState loginState = LoginStore.shared.loginState;
    if (loginState.loginStatus == LoginStatus.logined) {
      CallParticipantInfo oldValue = stateNotifier.selfInfoValue.value;
      CallParticipantInfo newValue = oldValue.copyWith(
        id: loginState.loginUserInfo?.userID ?? "",
        name: loginState.loginUserInfo?.nickname ?? "",
        avatarURL: loginState.loginUserInfo?.avatarURL ?? "",
      );
      stateNotifier.selfInfoValue.value = newValue;
    } else if (loginState.loginStatus == LoginStatus.unlogin) {
      _resetState();
    }
  }

  _resetState() {
    _resetDeviceStatus();
    stateNotifier.activeCallValue.value = CallInfo._();
    CallParticipantInfo oldValue = stateNotifier.selfInfoValue.value;
    CallParticipantInfo newValue = oldValue.copyWith(
      status: CallParticipantStatus.none,
      isMicrophoneOpened: false,
      isCameraOpened: false,
    );
    stateNotifier.selfInfoValue.value = newValue;

    stateNotifier.allParticipantsValue.value = [];
    stateNotifier.speakerVolumesValue.value = {};
    stateNotifier.networkQualitiesValue.value = {};
  }

  @override
  void addListener(CallEventListener listener) {
    listenerDispatcher.addListener(listener);
  }

  @override
  void removeListener(CallEventListener listener) {
    listenerDispatcher.removeListener(listener);
  }

  @override
  Future<CompletionHandler> calls(List<String> participantIds,
      CallMediaType mediaType, CallParams? params) {
    DataReport.reportAtomicMetrics(AtomicMetrics.call);
    DeviceStore.shared.setFocus(DeviceFocusOwner.call);
    return engine.TUICallEngine.instance
        .calls(participantIds, CallStoreConverter.toTUICallMediaType(mediaType),
            CallStoreConverter.toTUICallParams(params))
        .then((result) {
      CompletionHandler handler = handleCallback(result, onSuccess: (_) {
        CallInfo oldValue = stateNotifier.activeCallValue.value;
        CallInfo newValue = oldValue.copyWith(
          mediaType: mediaType,
          inviterId: LoginStore.shared.loginState.loginUserInfo?.userID ?? "",
          inviteeIds: participantIds,
          chatGroupId: params?.chatGroupId ?? "",
          roomId: params?.roomId ?? "",
        );
        stateNotifier.activeCallValue.value = newValue;
        listenerDispatcher.notify((listener) {
          listener.onCallStarted?.call(
            "",
            mediaType,
          );
        });
      });
      return handler;
    }).catchError((error) {
      return _buildErrorHandler(error);
    });
  }

  @override
  Future<CompletionHandler> accept() {
    return engine.TUICallEngine.instance.accept().then((result) {
      return handleCallback(result);
    }).catchError((error) {
      return _buildErrorHandler(error);
    });
  }

  @override
  Future<CompletionHandler> reject() {
    return engine.TUICallEngine.instance.reject().then((result) {
      return handleCallback(result, onSuccess: (_) {
        stateNotifier.activeCallValue.value = CallInfo._();
      });
    }).catchError((error) {
      return _buildErrorHandler(error);
    });
  }

  @override
  Future<CompletionHandler> hangup() {
    return engine.TUICallEngine.instance.hangup().then((result) {
      return handleCallback(result, onSuccess: (_) {
        stateNotifier.activeCallValue.value = CallInfo._();
      });
    }).catchError((error) {
      return _buildErrorHandler(error);
    });
  }

  @override
  Future<CompletionHandler> join(String callId) {
    DeviceStore.shared.setFocus(DeviceFocusOwner.call);
    return engine.TUICallEngine.instance.join(callId).then((result) {
      final existingMediaType = stateNotifier.activeCallValue.value.mediaType;
      CompletionHandler handler = handleCallback(result, onSuccess: (_) {
        CallInfo oldValue = stateNotifier.activeCallValue.value;
        CallInfo newValue = oldValue.copyWith(
          callId: callId,
          mediaType: existingMediaType,
        );
        stateNotifier.activeCallValue.value = newValue;
        if (existingMediaType != null) {
          listenerDispatcher.notify((listener) {
            listener.onCallStarted?.call(
              callId,
              existingMediaType,
            );
          });
        }
      });
      return handler;
    }).catchError((error) {
      return _buildErrorHandler(error);
    });
  }

  @override
  Future<CompletionHandler> invite(
      List<String> participantIds, CallParams? params) {
    return engine.TUICallEngine.instance
        .inviteUser(participantIds, CallStoreConverter.toTUICallParams(params))
        .then((result) {
      return handleCallback(result);
    }).catchError((error) {
      return _buildErrorHandler(error);
    });
  }

  @override
  Future<CompletionHandler> queryRecentCalls(String cursor, int count) {
    return engine.TUICallEngine.instance
        .queryRecentCalls(engine.TUICallRecentCallsFilter())
        .then((result) {
      return handleCallback(result, onSuccess: (data) {
        List<engine.TUICallRecords>? records = data;
        List<CallInfo> callInfoList = [];
        if (records != null) {
          for (engine.TUICallRecords record in records) {
            CallInfo callInfo = CallInfo._(
              callId: record.callId ?? "",
              chatGroupId: record.groupId ?? "",
              mediaType: CallStoreConverter.toCallMediaType(
                  record.mediaType ?? engine.TUICallMediaType.none),
              inviterId: record.inviter ?? "",
              inviteeIds: record.inviteList ?? [],
              result: CallStoreConverter.toCallDirection(
                  record.result ?? engine.TUICallResultType.unknown),
              startTime: record.beginTime ?? 0,
              duration: record.totalTime ?? 0,
            );
            callInfoList.add(callInfo);
          }
        }
        stateNotifier.recentCallsValue.value = callInfoList;
      });
    });
  }

  @override
  Future<CompletionHandler> deleteRecordCalls(List<String> callIdList) {
    return engine.TUICallEngine.instance
        .deleteRecordCalls(callIdList)
        .then((result) {
      return handleCallback(result, onSuccess: (data) {
        List<CallInfo> records = stateNotifier.recentCallsValue.value;
        final callIdSet = Set<String>.from(data);
        List<CallInfo> newRecords = records
            .where((callInfo) => !callIdSet.contains(callInfo.callId))
            .toList();
        stateNotifier.recentCallsValue.value = newRecords;
      });
    });
  }

  @override
  Future<void> callExperimentalAPI(Map<String, dynamic> jsonMap) async {
    await engine.TUICallEngine.instance.callExperimentalAPI(jsonMap);
  }

  @override
  void populateCallerState(String selfUserId, String selfUserName, List<String> inviteeIds, CallMediaType mediaType) {
    debugPrint('[TRTC-DEBUG][CallStore] populateCallerState: selfUserId=$selfUserId inviteeIds=$inviteeIds mediaType=$mediaType');
    // Populate selfInfo
    CallParticipantInfo selfInfo = stateNotifier.selfInfoValue.value;
    selfInfo = CallParticipantInfo._(
      id: selfUserId,
      name: selfUserName,
      avatarURL: selfInfo.avatarURL,
      status: CallParticipantStatus.waiting,
      isMicrophoneOpened: false,
      isCameraOpened: false,
    );
    stateNotifier.selfInfoValue.value = selfInfo;

    // Populate activeCall
    CallInfo activeCall = stateNotifier.activeCallValue.value;
    activeCall = CallInfo._(
      callId: activeCall.callId,
      roomId: activeCall.roomId,
      inviterId: selfUserId,
      inviteeIds: inviteeIds,
      chatGroupId: activeCall.chatGroupId,
      mediaType: mediaType,
      result: CallDirection.outgoing,
      startTime: activeCall.startTime,
      duration: activeCall.duration,
    );
    stateNotifier.activeCallValue.value = activeCall;
  }

  _getCallObserver() {
    return engine.TUICallObserver(
      onCallReceived: (callId, callerId, calleeIdList, mediaType, info) {
        DeviceStore.shared.setFocus(DeviceFocusOwner.call);
        CallInfo oldValue = stateNotifier.activeCallValue.value;
        CallInfo newValue = oldValue.copyWith(
          callId: callId,
          roomId: info.roomId.strRoomId,
          chatGroupId: info.chatGroupId,
          mediaType: CallStoreConverter.toCallMediaType(mediaType),
          inviterId: callerId,
          inviteeIds: calleeIdList,
        );
        stateNotifier.activeCallValue.value = newValue;

        // Populate selfInfo with the current user's ID from the room engine.
        // This is critical for CallParticipantView to correctly identify
        // local vs remote streams on the callee side.
        var selfUserId = engine.TUIRoomEngine.getSelfInfo().userId ?? '';
        debugPrint('[TRTC-DEBUG][CallStore] onCallReceived: selfUserId=$selfUserId calleeList=$calleeIdList');
        CallParticipantInfo selfInfo = stateNotifier.selfInfoValue.value;
        selfInfo = CallParticipantInfo._(
          id: selfUserId,
          name: selfInfo.name.isEmpty ? selfUserId : selfInfo.name,
          avatarURL: selfInfo.avatarURL,
          status: CallParticipantStatus.waiting,
          isMicrophoneOpened: false,
          isCameraOpened: false,
        );
        stateNotifier.selfInfoValue.value = selfInfo;

        List<String> allParticipantIds = List.from(calleeIdList);
        allParticipantIds.add(callerId);
        _updateParticipantsWithFriendInfo(
            allParticipantIds, CallParticipantStatus.waiting);

        listenerDispatcher.notify((listener) {
          listener.onCallReceived?.call(
            callId,
            CallStoreConverter.toCallMediaType(mediaType) ??
                CallMediaType.audio,
            info.userData,
          );
        });
      },
      onCallBegin: (callId, mediaType, info) {
        _startTimer();
        CallInfo oldValue = stateNotifier.activeCallValue.value;
        CallInfo newValue = oldValue.copyWith(
          callId: callId,
          chatGroupId: info.chatGroupId,
          mediaType: CallStoreConverter.toCallMediaType(mediaType),
          roomId: info.roomId.strRoomId,
          startTime: DateTime.now().millisecondsSinceEpoch,
        );
        stateNotifier.activeCallValue.value = newValue;

        List<CallParticipantInfo> allParticipants =
            List.from(stateNotifier.allParticipantsValue.value);
        CallParticipantInfo selfInfo = stateNotifier.selfInfoValue.value;

        int existingIndex =
            allParticipants.indexWhere((info) => info.id == selfInfo.id);
        if (existingIndex != -1) {
          allParticipants[existingIndex] = allParticipants[existingIndex]
              .copyWith(status: CallParticipantStatus.accept);
        } else {
          allParticipants
              .add(selfInfo.copyWith(status: CallParticipantStatus.accept));
        }

        stateNotifier.selfInfoValue.value =
            selfInfo.copyWith(status: CallParticipantStatus.accept);
        stateNotifier.allParticipantsValue.value = allParticipants;
      },
      onCallEnd: (callId, mediaType, reason, userId, totalTime, info) {
        _stopTimer();
        // Clear stale local view ID so next call's CallParticipantView
        // doesn't think its new camera is a duplicate.
        setLocalCallViewId(0);
        listenerDispatcher.notify((listener) {
          listener.onCallEnded?.call(
              callId,
              CallStoreConverter.toCallMediaType(mediaType) ??
                  CallMediaType.audio,
              CallStoreConverter.toCallEndReason(reason),
              userId);
        });
        _resetState();
      },
      onCallNotConnected: (callId, mediaType, reason, userId, info) {
        setLocalCallViewId(0);
        listenerDispatcher.notify((listener) {
          listener.onCallEnded?.call(
              callId,
              CallStoreConverter.toCallMediaType(mediaType) ??
                  CallMediaType.audio,
              CallStoreConverter.toCallEndReason(reason),
              userId);
        });
        _resetState();
      },
      onUserJoin: (userId) {
        _updateParticipantsWithFriendInfo(
            [userId], CallParticipantStatus.accept);
      },
      onUserLeave: (userId) {
        List<CallParticipantInfo> allParticipants =
            List.from(stateNotifier.allParticipantsValue.value);
        allParticipants.removeWhere((info) => info.id == userId);
        stateNotifier.allParticipantsValue.value = allParticipants;
      },
      onUserReject: (userId) {
        List<CallParticipantInfo> allParticipants =
            List.from(stateNotifier.allParticipantsValue.value);
        allParticipants.removeWhere((info) => info.id == userId);
        stateNotifier.allParticipantsValue.value = allParticipants;
      },
      onUserInviting: (userId) {
        if (stateNotifier.allParticipantsValue.value.isEmpty) {
          List<CallParticipantInfo> allParticipants =
              List.from(stateNotifier.allParticipantsValue.value);
          CallParticipantInfo selfInfo = stateNotifier.selfInfoValue.value;
          allParticipants.add(selfInfo.copyWith(
            status: CallParticipantStatus.waiting,
          ));
          stateNotifier.selfInfoValue.value = selfInfo.copyWith(
            status: CallParticipantStatus.waiting,
          );
          stateNotifier.allParticipantsValue.value = allParticipants;
        }

        _updateParticipantsWithFriendInfo(
            [userId], CallParticipantStatus.waiting);
      },
      onUserLineBusy: (userId) {
        List<CallParticipantInfo> allParticipants =
            List.from(stateNotifier.allParticipantsValue.value);
        allParticipants.removeWhere((info) => info.id == userId);
        stateNotifier.allParticipantsValue.value = allParticipants;
      },
      onUserNoResponse: (userId) {
        List<CallParticipantInfo> allParticipants =
            List.from(stateNotifier.allParticipantsValue.value);
        allParticipants.removeWhere((info) => info.id == userId);
        stateNotifier.allParticipantsValue.value = allParticipants;
      },
      onUserVoiceVolumeChanged: (volumeMap) {
        stateNotifier.speakerVolumesValue.value = volumeMap;
      },
      onUserNetworkQualityChanged: (networkQualityList) {
        stateNotifier.networkQualitiesValue.value = {
          for (var networkInfo in networkQualityList)
            networkInfo.userId:
                CallStoreConverter.toNetworkQuality(networkInfo.quality)
        };
      },
      onUserAudioAvailable: (userId, isAvailable) {
        _updateParticipantInfo(userId, {
          _CallParticipantInfoKey.isMicrophoneOpened: isAvailable,
        });
      },
      onUserVideoAvailable: (userId, isAvailable) {
        _updateParticipantInfo(userId, {
          _CallParticipantInfoKey.isCameraOpened: isAvailable,
        });
      },
      onKickedOffline: () {
        _resetState();
      },
    );
  }

  Future<void> _updateParticipantsWithFriendInfo(
      List<String> userIds, CallParticipantStatus callStatus) async {
    final response = await TencentImSDKPlugin.v2TIMManager
        .getFriendshipManager()
        .getFriendsInfo(userIDList: userIds);

    List<CallParticipantInfo> allParticipants =
        List.from(stateNotifier.allParticipantsValue.value);

    for (String userId in userIds) {
      if (!allParticipants.any((info) => info.id == userId)) {
        allParticipants.add(CallParticipantInfo._(
          id: userId,
          name: "",
          remark: "",
          avatarURL: "",
          status: callStatus,
        ));
      }
    }

    if (response.code == 0 && response.data != null) {
      List<V2TimFriendInfoResult> friendInfoResultList = response.data!;

      for (var result in friendInfoResultList) {
        if (result.friendInfo?.userID == null) continue;

        String userId = result.friendInfo!.userID;
        int index = allParticipants.indexWhere((info) => info.id == userId);
        if (index != -1) {
          allParticipants[index] = allParticipants[index].copyWith(
            name: result.friendInfo?.userProfile?.nickName ?? "",
            remark: result.friendInfo?.friendRemark ?? "",
            avatarURL: result.friendInfo?.userProfile?.faceUrl ?? "",
            status: callStatus,
          );
        }
      }
    }

    stateNotifier.allParticipantsValue.value = allParticipants;
  }

  _updateParticipantInfo(
      String userId, Map<_CallParticipantInfoKey, dynamic> map) {
    if (stateNotifier.selfInfoValue.value.id == userId) {
      stateNotifier.selfInfoValue.value =
          stateNotifier.selfInfoValue.value.copyWithMap(map);
    }

    List<CallParticipantInfo> allParticipants =
        List.from(stateNotifier.allParticipantsValue.value);
    int index = allParticipants.indexWhere((info) => info.id == userId);
    if (index != -1) {
      allParticipants[index] = allParticipants[index].copyWithMap(map);
      stateNotifier.allParticipantsValue.value = allParticipants;
    }
  }

  _resetDeviceStatus() {
    if (DeviceStore.shared.state.cameraStatus.value == DeviceStatus.on) {
      DeviceStore.shared.closeLocalCamera();
    }
    if (DeviceStore.shared.state.microphoneStatus.value == DeviceStatus.on) {
      DeviceStore.shared.closeLocalMicrophone();
    }
  }

  _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _duration += 1;
      stateNotifier.activeCallValue.value =
          stateNotifier.activeCallValue.value.copyWith(
        duration: _duration,
      );
    });
  }

  _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _duration = 0;
  }

  CompletionHandler _buildErrorHandler(Object error) {
    final handler = CompletionHandler();
    handler.errorCode = -1;
    handler.errorMessage = error.toString();
    return handler;
  }
}

enum _CallParticipantInfoKey {
  id,
  name,
  avatarURL,
  remark,
  status,
  isMicrophoneOpened,
  isCameraOpened
}

extension _CallInfoExtension on CallInfo {
  CallInfo copyWith({
    String? callId,
    String? roomId,
    String? inviterId,
    List<String>? inviteeIds,
    String? chatGroupId,
    CallMediaType? mediaType,
    CallDirection? result,
    int? startTime,
    int? duration,
  }) {
    return CallInfo._(
      callId: callId ?? this.callId,
      roomId: roomId ?? this.roomId,
      inviterId: inviterId ?? this.inviterId,
      inviteeIds: inviteeIds != null ? List.from(inviteeIds) : this.inviteeIds,
      chatGroupId: chatGroupId ?? this.chatGroupId,
      mediaType: mediaType ?? this.mediaType,
      result: result ?? this.result,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
    );
  }
}

extension _CallParticipantInfoExtension on CallParticipantInfo {
  CallParticipantInfo copyWith({
    String? id,
    String? name,
    String? avatarURL,
    String? remark,
    CallParticipantStatus? status,
    bool? isMicrophoneOpened,
    bool? isCameraOpened,
  }) {
    return CallParticipantInfo._(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarURL: avatarURL ?? this.avatarURL,
      remark: remark ?? this.remark,
      status: status ?? this.status,
      isMicrophoneOpened: isMicrophoneOpened ?? this.isMicrophoneOpened,
      isCameraOpened: isCameraOpened ?? this.isCameraOpened,
    );
  }

  CallParticipantInfo copyWithMap(Map<_CallParticipantInfoKey, dynamic> map) {
    return copyWith(
      id: map[_CallParticipantInfoKey.id],
      name: map[_CallParticipantInfoKey.name],
      avatarURL: map[_CallParticipantInfoKey.avatarURL],
      remark: map[_CallParticipantInfoKey.remark],
      status: map[_CallParticipantInfoKey.status],
      isMicrophoneOpened: map[_CallParticipantInfoKey.isMicrophoneOpened],
      isCameraOpened: map[_CallParticipantInfoKey.isCameraOpened],
    );
  }
}
