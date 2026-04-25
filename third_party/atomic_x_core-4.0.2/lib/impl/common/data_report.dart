import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

enum AtomicMetrics {
  messageList(1001),
  messageInput(1002),
  messageAction(1003),
  conversationList(1004),
  conversationGroup(1005),
  search(1006),
  contactList(1007),
  groupSetting(1008),
  c2cSetting(1009),
  call(1301),
  aiTranscriber(1401);

  final int value;
  const AtomicMetrics(this.value);
}

class DataReport {
  static void reportAtomicMetrics(AtomicMetrics componentType) {
    Map<String, dynamic> param = {
      'report_tuifeature_usage_uicomponent_type': componentType.value,
    };

    TencentImSDKPlugin.v2TIMManager.callExperimentalAPI(
      api: 'report_tuifeature_usage',
      param: param,
    );
  }
}
