import 'package:flutter/foundation.dart';

import 'package:tencent_rtc_sdk/trtc_cloud.dart';
import 'package:tencent_rtc_sdk/trtc_cloud_def.dart';

import '../../api/device/base_beauty_store.dart';
import '../common/log.dart';
import '../live/room_engine_login.dart';

class _BaseBeautyStateImpl implements BaseBeautyState {
  final ValueNotifier<double> smoothLevelValue = ValueNotifier(0.0);

  final ValueNotifier<double> whitenessLevelValue = ValueNotifier(0.0);

  final ValueNotifier<double> ruddyLevelValue = ValueNotifier(0.0);

  @override
  ValueListenable<double> get smoothLevel => smoothLevelValue;

  @override
  ValueListenable<double> get whitenessLevel => whitenessLevelValue;

  @override
  ValueListenable<double> get ruddyLevel => ruddyLevelValue;
}

class BaseBeautyStoreImpl extends BaseBeautyStore {
  static final BaseBeautyStoreImpl shared = BaseBeautyStoreImpl._();

  BaseBeautyStoreImpl._() {
    RoomEngineLogin.shared.startAutoLogin();
  }

  late final _BaseBeautyStateImpl _baseBeautyState = _BaseBeautyStateImpl();
  // 1 = smooth style (磨皮+美白+红润), 0 = none (beauty disabled).
  final int _beautyStyle = 1;
  
  final Log _log = Log.getCommonLog('BaseBeautyStoreImpl');

  @override
  BaseBeautyState get baseBeautyState => _baseBeautyState;

  @override
  void setSmoothLevel(double smoothLevel) {
    _log.info('API setSmoothLevel smoothLevel:$smoothLevel');
    _baseBeautyState.smoothLevelValue.value = smoothLevel;
    _setBeautyStyle();
  }

  @override
  void setWhitenessLevel(double whitenessLevel) {
    _log.info('API setWhitenessLevel whitenessLevel:$whitenessLevel');
    _baseBeautyState.whitenessLevelValue.value = whitenessLevel;
    _setBeautyStyle();
  }

  @override
  void setRuddyLevel(double ruddyLevel) {
    _log.info('API setRuddyLevel ruddyLevel:$ruddyLevel');
    _baseBeautyState.ruddyLevelValue.value = ruddyLevel;
    _setBeautyStyle();
  }

  @override
  void reset() {
    setSmoothLevel(0);
    setWhitenessLevel(0);
    setRuddyLevel(0);
  }
}

extension on BaseBeautyStoreImpl {
  void _setBeautyStyle() async {
    TRTCCloud trtcCloud = await TRTCCloud.sharedInstance();
    trtcCloud.setBeautyStyle(TRTCBeautyStyleExt.fromValue(_beautyStyle), _baseBeautyState.smoothLevel.value.toInt(),
        _baseBeautyState.whitenessLevel.value.toInt(), _baseBeautyState.ruddyLevel.value.toInt());
  }
}
