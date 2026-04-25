import 'package:flutter/foundation.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/contact/c2c_setting_store_impl.dart';

enum ReceiveMessageOpt {
  receive,
  notReceive,
  notNotify,
  notNotifyExceptMention,
  notReceiveExceptMention,
}

class C2CSettingState {
  final String avatarURL;
  final bool isNotDisturb;
  final bool isPinned;
  final String nickname;
  final String signature;
  final String remark;
  final bool isContact;
  final bool isInBlacklist;
  final ReceiveMessageOpt receiveMessageOpt;

  const C2CSettingState({
    this.avatarURL = '',
    this.isNotDisturb = false,
    this.isPinned = false,
    this.nickname = '',
    this.signature = '',
    this.remark = '',
    this.isContact = false,
    this.isInBlacklist = false,
    this.receiveMessageOpt = ReceiveMessageOpt.receive,
  });
}

abstract class C2CSettingStore extends ChangeNotifier {
  static C2CSettingStore create({required String userID}) {
    return C2CSettingStoreImpl(userID);
  }

  C2CSettingState get c2cSettingState;

  String get userID;

  Future<CompletionHandler> fetchUserInfo();

  Future<CompletionHandler> setUserRemark({required String remark});

  Future<CompletionHandler> addToBlacklist();

  Future<CompletionHandler> removeFromBlacklist();

  Future<CompletionHandler> checkBlacklistStatus();

  Future<CompletionHandler> deleteFriend();

  Future<CompletionHandler> setReceiveMessageOpt({required ReceiveMessageOpt opt});
}
