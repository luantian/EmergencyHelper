// Copyright (c) 2025 Tencent. All rights reserved.
// Module:   DeviceStore @ AtomicXCore
// Function: Device related interfaces, operating microphone, camera, etc.

import 'package:atomic_x_core/api/define.dart';
import 'package:flutter/foundation.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:tencent_rtc_sdk/trtc_cloud.dart';
import 'package:tencent_rtc_sdk/trtc_cloud_def.dart';

import '../../impl/common/log.dart';

part '../../impl/device/device_store_impl.dart';

/// Stores the native view ID of the local VideoView for use by openLocalCamera.
/// Set by CallParticipantView.onViewCreated when the local view is created.
int? localCallViewId;

/// Sets the local call view ID.
void setLocalCallViewId(int viewId) {
  localCallViewId = viewId;
}

/// Device type
///
/// This enum defines the available device types.
///
/// ### Response Scenarios
///
/// | Type | Value | Description |
/// |------|------|-----------|
/// | `microphone` | 0 | Microphone type |
/// | `camera` | 1 | Camera type |
/// | `screenShare` | 2 | Screen sharing type |
enum DeviceType {
  /// Microphone type.
  microphone(0),

  /// Camera type.
  camera(1),

  /// Screen sharing type.
  screenShare(2);

  final int value;

  const DeviceType(this.value);
}

/// Device related error codes
///
/// This enum defines the error codes that device operations may return.
///
/// ### Response Scenarios
///
/// | Error | Value | Description |
/// |------|------|-----------|
/// | `noError` | 0 | Operation successful |
/// | `noDeviceDetected` | 1 | No device detected |
/// | `noSystemPermission` | 2 | No system permission |
/// | `notSupportCapture` | 3 | Capture not supported |
/// | `occupiedError` | 4 | Device occupied |
/// | `unknownError` | 5 | Unknown error |
enum DeviceError {
  /// Operation successful.
  noError(0),

  /// No device detected.
  noDeviceDetected(1),

  /// No system permission.
  noSystemPermission(2),

  /// Capture not supported.
  notSupportCapture(3),

  /// Device occupied.
  occupiedError(4),

  /// Unknown error.
  unknownError(5);

  final int value;

  const DeviceError(this.value);
}

/// Device on/off status
///
/// This enum defines the on/off status of devices.
///
/// ### Response Scenarios
///
/// | Status | Value | Description |
/// |------|------|-----------|
/// | `off` | 0 | False |
/// | `on` | 1 | True |
enum DeviceStatus {
  /// Off.
  off(0),

  /// On.
  on(1);

  final int value;

  const DeviceStatus(this.value);
}

/// Audio route
///
/// This enum defines the audio output route location.
///
/// ### Response Scenarios
///
/// | Route | Value | Description |
/// |------|------|-----------|
/// | `speakerphone` | 0 | Speaker | suitable for playing music out loud |
/// | `earpiece` | 1 | Earpiece | suitable for private call scenarios |
enum AudioRoute {
  /// Speaker, using speaker to play (i.e., "hands-free"), located at the bottom of the phone, louder sound, suitable for playing music out loud.
  speakerphone(0),

  /// Earpiece, using earpiece to play, located at the top of the phone, quieter sound, suitable for private call scenarios.
  earpiece(1);

  final int value;

  const AudioRoute(this.value);
}

/// Video quality
///
/// This enum defines the video capture quality levels.
///
/// ### Response Scenarios
///
/// | Quality | Value | Description |
/// |-------|------|-----------|
/// | `quality360P` | 1 | 360P |
/// | `quality540P` | 2 | 540P |
/// | `quality720P` | 3 | 720P |
/// | `quality1080P` | 4 | 1080P |
enum VideoQuality {
  /// 360P.
  quality360P(1),

  /// 540P.
  quality540P(2),

  /// 720P.
  quality720P(3),

  /// 1080P.
  quality1080P(4);

  final int value;

  const VideoQuality(this.value);
}

/// Network quality
///
/// This enum defines the network quality levels.
///
/// ### Response Scenarios
///
/// | Quality | Value | Description |
/// |-------|------|-----------|
/// | `unknown` | 0 | Unknown network |
/// | `excellent` | 1 | Excellent |
/// | `good` | 2 | Good |
/// | `poor` | 3 | Poor |
/// | `bad` | 4 | Bad |
/// | `veryBad` | 5 | Very bad |
/// | `down` | 6 | Disconnected |
enum NetworkQuality {
  /// Unknown network.
  unknown(0),

  /// Excellent.
  excellent(1),

  /// Good.
  good(2),

