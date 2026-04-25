// Copyright (c) 2025 Tencent. All rights reserved.
// Module:   LoginStore @ AtomicXCore
// Function: Login related interfaces, managing user login, logout, user information settings and other operations.

import 'package:flutter/foundation.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/login/login_store_impl.dart';
import 'package:tencent_cloud_chat_sdk/enum/login_status.dart' as sdk;

/// Login status.
enum LoginStatus {
  /// Not logged in.
  unlogin(sdk.LoginStatus.V2TIM_STATUS_LOGOUT),

  /// Logged in.
  logined(sdk.LoginStatus.V2TIM_STATUS_LOGINED);

  final int value;
  const LoginStatus(this.value);

  static LoginStatus fromValue(int value) {
    switch (value) {
      case sdk.LoginStatus.V2TIM_STATUS_LOGINED:
        return LoginStatus.logined;
      case sdk.LoginStatus.V2TIM_STATUS_LOGOUT:
        return LoginStatus.unlogin;
      default:
        return LoginStatus.unlogin;
    }
  }
}

/// Friend verification type.
enum AllowType {
  /// Allow anyone.
  allowAny,

  /// Need confirmation.
  needConfirm,

  /// Deny anyone.
  denyAny,
}

/// Gender.
enum Gender {
  /// Unknown.
  unknown,

  /// Male.
  male,

  /// Female.
  female,
}

/// User profile
///
/// User profile data structure, containing user ID, nickname, avatar, gender and other personal information.
///
/// ### User Profile Properties Overview
///
/// | Property | Type | Description |
/// |--------|------|-----------|
/// | [userID] | `String` | User ID |
/// | [nickname] | `String?` | Nickname |
/// | [avatarURL] | `String?` | Avatar URL |
/// | [selfSignature] | `String?` | Personal signature |
/// | [gender] | `Gender?` | Gender |
/// | [role] | `int?` | Role |
/// | [level] | `int?` | Level |
/// | [birthday] | `int?` | Birthday |
/// | [allowType] | `AllowType?` | Friend verification type |
/// | [customInfo] | `Map<String, String>?` | Custom information |
class UserProfile {
  /// User ID.
  final String userID;

  /// Nickname.
  final String? nickname;

  /// Avatar URL.
  final String? avatarURL;

  /// Personal signature.
  final String? selfSignature;

  /// Gender.
  final Gender? gender;

  /// Role.
  final int? role;

  /// Level.
  final int? level;

  /// Birthday.
  final int? birthday;

  /// Friend verification type.
  final AllowType? allowType;

  /// Custom information.
  final Map<String, String>? customInfo;

  const UserProfile({
    this.userID = '',
    this.nickname,
    this.avatarURL,
    this.selfSignature,
    this.gender,
    this.role,
    this.level,
    this.birthday,
    this.allowType,
    this.customInfo,
  });
}

/// Login state
///
/// Login state data structure, containing current login status and logged-in user information.
///
/// ### State Properties Overview
///
/// | Property | Type | Description |
/// |--------|------|-----------|
/// | [loginStatus] | `LoginStatus` | Login status |
/// | [loginUserInfo] | `UserProfile?` | Logged-in user information |
class LoginState {
  /// Login status.
  final LoginStatus loginStatus;

  /// Logged-in user information.
  final UserProfile? loginUserInfo;

  const LoginState({
    this.loginStatus = LoginStatus.unlogin,
    this.loginUserInfo,
  });
}

/// Login event.

/// Login related interfaces, managing user login, logout, user information settings and other operations.
///
/// `LoginStore` Login management class for handling user login, logout and user information management business logic.
/// `LoginStore` provides a complete set of login management APIs, including user login, logout, and personal information settings.
/// Through this class, you can manage user login status and user profiles.
///
/// ### Key Features
///
/// - **User Login**：Supports login using SDK application ID, user ID and user signature
/// - **User Logout**：Supports user logout operation
/// - **Personal Information Settings**：Supports setting user nickname, avatar, gender and other personal information
///
/// > **Important**: Use [shared] singleton object to access the `LoginStore` instance.
///
/// > **Note**: Login status updates are delivered through [loginState] publisher. Subscribe to it to receive real-time updates about login status.
///
/// ### Login Operations Overview
///
/// | Operation | Method | Description |
/// |---------|------|-----------|
/// | Login | [login] | Login using SDK application ID user ID and user signature |
/// | Logout | [logout] | User logout |
/// | Set Info | [setSelfInfo] | Set user personal information |
///
/// ## Topics
///
/// ### Getting Instance
/// - [shared] : Singleton object
///
/// ### Observing State
/// - [state] : Login state
///
/// ### Observing Events
///
/// ### Login Operations
/// - [login] : Login
/// - [logout] : Logout
/// - [setSelfInfo] : Set personal information
///
/// ## See Also
///
/// - [LoginState]
/// - [UserProfile]
/// - [LoginStatus]
/// - [Gender]
/// - [AllowType]
abstract class LoginStore extends ChangeNotifier {
  /// SDK application ID
  int get sdkAppID;

  /// Login state
  LoginState get loginState;

  /// Singleton object
  static LoginStore get shared => LoginStoreImpl.instance;

  /// Login
  ///
  /// - [sdkAppID] : SDK application ID.
  /// - [userID] : User ID.
  /// - [userSig] : User signature.
  Future<CompletionHandler> login({
    required int sdkAppID,
    required String userID,
    required String userSig,
  });

  /// Logout
  ///
  Future<CompletionHandler> logout();

  /// Set personal information
  ///
  /// - [userProfile] : User profile.
  Future<CompletionHandler> setSelfInfo({required UserProfile userInfo});
}
