import 'package:flutter/foundation.dart';

import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:atomic_x_core/api/login/login_store.dart';

import '../common/log.dart';
import '../login/login_store_impl.dart';

class _LoginParam {
  final int sdkAppId;
  final String userId;
  final String userSig;

  _LoginParam({
    this.sdkAppId = 0,
    this.userId = '',
    this.userSig = '',
  });
}

class RoomEngineLogin {
  static final RoomEngineLogin shared = RoomEngineLogin._();
  late final VoidCallback _onLoginStoreChangedListener = _handleLoginStoreChanged;
  final Log _logger = Log.getLiveLog('RoomEngineLogin');

  RoomEngineLogin._();

  _LoginParam? _loginParam;
  LoginStatus _lastLoginStatus = LoginStatus.unlogin;
  String _lastLoginUserId = '';

  void startAutoLogin() {
    LoginStore.shared.addListener(_onLoginStoreChangedListener);
    _handleLoginStoreChanged();
  }

  void invokeLogin(LoginStoreImpl loginStore) {
    if (_loginParam == null) {
      _login(loginStore.sdkAppID, loginStore.userId, loginStore.userSig);
    }
    if (_loginParam?.sdkAppId != loginStore.sdkAppID ||
        _loginParam?.userId != loginStore.userId ||
        _loginParam?.userSig != loginStore.userSig) {
      _login(loginStore.sdkAppID, loginStore.userId, loginStore.userSig);
    }
  }

  void stopAutoLogin() {
    LoginStore.shared.removeListener(_onLoginStoreChangedListener);
  }
}

extension on RoomEngineLogin {
  void _handleLoginStoreChanged() {
    final loginStore = LoginStore.shared as LoginStoreImpl;
    final loginStatus = loginStore.loginState.loginStatus;
    if (_lastLoginStatus != loginStatus) {
      switch (loginStatus) {
        case LoginStatus.logined:
          invokeLogin(loginStore);
          break;
        case LoginStatus.unlogin:
          if (_loginParam != null) {
            _logout();
          }
          break;
      }
      _lastLoginStatus = loginStatus;
    }

    final loginUserInfo = loginStore.loginState.loginUserInfo;
    if (_lastLoginUserId != loginUserInfo?.userID) {
      if (loginUserInfo?.userID == TUIRoomEngine.getSelfInfo().userId) {
        return;
      }
      invokeLogin(loginStore);
      _lastLoginUserId = loginUserInfo?.userID ?? '';
    }
  }

  void _login(int sdkAppId, String userId, String userSig) async {
    _logger.info('Login room engine');
    final result = await TUIRoomEngine.login(sdkAppId, userId, userSig);
    if (result.code != TUIError.success) {
      _logger.error('Login room engine failed [${result.code}]: ${result.message}');
      return;
    }
    _logger.info('Login room engine success');
    _loginParam = _LoginParam(sdkAppId: sdkAppId, userId: userId, userSig: userSig);
  }

  void _logout() async {
    _logger.info('Logout room engine');
    final result = await TUIRoomEngine.logout();
    if (result.code != TUIError.success) {
      _logger.error('Logout room engine failed [${result.code}]: ${result.message}');
      return;
    }
    _logger.info('Logout room engine success');
    _loginParam = null;
  }
}
