class AppConstants {
  const AppConstants._();

  static const String appName = '应急事件管理';
  static const String apiBaseUrl = 'http://47.104.73.59:93';
  static const String appBuildName = String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: '1.0.0',
  );
  static const String appBuildNumber = String.fromEnvironment(
    'FLUTTER_BUILD_NUMBER',
    defaultValue: '1',
  );
  static String get appVersionLabel => 'v$appBuildName';
  static const String splashLogoAsset = 'assets/images/logo.svg';

  static const String authLoginPath = '/admin-api/system/auth/login';
  static const String authRefreshTokenPath =
      '/admin-api/system/auth/refresh-token';
  static const String authLogoutPath = '/admin-api/system/auth/logout';
  static const String authPermissionInfoPath =
      '/admin-api/system/auth/get-permission-info';
  static const String authUserProfilePath =
      '/admin-api/system/user/profile/get';
  static const String authUserProfileUpdatePasswordPath =
      '/admin-api/system/user/profile/update-password';
  static const String dictDataSimpleListPath =
      '/admin-api/system/dict-data/simple-list';
  static const String deptListByTypePath =
      '/admin-api/system/dept/list-by-type';
  static const String deptListByTypeCompatPath =
      '/admin-api/system/deptlist-by-type';
  static const String deptSimpleListPath = '/admin-api/system/dept/simple-list';
  static const String userSimpleListPath = '/admin-api/system/user/simple-list';
  static const String userGetPath = '/admin-api/system/user/get';
  static const String notifyMessageUnreadCountPath =
      '/admin-api/system/notify-message/get-unread-count';
  static const String notifyMessageMyPagePath =
      '/admin-api/system/notify-message/my-page';
  static const String notifyMessageGetPath =
      '/admin-api/system/notify-message/get';
  static const String notifyMessageUpdateReadPath =
      '/admin-api/system/notify-message/update-read';
  static const String notifyMessageUpdateAllReadPath =
      '/admin-api/system/notify-message/update-all-read';
  static const String trtcUserSigPath = '/admin-api/api/trtc/user-sig';
  static const String trtcVerifySigPath = '/admin-api/api/trtc/verify-sig';
  static const String trtcCallRecordsPath = '/admin-api/api/trtc/call-records';
  static const String trtcCallRecordsPagePath =
      '/admin-api/api/trtc/call-records/page';
  static const String emergencyPlacePagePath =
      '/admin-api/emergency/place/page';
  static const String eventReportStatisticsPath =
      '/admin-api/event/report/statistics';
  static const String timPushAppKey = String.fromEnvironment(
    'TIM_PUSH_APPKEY',
    defaultValue:
        'cTLkjAEwdGW9G41pmVbLSKhiRoDYFQphuy1Vt1fIJkkwEXkr72yJItUKeEP0rjtV',
  );

  static const String defaultTenantId = '';

  static const String qWeatherHost = String.fromEnvironment(
    'QWEATHER_HOST',
    defaultValue: 'https://kn7p43kaq5.re.qweatherapi.com',
  );
  static const String qWeatherDefaultLocation = '101070101';
  static const String qWeatherKey = String.fromEnvironment(
    'QWEATHER_KEY',
    defaultValue: '507f4756f9474dd8a3ba8db0cc33ac2c',
  );
}
