import 'package:flutter/foundation.dart';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_rtc_sdk/trtc_cloud.dart';
import 'package:tencent_rtc_sdk/tx_audio_effect_manager.dart';

import '../../api/device/audio_effect_store.dart';
import '../common/log.dart';

class _AudioEffectStateImpl implements AudioEffectState {
  final ValueNotifier<AudioChangerType> audioChangerTypeValue = ValueNotifier(AudioChangerType.none);
  final ValueNotifier<AudioReverbType> audioReverbTypeValue = ValueNotifier(AudioReverbType.none);
  final ValueNotifier<bool> isEarMonitorOpenedValue = ValueNotifier(false);
  final ValueNotifier<int> earMonitorVolumeValue = ValueNotifier(100);

  @override
  ValueListenable<AudioChangerType> get audioChangerType => audioChangerTypeValue;

  @override
  ValueListenable<AudioReverbType> get audioReverbType => audioReverbTypeValue;

  @override
  ValueListenable<bool> get isEarMonitorOpened => isEarMonitorOpenedValue;

  @override
  ValueListenable<int> get earMonitorVolume => earMonitorVolumeValue;
}

class AudioEffectStoreImpl extends AudioEffectStore {
  static final AudioEffectStoreImpl shared = AudioEffectStoreImpl._();

  AudioEffectStoreImpl._();

  TRTCCloud? _trtcCloud;
  TXAudioEffectManager? _audioEffectManager;
  
  final Log _log = Log.getCommonLog('AudioEffectStoreImpl');

  Future<TXAudioEffectManager?> get _audioManager async {
    if (_audioEffectManager != null) return _audioEffectManager;

    _trtcCloud ??= await TRTCCloud.sharedInstance();
    _audioEffectManager ??= _trtcCloud?.getAudioEffectManager();
    return _audioEffectManager;
  }

  final _audioEffectState = _AudioEffectStateImpl();

  @override
  AudioEffectState get audioEffectState => _audioEffectState;

  @override
  void setAudioChangerType(AudioChangerType type) async {
    _log.info('API setAudioChangerType type:${type.value}');
    _audioEffectState.audioChangerTypeValue.value = type;
    (await _audioManager)?.setVoiceChangerType(TXVoiceChangerTypeExt.fromValue(type.value));
  }

  @override
  void setAudioReverbType(AudioReverbType type) async {
    _log.info('API setAudioReverbType type:${type.value}');
    _audioEffectState.audioReverbTypeValue.value = type;
    (await _audioManager)?.setVoiceReverbType(TXVoiceReverbTypeExt.fromValue(type.value));
  }

  @override
  void setVoiceEarMonitorEnable(bool enable) async {
    _log.info('API setVoiceEarMonitorEnable enable:$enable');
    _audioEffectState.isEarMonitorOpenedValue.value = enable;
    (await _audioManager)?.enableVoiceEarMonitor(enable);
  }

  @override
  void setVoiceEarMonitorVolume(int volume) async {
    _log.info('API setVoiceEarMonitorVolume volume:$volume');
    _audioEffectState.earMonitorVolumeValue.value = volume;
    (await _audioManager)?.setVoiceEarMonitorVolume(volume);
  }

  @override
  void reset() {
    setAudioChangerType(AudioChangerType.none);
    setAudioReverbType(AudioReverbType.none);
    setVoiceEarMonitorEnable(false);
    setVoiceEarMonitorVolume(100);
  }
}
