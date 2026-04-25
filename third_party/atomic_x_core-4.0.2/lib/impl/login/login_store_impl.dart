import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/api/login/login_store.dart';
import 'package:atomic_x_core/impl/common/version.dart';
import 'package:flutter/cupertino.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimSDKListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_imsdk_bindings_generated.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class LoginStoreImpl extends LoginStore {
  static final LoginStoreImpl instance = LoginStoreImpl._internal();

  LoginStoreImpl._internal();

  String userId = '';
  String userSig = '';
  int _sdkAppID = 0;
  LoginStatus _loginStatus = LoginStatus.unlogin;
  UserProfile? _loginUserInfo;

  LoginState? _loginState;
  bool _needUpdate = true;

  V2TimSDKListener? _sdkListener;

  @override
  int get sdkAppID => _sdkAppID;

  @override
  LoginState get loginState {
    if (_needUpdate || _loginState == null) {
      _loginState = LoginState(
        loginStatus: _loginStatus,
        loginUserInfo: _loginUserInfo,
      );
      _needUpdate = false;
    }

    return _loginState!;
  }

  void _markNeedUpdate() {
    _needUpdate = true;
    notifyListeners();
  }

  @override
  Future<CompletionHandler> login({
    required int sdkAppID,
    required String userID,
    required String userSig,
  }) async {
    Version.printVersion();
    _initSDKListener();
    final handler = CompletionHandler();
    V2TimValueCallback<bool> initResult = await TencentImSDKPlugin.v2TIMManager.initSDK(
      sdkAppID: sdkAppID,
      loglevel: LogLevelEnum.V2TIM_LOG_INFO,
      listener: _sdkListener,
    );

    if (initResult.code != 0) {
      debugPrint('init failed: ${initResult.code}, ${initResult.desc}');
      handler.errorCode = initResult.code;
      handler.errorMessage = initResult.desc;
      return handler;
    }

    if (initResult.data != true) {
      debugPrint('init failed: result - ${initResult.data}');
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = 'Invalid sdkAppID: $sdkAppID. Please check if the sdkAppID is correct.';
      return handler;
    }

    _sdkAppID = sdkAppID;
    userId = userID;
    this.userSig = userSig;

    V2TimCallback loginResult = await TencentImSDKPlugin.v2TIMManager.login(
      userID: userID,
      userSig: userSig,
    );

    if (loginResult.code != 0) {
      debugPrint("login failed: ${loginResult.code}, ${loginResult.desc}");
      handler.errorCode = loginResult.code;
      handler.errorMessage = loginResult.desc;
      return handler;
    }

    _loginStatus = LoginStatus.logined;
    _markNeedUpdate();

    V2TimValueCallback<List<V2TimUserFullInfo>> userInfoResult =
    await TencentImSDKPlugin.v2TIMManager.getUsersInfo(userIDList: [userID]);
    if (userInfoResult.code == 0 && userInfoResult.data != null && userInfoResult.data!.isNotEmpty) {
      V2TimUserFullInfo info = userInfoResult.data!.first;
      _updateLoginUserInfo(info);
    } else {
      debugPrint("getUsersInfo failed: ${userInfoResult.code}, ${userInfoResult.desc}");
    }

    return handler;
  }

  void _updateLoginUserInfo(V2TimUserFullInfo info) {
    _loginUserInfo = UserProfile(
        userID: info.userID ?? '',
        nickname: info.nickName,
        avatarURL: info.faceUrl,
        selfSignature: info.selfSignature,
        gender: _convertToUIGender(info.gender),
        role: info.role,
        level: info.level,
        birthday: info.birthday,
        allowType: _convertToUIAllowType(info.allowType),
        customInfo: info.customInfo);
    _markNeedUpdate();
  }

  @override
  Future<CompletionHandler> logout() async {
    Version.printVersion();
    final handler = CompletionHandler();
    V2TimCallback result = await TencentImSDKPlugin.v2TIMManager.logout();
    if (result.code != 0) {
      debugPrint("logout failed: ${result.code}, ${result.desc}");
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _loginStatus = LoginStatus.unlogin;
    _loginUserInfo = null;
    _markNeedUpdate();

    return handler;
  }

  void _initSDKListener() {
    _sdkListener ??= V2TimSDKListener(
      onSelfInfoUpdated: (V2TimUserFullInfo info) {
        _updateLoginUserInfo(info);
      },
    );
  }

  @override
  Future<CompletionHandler> setSelfInfo({required UserProfile userInfo}) async {
    final handler = CompletionHandler();

    V2TimUserFullInfo info = V2TimUserFullInfo(
      userID: userInfo.userID,
      nickName: userInfo.nickname,
      faceUrl: userInfo.avatarURL,
      selfSignature: userInfo.selfSignature,
      gender: userInfo.gender?.index,
      role: userInfo.role,
      level: userInfo.level,
      birthday: userInfo.birthday,
      allowType: userInfo.allowType?.index,
      customInfo: userInfo.customInfo,
    );
    V2TimCallback result = await TencentImSDKPlugin.v2TIMManager.setSelfInfo(userFullInfo: info);
    if (result.code == 0) {
      var oldProfile = _loginUserInfo;
      _loginUserInfo = UserProfile(
          userID: info.userID ?? '',
          nickname: info.nickName ?? oldProfile?.nickname,
          avatarURL: info.faceUrl ?? oldProfile?.avatarURL,
          selfSignature: info.selfSignature ?? oldProfile?.selfSignature,
          gender: _convertToUIGender(info.gender) ?? oldProfile?.gender,
          role: info.role ?? oldProfile?.role,
          level: info.level ?? oldProfile?.level,
          birthday: info.birthday ?? oldProfile?.birthday,
          allowType: _convertToUIAllowType(info.allowType) ?? oldProfile?.allowType,
          customInfo: info.customInfo ?? oldProfile?.customInfo);
      _markNeedUpdate();
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  Gender? _convertToUIGender(int? gender) {
    if (gender == null) {
      return null;
    }

    return Gender.values[gender];
  }

  AllowType? _convertToUIAllowType(int? allowType) {
    if (allowType == null) {
      return null;
    }

    return AllowType.values[allowType];
  }
}