  /// Poor.
  poor(3),

  /// Bad.
  bad(4),

  /// Very bad.
  veryBad(5),

  /// Disconnected.
  down(6);

  final int value;

  const NetworkQuality(this.value);
}

/// Camera mirror state
///
/// This enum defines the camera mirror modes.
///
/// ### Response Scenarios
///
/// | Mode | Value | Description |
/// |------|------|-----------|
/// | `auto` | 0 | Auto | front camera mirrored | rear camera not mirrored |
/// | `enable` | 1 | Both front and rear cameras mirrored |
/// | `disable` | 2 | Neither front nor rear camera mirrored |
enum MirrorType {
  /// Auto, front camera mirrored, rear camera not mirrored.
  auto(0),

  /// Both front and rear cameras mirrored.
  enable(1),

  /// Neither front nor rear camera mirrored.
  disable(2);

  final int value;

  const MirrorType(this.value);
}

/// Device focus
///
/// This enum defines the device focus owner scenarios.
///
/// ### Response Scenarios
///
/// | Scenario | Value | Description |
/// |--------|------|-----------|
/// | `call` | call | Voice call scenario |
/// | `live` | live | Live streaming scenario |
/// | `room` | room | Room scenario |
/// | `none` | none | Not set |
enum DeviceFocusOwner {
  call,

  live,

  room,

  none,
}

/// Network information
///
/// Data structure for network status information, containing user ID, network quality, packet loss rate and latency.
///
///
/// | Property | Type | Description |
/// |--------|------|-----------|
/// | [userID] | `String` | User unique ID |
/// | [quality] | [NetworkQuality] | Network quality |
/// | [upLoss] | `int` | Uplink packet loss rate, range [0, 100] |
/// | [downLoss] | `int` | Downlink packet loss rate, range [0, 100] |
/// | [delay] | `int` | {'Latency (unit': 'milliseconds)'} |
class NetworkInfo {
  /// User unique ID.
  final String userID;

  /// Network quality.
  final NetworkQuality quality;

  /// Uplink packet loss rate, range [0, 100].
  final int upLoss;

  /// Downlink packet loss rate, range [0, 100].
  final int downLoss;

  /// Latency (unit: milliseconds).
  final int delay;
  NetworkInfo({
    this.userID = '',
    this.quality = NetworkQuality.excellent,
    this.upLoss = 0,
    this.downLoss = 0,
    this.delay = 0,
  });
}

/// Device state
///
/// A comprehensive snapshot of device state, containing all device-related status information including microphone, camera, screen sharing and network.
///
/// > **Note**: Device state is automatically updated. Subscribe to [state] to receive real-time updates.
///
/// ### State Properties Overview
///
/// | Property | Type | Description |
/// |--------|------|-----------|
/// | [microphoneStatus] | `ValueListenable<DeviceStatus>` | Microphone status |
/// | [microphoneLastError] | `ValueListenable<DeviceError>` | Microphone error |
/// | [captureVolume] | `ValueListenable<int>` | Capture volume, range [0, 100] |
/// | [currentMicVolume] | `ValueListenable<int>` | Current user's actual output volume |
/// | [outputVolume] | `ValueListenable<int>` | Maximum output volume, range [0, 100] |
/// | [cameraStatus] | `ValueListenable<DeviceStatus>` | Camera status |
/// | [cameraLastError] | `ValueListenable<DeviceError>` | Camera error |
/// | [isFrontCamera] | `ValueListenable<bool>` | Whether it's front camera |
/// | [localMirrorType] | `ValueListenable<MirrorType>` | Mirror state |
/// | [localVideoQuality] | `ValueListenable<VideoQuality>` | Local video quality |
/// | [currentAudioRoute] | `ValueListenable<AudioRoute>` | Current audio route location |
/// | [screenStatus] | `ValueListenable<DeviceStatus>` | Screen sharing status |
/// | [networkInfo] | `ValueListenable<NetworkInfo>` | Network information |
abstract class DeviceState {
  /// Microphone status.
  ValueListenable<DeviceStatus> get microphoneStatus;

  /// Microphone error, used to extract error information when an error occurs.
  ValueListenable<DeviceError> get microphoneLastError;

  /// Capture volume, range [0, 100].
  ValueListenable<int> get captureVolume;

  /// Current user's actual output volume.
  ValueListenable<int> get currentMicVolume;

  /// Maximum output volume, range [0, 100].
  ValueListenable<int> get outputVolume;

  /// Camera status.
  ValueListenable<DeviceStatus> get cameraStatus;

