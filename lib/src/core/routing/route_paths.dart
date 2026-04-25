class RoutePaths {
  const RoutePaths._();

  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String eventReport = '/event-report';
  static const String eventList = '/event-list';
  static const String eventDetail = '/event-detail/:eventId';
  static const String eventTransferPicker = '/event-transfer-picker/:eventId';
  static const String eventFeedback = '/event-feedback/:eventId';
  static const String eventTimeline = '/event-timeline/:eventId';
  static const String riskReport = '/risk-report';
  static const String riskList = '/risk-list';
  static const String riskDetail = '/risk-detail/:riskId';
  static const String riskTransferPicker = '/risk-transfer-picker/:riskId';
  static const String riskFeedback = '/risk-feedback/:riskId';
  static const String keyPoint = '/key-point';
  static const String weatherInfo = '/weather-info';
  static const String changePassword = '/change-password';
  static const String about = '/about';
  static const String messageDetail = '/message-detail/:messageId';
  static const String pushDebug = '/push-debug';
  static const String trtcCall = '/trtc-call';
  static const String trtcCallNew = '/trtc-call-new';

  static String eventDetailById(String eventId) =>
      '/event-detail/${Uri.encodeComponent(eventId)}';

  static String eventFeedbackById(String eventId) =>
      '/event-feedback/${Uri.encodeComponent(eventId)}';

  static String eventTransferPickerById(String eventId) =>
      '/event-transfer-picker/${Uri.encodeComponent(eventId)}';

  static String eventTimelineById(String eventId) =>
      '/event-timeline/${Uri.encodeComponent(eventId)}';

  static String riskDetailById(String riskId) =>
      '/risk-detail/${Uri.encodeComponent(riskId)}';

  static String riskFeedbackById(String riskId) =>
      '/risk-feedback/${Uri.encodeComponent(riskId)}';

  static String riskTransferPickerById(String riskId) =>
      '/risk-transfer-picker/${Uri.encodeComponent(riskId)}';

  static String messageDetailById(int messageId) =>
      '/message-detail/${Uri.encodeComponent(messageId.toString())}';
}
