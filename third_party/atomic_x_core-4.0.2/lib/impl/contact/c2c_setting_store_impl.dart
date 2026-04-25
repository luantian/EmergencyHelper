import 'dart:async';

import 'package:atomic_x_core/api/contact/c2c_setting_store.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/common/chat_util.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';
import 'package:atomic_x_core/impl/common/notification_center.dart';
import 'package:atomic_x_core/impl/conversation/conversation_list_store_impl.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimConversationListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/friend_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/friend_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_receive_message_opt_info.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class C2CSettingStoreImpl extends C2CSettingStore {
  final String _userID;
  String _nickname = '';
  String _avatar = '';
  String _signature = '';
  String _remark = '';
  bool _isNotDisturb = false;
  bool _isPinned = false;
  bool _isContact = false;
  bool _isInBlacklist = false;
  ReceiveMessageOpt _receiveMessageOpt = ReceiveMessageOpt.receive;

  C2CSettingState? _c2cSettingState;
  bool _needUpdate = true;

  late ConversationListStoreImpl conversationListStoreImpl;
  V2TimConversationListener? _conversationListener;
  late List<StreamSubscription> _eventSubscriptions;

  C2CSettingStoreImpl(this._userID) {
    conversationListStoreImpl = ConversationListStoreImpl();
    _addConversationListener();
    _addNotificationListeners();
  }

  @override
  void dispose() {
    conversationListStoreImpl.dispose();
    _removeConversationListener();
    _removeNotificationListeners();
    super.dispose();
  }

  @override
  String get userID => _userID;

  String get conversationID => "c2c_$userID";

  @override
  C2CSettingState get c2cSettingState {
    if (_needUpdate || _c2cSettingState == null) {
      _c2cSettingState = C2CSettingState(
        avatarURL: _avatar,
        isNotDisturb: _isNotDisturb,
        isPinned: _isPinned,
        nickname: _nickname,
        signature: _signature,
        remark: _remark,
        isContact: _isContact,
        isInBlacklist: _isInBlacklist,
        receiveMessageOpt: _receiveMessageOpt,
      );
      _needUpdate = false;
    }

    return _c2cSettingState!;
  }

  void _addConversationListener() {
    _conversationListener =
        V2TimConversationListener(onConversationChanged: (List<V2TimConversation> conversationList) {
      final existingIndex = conversationList.indexWhere((element) => element.conversationID == conversationID);
      if (existingIndex >= 0) {
        final conversation = conversationList[existingIndex];
        _isPinned = conversation.isPinned ?? false;
        _markNeedUpdate();
      }
    });

    TencentImSDKPlugin.v2TIMManager.getConversationManager().addConversationListener(listener: _conversationListener!);
  }

  void _removeConversationListener() {
    if (_conversationListener != null) {
      TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .removeConversationListener(listener: _conversationListener!);
      _conversationListener = null;
    }
  }

  void _addNotificationListeners() {
    _eventSubscriptions = [
      notificationCenter.addListener<ConversationMuteEventData>(
          ConversationNotificationNames.conversationMute, _handleConversationMute),
    ];
  }

  void _removeNotificationListeners() {
    for (var subscription in _eventSubscriptions) {
      subscription.cancel();
    }

    _eventSubscriptions.clear();
  }

  void _handleConversationMute(ConversationMuteEventData data) {
    if (!data.conversationID.contains(c2cConversationIDPrefix)) {
      return;
    }

    String userID = ChatUtil.getUserID(data.conversationID);
    if (userID != this.userID) {
      return;
    }

    _isNotDisturb = data.mute;
    _markNeedUpdate();
  }

  void _markNeedUpdate() {
    _needUpdate = true;
    notifyListeners();
  }

  @override
  Future<CompletionHandler> fetchUserInfo() async {
    return _fetchUserInfo();
  }

  @override
  Future<CompletionHandler> checkBlacklistStatus() async {
    return _checkBlacklistStatus();
  }

  @override
  Future<CompletionHandler> setUserRemark({required String remark}) async {
    return _setUserRemarkInternal(remark: remark);
  }

  @override
  Future<CompletionHandler> addToBlacklist() async {
    return _addToBlacklistInternal();
  }

  @override
  Future<CompletionHandler> removeFromBlacklist() async {
    return _removeFromBlacklistInternal();
  }

  @override
  Future<CompletionHandler> deleteFriend() async {
    return _deleteFriendInternal();
  }

  @override
  Future<CompletionHandler> setReceiveMessageOpt({required ReceiveMessageOpt opt}) async {
    return _setReceiveMessageOptInternal(opt: opt);
  }

  Future<CompletionHandler> _fetchUserInfo() async {
    DataReport.reportAtomicMetrics(AtomicMetrics.c2cSetting);

    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getUsersInfo(userIDList: [userID]);

    if (result.code == 0 && result.data != null && result.data!.isNotEmpty) {
      final userInfo = result.data!.first;
      _nickname = userInfo.nickName ?? "";
      _avatar = userInfo.faceUrl ?? "";
      _signature = userInfo.selfSignature ?? "";
      _markNeedUpdate();

      final receiveMessageOptResult =
          await TencentImSDKPlugin.v2TIMManager.getMessageManager().getC2CReceiveMessageOpt(userIDList: [userID]);
      if (receiveMessageOptResult.code == 0) {
        if (receiveMessageOptResult.data != null && receiveMessageOptResult.data!.isNotEmpty) {
          V2TimReceiveMessageOptInfo optInfo = receiveMessageOptResult.data!.first;
          _receiveMessageOpt = ChatUtil.convertToReceiveMessageOpt(optInfo.c2CReceiveMessageOpt ?? 0);
          _isNotDisturb = (_receiveMessageOpt == ReceiveMessageOpt.notNotify);
          _markNeedUpdate();
        }
      }

      CompletionHandler handler = await conversationListStoreImpl.fetchConversationInfo(conversationID: conversationID);
      if (handler.isSuccess) {
        final existingIndex = conversationListStoreImpl.conversationListState.conversationList
            .indexWhere((element) => element.conversationID == conversationID);
        if (existingIndex >= 0) {
          final conversationInfo = conversationListStoreImpl.conversationListState.conversationList[existingIndex];
          _isPinned = conversationInfo.isPinned;
          _markNeedUpdate();
        }
      }

      final friendResultList =
          await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().getFriendsInfo(userIDList: [userID]);
      if (friendResultList.code == 0 && friendResultList.data != null && friendResultList.data!.isNotEmpty) {
        final friendInfoResult = friendResultList.data!.first;
        if (friendInfoResult.relation == FriendType.V2TIM_FRIEND_TYPE_BOTH) {
          _isContact = true;
          _remark = friendInfoResult.friendInfo?.friendRemark ?? '';
        } else {
          _isContact = false;
          _remark = '';
        }
      } else {
        _isContact = false;
        _remark = '';

        handler.errorCode = friendResultList.code;
        handler.errorMessage = friendResultList.desc;
      }

      _markNeedUpdate();
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  Future<CompletionHandler> _checkBlacklistStatus() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().getBlackList();
    if (result.code == 0 && result.data != null) {
      _isInBlacklist = result.data!.any((blackUser) => blackUser.userID == userID);
      _markNeedUpdate();
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  Future<CompletionHandler> _setUserRemarkInternal({required String remark}) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().setFriendInfo(
          userID: userID,
          friendRemark: remark,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _remark = remark;
    _markNeedUpdate();

    return handler;
  }

  Future<CompletionHandler> _addToBlacklistInternal() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().addToBlackList(
          userIDList: [_userID],
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _isInBlacklist = true;
    _markNeedUpdate();

    return handler;
  }

  Future<CompletionHandler> _removeFromBlacklistInternal() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().deleteFromBlackList(
          userIDList: [_userID],
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _isInBlacklist = false;
    _markNeedUpdate();

    return handler;
  }

  Future<CompletionHandler> _deleteFriendInternal() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().deleteFromFriendList(
      userIDList: [_userID],
      deleteType: FriendTypeEnum.V2TIM_FRIEND_TYPE_BOTH,
    );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    // Post notification for friend deleted
    notificationCenter.post('FriendDeleted', {
      'userID': _userID,
      'conversationID': conversationID,
    });

    return handler;
  }

  Future<CompletionHandler> _setReceiveMessageOptInternal({required ReceiveMessageOpt opt}) async {
    final handler = CompletionHandler();

    final v2Opt = ChatUtil.convertToV2TIMReceiveMessageOpt(opt);
    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().setC2CReceiveMessageOpt(
      userIDList: [_userID],
      opt: v2Opt,
    );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _receiveMessageOpt = opt;
    _isNotDisturb = (opt == ReceiveMessageOpt.notNotify);
    _markNeedUpdate();

    return handler;
  }

}