  /// Camera error, used to extract error information when an error occurs.
  ValueListenable<DeviceError> get cameraLastError;

  /// Whether it's front camera.
  ValueListenable<bool> get isFrontCamera;

  /// Mirror state.
  ValueListenable<MirrorType> get localMirrorType;

  /// Local video quality.
  ValueListenable<VideoQuality> get localVideoQuality;

  /// Current audio route location.
  ValueListenable<AudioRoute> get currentAudioRoute;

  /// Screen sharing status.
  ValueListenable<DeviceStatus> get screenStatus;

  /// Network information.
  ValueListenable<NetworkInfo> get networkInfo;
}

/// Device related interfaces, operating microphone, camera, etc.
///
/// `DeviceStore` Device management class for handling host camera, microphone and other business.
/// `DeviceStore` provides a comprehensive set of APIs to manage audio and video devices, including microphone, camera and screen sharing features.
///
/// ### Key Features
///
/// - **Microphone Management**：Open/close microphone, set capture volume and output volume
/// - **Camera Management**：Open/close camera, switch front/rear camera, set mirror and video quality
/// - **Audio Route**：Switch between speaker and earpiece
/// - **Screen Sharing**：Start and stop screen sharing feature
/// - **Network Status**：Real-time monitoring of network quality information
/// - **Smart Cellular Switch**：Enable/disable smart cellular switch mode and receive recommendations
///
/// > **Important**: Use [DeviceStore.shared] singleton to get the `DeviceStore` instance. Do not attempt to initialize directly.
///
/// > **Note**: Device state updates are delivered through the [state] publisher. Subscribe to it to receive real-time updates about microphone, camera, network and other states.
///
/// ### Device Operations Overview
///
/// | Feature | Method | Description |
/// |-------|------|-----------|
/// | Microphone | [openLocalMicrophone]/[closeLocalMicrophone] | Open/close local microphone |
/// | Camera | [openLocalCamera]/[closeLocalCamera] | Open/close local camera |
/// | Audio Route | [setAudioRoute] | Switch speaker/earpiece |
/// | Screen Sharing | [startScreenShare]/[stopScreenShare] | Start/stop screen sharing |
/// | Volume Control | [setCaptureVolume]/[setOutputVolume] | Set capture/output volume |
///
/// ## Topics
///
/// ### Getting Instance
/// - [shared] : Singleton object
///
/// ### Observing State
/// - [state] : Reactive state containing microphone, camera, network and other device states
///
/// ### Event Listening
///
/// ### Smart Cellular Switch
///
/// ### Microphone Operations
///
/// ### Audio Route
///
/// ### Camera Operations
///
/// ### Screen Sharing
///
/// ### Reset
///
/// ## See Also
///
abstract class DeviceStore {
  /// Singleton object
  ///
  /// @param shared Singleton instance.
  static final DeviceStore _instance = _DeviceStoreImpl();

  static DeviceStore get shared => _instance;

  /// State
  DeviceState get state;

  /// Open local microphone
  ///
  /// - [completion] : Whether operation succeeded
  Future<CompletionHandler> openLocalMicrophone();

  /// Close local microphone
  void closeLocalMicrophone();

  /// Set capture volume
  ///
  /// - [volume] : Capture volume, range [0, 100]
  void setCaptureVolume(int volume);

  /// Set maximum output volume
  ///
  /// - [volume] : Maximum volume, range [0, 100]
  void setOutputVolume(int volume);

  /// Set audio route
  ///
  /// - [route] : Route location
  void setAudioRoute(AudioRoute route);

  /// Open local camera
  ///
  /// - [isFront] : Whether front camera
  /// - [completion] : Whether operation succeeded
  Future<CompletionHandler> openLocalCamera(bool isFront);

  /// Update camera status in DeviceStore without calling native SDK.
  /// Used when camera is opened/closed by the SDK directly (e.g. via
  /// TUICallEngine.openCamera from CallParticipantView).
  void updateCameraStatus(bool isOpen, {bool isFront = true});

  /// Close local camera
  void closeLocalCamera();

  /// Switch camera
  ///
  /// - [isFront] : Whether front camera
  void switchCamera(bool isFront);

  /// Switch mirror state
  ///
  /// - [mirrorType] : Mirror state
  void switchMirror(MirrorType mirrorType);

  /// Update video quality
  ///
  /// - [quality] : Video quality
  void updateVideoQuality(VideoQuality quality);

  /// Start screen sharing
  ///
  void startScreenShare();

  /// Stop screen capture
  void stopScreenShare();

  /// Reset to default state
  void reset();

  void setFocus(DeviceFocusOwner owner);
}
