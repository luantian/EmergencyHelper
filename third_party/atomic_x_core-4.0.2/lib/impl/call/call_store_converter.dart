import 'dart:math';

import 'package:rtc_room_engine/rtc_room_engine.dart' as engine;
import '../../api/call/call_store.dart';
import '../../api/device/device_store.dart';

class CallStoreConverter {
  static final Map<CallMediaType, engine.TUICallMediaType> _kTUICallMediaTypeMap = {
    CallMediaType.audio: engine.TUICallMediaType.audio,
    CallMediaType.video: engine.TUICallMediaType.video,
  };

  static final Map<engine.TUICallMediaType, CallMediaType?> _kCallMediaTypeMap = {
    engine.TUICallMediaType.audio: CallMediaType.audio,
    engine.TUICallMediaType.video: CallMediaType.video,
    engine.TUICallMediaType.none: null,
  };

  static final Map<engine.TUICallResultType, CallDirection> _kCallDirectionMap = {
    engine.TUICallResultType.unknown: CallDirection.unknown,
    engine.TUICallResultType.missed: CallDirection.missed,
    engine.TUICallResultType.incoming: CallDirection.incoming,
    engine.TUICallResultType.outgoing: CallDirection.outgoing,
  };

  static final Map<engine.CallEndReason, CallEndReason> _kCallEndReasonMap = {
    engine.CallEndReason.unknown: CallEndReason.unknown,
    engine.CallEndReason.hangup: CallEndReason.hangup,
    engine.CallEndReason.reject: CallEndReason.reject,
    engine.CallEndReason.noResponse: CallEndReason.noResponse,
    engine.CallEndReason.offline: CallEndReason.offline,
    engine.CallEndReason.lineBusy: CallEndReason.lineBusy,
    engine.CallEndReason.canceled: CallEndReason.canceled,
    engine.CallEndReason.otherDeviceAccepted: CallEndReason.otherDeviceAccepted,
    engine.CallEndReason.otherDeviceReject: CallEndReason.otherDeviceReject,
    engine.CallEndReason.endByServer: CallEndReason.endByServer,
  };

  static final Map<engine.TUINetworkQuality, NetworkQuality> _kTUINetworkQualityMap = {
    engine.TUINetworkQuality.qualityUnknown: NetworkQuality.unknown,
    engine.TUINetworkQuality.qualityExcellent: NetworkQuality.excellent,
    engine.TUINetworkQuality.qualityGood: NetworkQuality.good,
    engine.TUINetworkQuality.qualityPoor: NetworkQuality.poor,
    engine.TUINetworkQuality.qualityBad: NetworkQuality.bad,
    engine.TUINetworkQuality.qualityVeryBad: NetworkQuality.veryBad,
    engine.TUINetworkQuality.qualityDown: NetworkQuality.down,
  };

  static engine.TUICallMediaType toTUICallMediaType(CallMediaType? mediaType) {
    if (mediaType == null) {
      return engine.TUICallMediaType.none;
    }
    return _kTUICallMediaTypeMap[mediaType] ?? engine.TUICallMediaType.none;
  }

  static engine.TUICallParams toTUICallParams(CallParams? callParams) {
    engine.TUICallParams params = engine.TUICallParams();
    if (callParams != null) {
      params.roomId = callParams.roomId.isEmpty
          ? engine.TUIRoomId.strRoomId(_generateRoomId())
          : engine.TUIRoomId.strRoomId(callParams.roomId);
      params.chatGroupId = callParams.chatGroupId;
      params.userData = callParams.userData;
      params.timeout = callParams.timeout;

      final info = engine.TUIOfflinePushInfo();
      info.iOSPushType = engine.TUICallIOSOfflinePushType.VoIP;
      params.offlinePushInfo = info;
      return params;
    }
    params.roomId = engine.TUIRoomId.strRoomId(_generateRoomId());
    return params;
  }

  static CallMediaType? toCallMediaType(engine.TUICallMediaType type) {
    return _kCallMediaTypeMap[type];
  }

  static CallDirection toCallDirection(engine.TUICallResultType type) {
    return _kCallDirectionMap[type] ?? CallDirection.unknown;
  }

  static CallEndReason toCallEndReason(engine.CallEndReason reason) {
    return _kCallEndReasonMap[reason] ?? CallEndReason.unknown;
  }

  static NetworkQuality toNetworkQuality(engine.TUINetworkQuality quality) {
    return _kTUINetworkQualityMap[quality] ?? NetworkQuality.unknown;
  }

  static String _generateRoomId() {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    final random = Random.secure();
    final randomStr = List.generate(32, (index) => chars[random.nextInt(chars.length)]).join();
    return 'call_$randomStr';
  }
}