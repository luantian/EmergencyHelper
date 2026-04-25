import 'package:atomic_x_core/api/contact/group_setting_store.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/api/login/login_store.dart';
import 'package:atomic_x_core/api/message/message_action_store.dart';
import 'package:atomic_x_core/api/message/message_list_store.dart';
import 'package:atomic_x_core/impl/common/chat_util.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';
import 'package:atomic_x_core/impl/common/notification_center.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:tencent_cloud_chat_sdk/enum/get_group_message_read_member_list_filter.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_extension.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_imsdk_bindings_generated.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

// Message action notification keys
class MessageActionNotifyKey {
  static const String messageDelete = 'message_delete';
  static const String messageRecall = 'message_recall';
  static const String messageEdit = 'message_edit';
  static const String messagePin = 'message_pin';
  static const String messageTranslate = 'message_translate';
  static const String voiceConvertToText = 'voice_convert_to_text';
}

// Message action notification data keys
class MessageActionNotifyDataKey {
  static const String messageID = 'messageID';
  static const String targetLanguage = 'targetLanguage';
  static const String translatedText = 'translatedText';
  static const String language = 'language';
  static const String convertedText = 'convertedText';
}

// Voice convert to text event data
class VoiceConvertToTextEventData {
  final String? messageID;
  final String? language;
  final String? convertedText;

  VoiceConvertToTextEventData({
    this.messageID,
    this.language,
    this.convertedText,
  });
}

// Message translate event data
class MessageTranslateEventData {
  final String? messageID;
  final String? targetLanguage;
  final Map<String, String>? translatedText;

  MessageTranslateEventData({
    this.messageID,
    this.targetLanguage,
    this.translatedText,
  });
}

class MessageActionStoreImpl extends MessageActionStore {
  List<GroupMember> _readMemberList = [];
  List<GroupMember> _unReadMemberList = [];
  List<UserProfile> _reactionUserList = [];
  bool _hasMoreReadMembers = true;
  bool _hasMoreUnReadMembers = true;
  bool _hasMoreReactionUsers = true;

  // Pagination state for read/unread members
  int _nextSeqOfReadMembers = 0;
  int _nextSeqOfUnReadMembers = 0;
  int _countOfReadMembers = 0;
  int _countOfUnReadMembers = 0;

  // Pagination state for reaction users
  String _currentReactionID = "";
  int _nextSeqOfReactionUsers = 0;
  int _countOfReactionUsers = 0;

  MessageActionState? _state;
  MessageInfo _message;
  bool _needUpdate = true;
  bool _hasReported = false;

  MessageActionStoreImpl(this._message);

  @override
  MessageActionState get messageActionState {
    if (_needUpdate || _state == null) {
      _state = MessageActionState(
        readMemberList: List.unmodifiable(_readMemberList),
        unReadMemberList: List.unmodifiable(_unReadMemberList),
        reactionUserList: List.unmodifiable(_reactionUserList),
        hasMoreReadMembers: _hasMoreReadMembers,
        hasMoreUnReadMembers: _hasMoreUnReadMembers,
        hasMoreReactionUsers: _hasMoreReactionUsers,
      );
      _needUpdate = false;
    }

    return _state!;
  }

  void _markNeedUpdate() {
    _needUpdate = true;
    notifyListeners();
  }

  @override
  Future<CompletionHandler> deleteMessage() async {
    return await _deleteMessageInternal();
  }

  @override
  Future<CompletionHandler> recallMessage() async {
    return await _recallMessageInternal();
  }

  @override
  Future<CompletionHandler> pinMessage({required bool isPinned}) async {
    return await _pinMessageInternal(isPinned: isPinned);
  }

  @override
  Future<CompletionHandler> fetchMessageReadMembers({int count = 100}) async {
    return await _fetchMessageReadMembersInternal(count: count);
  }

  @override
  Future<CompletionHandler> fetchMessageUnreadMembers({int count = 100}) async {
    return await _fetchMessageUnreadMembersInternal(count: count);
  }

  @override
  Future<CompletionHandler> fetchMoreMessageMembers({required bool isRead}) async {
    return await _fetchMoreMessageMembersInternal(isRead: isRead);
  }

  @override
  Future<CompletionHandler> addMessageReaction({required String reactionID}) async {
    return await _addMessageReactionInternal(reactionID: reactionID);
  }

  @override
  Future<CompletionHandler> removeMessageReaction({required String reactionID}) async {
    return await _removeMessageReactionInternal(reactionID: reactionID);
  }

  @override
  Future<CompletionHandler> fetchMessageReactionUsers({required String reactionID, int count = 100}) async {
    return await _fetchMessageReactionUsersInternal(reactionID: reactionID, count: count);
  }

  @override
  Future<CompletionHandler> fetchMoreMessageReactionUsers() async {
    return await _fetchMoreMessageReactionUsersInternal();
  }

  @override
  Future<CompletionHandler> setMessageExtensions({required List<MessageExtension> extensions}) async {
    return await _setMessageExtensionsInternal(extensions: extensions);
  }

  @override
  Future<CompletionHandler> deleteMessageExtensions({List<String>? keys}) async {
    return await _deleteMessageExtensionsInternal(keys: keys);
  }

  @override
  Future<CompletionHandler> translateText({
    required List<String> sourceTextList,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    return await _translateTextInternal(
        sourceTextList: sourceTextList, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage);
  }

  @override
  Future<CompletionHandler> convertVoiceToText({required String language}) async {
    return await _convertVoiceToTextInternal(language: language);
  }

  Future<CompletionHandler> _deleteMessageInternal() async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    if (_message.msgID == null || _message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    final msgID = _message.msgID!;
    final imMessage = _message.rawMessage!;
    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().deleteMessages(
      messageList: [imMessage],
    );

    if (result.code == 0) {
      notificationCenter.post(MessageActionNotifyKey.messageDelete, MessageDeleteEventData(messageIDList: [msgID]));
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  Future<CompletionHandler> _recallMessageInternal() async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    if (_message.msgID == null || _message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    final result =
        await TencentImSDKPlugin.v2TIMManager.getMessageManager().revokeMessage(message: _message.rawMessage);
    if (result.code == 0) {
      notificationCenter.post(MessageActionNotifyKey.messageRecall, MessageRevokeEventData(messageID: _message.msgID!));
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Pin message
  Future<CompletionHandler> _pinMessageInternal({required bool isPinned}) async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    final msgID = _message.msgID;
    if (msgID == null || _message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    final groupID = _message.groupID;
    if (groupID == null || groupID.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Only group messages can be pinned";
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().pinGroupMessage(
          groupID: groupID,
          message: _message.rawMessage!,
          isPinned: isPinned,
        );

    if (result.code == 0) {
      notificationCenter.post(
          MessageActionNotifyKey.messagePin,
          MessagePinEventData(
            messageID: msgID,
            groupID: groupID,
            isPinned: isPinned,
          ));
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Fetch message read members
  Future<CompletionHandler> _fetchMessageReadMembersInternal({required int count}) async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    if (count <= 0) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "count cannot be 0";
      return handler;
    }

    if (_message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    _countOfReadMembers = count;

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getGroupMessageReadMemberList(
          message: _message.rawMessage,
          filter: GetGroupMessageReadMemberListFilter.V2TIM_GROUP_MESSAGE_READ_MEMBERS_FILTER_READ,
          nextSeq: 0,
          count: count,
        );

    if (result.code == 0 && result.data != null) {
      _nextSeqOfReadMembers = result.data!.nextSeq;

      List<GroupMember> groupMembers = [];
      final members = result.data!.memberInfoList;
      for (final v2Member in members) {
        final member = ChatUtil.convertToGroupMember(v2Member);
        groupMembers.add(member);
      }

      _readMemberList = groupMembers;
      _hasMoreReadMembers = !result.data!.isFinished;
      _markNeedUpdate();
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Fetch message unread members
  Future<CompletionHandler> _fetchMessageUnreadMembersInternal({required int count}) async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    if (count <= 0) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "count cannot be 0";
      return handler;
    }

    if (_message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    _countOfUnReadMembers = count;

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getGroupMessageReadMemberList(
          message: _message.rawMessage,
          filter: GetGroupMessageReadMemberListFilter.V2TIM_GROUP_MESSAGE_READ_MEMBERS_FILTER_UNREAD,
          nextSeq: 0,
          count: count,
        );

    if (result.code == 0 && result.data != null) {
      _nextSeqOfUnReadMembers = result.data!.nextSeq;

      List<GroupMember> groupMembers = [];
      final members = result.data!.memberInfoList;
      for (final v2Member in members) {
        final member = ChatUtil.convertToGroupMember(v2Member);
        groupMembers.add(member);
      }

      _unReadMemberList = groupMembers;
      _hasMoreUnReadMembers = !result.data!.isFinished;
      _markNeedUpdate();
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Fetch more message members
  Future<CompletionHandler> _fetchMoreMessageMembersInternal({required bool isRead}) async {
    final handler = CompletionHandler();

    if (_message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    if (isRead) {
      if (!_hasMoreReadMembers) {
        return handler;
      }

      final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getGroupMessageReadMemberList(
            message: _message.rawMessage,
            filter: GetGroupMessageReadMemberListFilter.V2TIM_GROUP_MESSAGE_READ_MEMBERS_FILTER_READ,
            nextSeq: _nextSeqOfReadMembers,
            count: _countOfReadMembers,
          );

      if (result.code == 0 && result.data != null) {
        _nextSeqOfReadMembers = result.data!.nextSeq;

        final members = result.data!.memberInfoList;
        if (members.isNotEmpty) {
          List<GroupMember> groupMembers = [];
          for (final v2Member in members) {
            final member = ChatUtil.convertToGroupMember(v2Member);
            groupMembers.add(member);
          }
          _readMemberList.addAll(groupMembers);
        }

        _hasMoreReadMembers = !result.data!.isFinished;
        _markNeedUpdate();
      } else {
        handler.errorCode = result.code;
        handler.errorMessage = result.desc;
      }
    } else {
      if (!_hasMoreUnReadMembers) {
        return handler;
      }

      final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getGroupMessageReadMemberList(
            message: _message.rawMessage,
            filter: GetGroupMessageReadMemberListFilter.V2TIM_GROUP_MESSAGE_READ_MEMBERS_FILTER_UNREAD,
            nextSeq: _nextSeqOfUnReadMembers,
            count: _countOfUnReadMembers,
          );

      if (result.code == 0 && result.data != null) {
        _nextSeqOfUnReadMembers = result.data!.nextSeq;

        final members = result.data!.memberInfoList;
        if (members.isNotEmpty) {
          List<GroupMember> groupMembers = [];
          for (final v2Member in members) {
            final member = ChatUtil.convertToGroupMember(v2Member);
            groupMembers.add(member);
          }
          _unReadMemberList.addAll(groupMembers);
        }

        _hasMoreUnReadMembers = !result.data!.isFinished;
        _markNeedUpdate();
      } else {
        handler.errorCode = result.code;
        handler.errorMessage = result.desc;
      }
    }

    return handler;
  }

  // Add message reaction
  Future<CompletionHandler> _addMessageReactionInternal({required String reactionID}) async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    if (_message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().addMessageReaction(
          message: _message.rawMessage,
          reactionID: reactionID,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Remove message reaction
  Future<CompletionHandler> _removeMessageReactionInternal({required String reactionID}) async {
    final handler = CompletionHandler();

    if (_message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().removeMessageReaction(
          message: _message.rawMessage,
          reactionID: reactionID,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Fetch message reaction users
  Future<CompletionHandler> _fetchMessageReactionUsersInternal({
    required String reactionID,
    required int count,
  }) async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    if (reactionID.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "reactionID cannot be empty";
      return handler;
    }

    if (count <= 0) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "count cannot be 0";
      return handler;
    }

    if (_message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    _currentReactionID = reactionID;
    _countOfReactionUsers = count;

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getAllUserListOfMessageReaction(
          message: _message.rawMessage,
          reactionID: reactionID,
          nextSeq: 0,
          count: count,
        );

    if (result.code == 0 && result.data != null) {
      _nextSeqOfReactionUsers = result.data!.nextSeq;

      List<UserProfile> userProfiles = [];
      final userList = result.data!.userInfoList;
      for (final v2UserInfo in userList) {
        final userProfile = ChatUtil.convertToUserProfile(v2UserInfo);
        userProfiles.add(userProfile);
      }

      _reactionUserList = userProfiles;
      _hasMoreReactionUsers = !result.data!.isFinished;
      _markNeedUpdate();
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Fetch more message reaction users
  Future<CompletionHandler> _fetchMoreMessageReactionUsersInternal() async {
    final handler = CompletionHandler();

    if (!_hasMoreReactionUsers) {
      return handler;
    }

    if (_currentReactionID.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Please call fetchMessageReactionUsers first";
      return handler;
    }

    if (_message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getAllUserListOfMessageReaction(
          message: _message.rawMessage,
          reactionID: _currentReactionID,
          nextSeq: _nextSeqOfReactionUsers,
          count: _countOfReactionUsers,
        );

    if (result.code == 0 && result.data != null) {
      _nextSeqOfReactionUsers = result.data!.nextSeq;

      final userList = result.data!.userInfoList;
      if (userList.isNotEmpty) {
        List<UserProfile> userProfiles = [];
        for (final v2UserInfo in userList) {
          final userProfile = ChatUtil.convertToUserProfile(v2UserInfo);
          userProfiles.add(userProfile);
        }
        _reactionUserList.addAll(userProfiles);
      }

      _hasMoreReactionUsers = !result.data!.isFinished;
      _markNeedUpdate();
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Set message extensions
  Future<CompletionHandler> _setMessageExtensionsInternal({
    required List<MessageExtension> extensions,
  }) async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    if (extensions.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "extensions cannot be empty";
      return handler;
    }

    if (_message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    List<V2TimMessageExtension> v2Extensions = [];
    for (final ext in extensions) {
      final v2Ext = V2TimMessageExtension(
        extensionKey: ext.extensionKey ?? "",
        extensionValue: ext.extensionValue ?? "",
      );
      v2Extensions.add(v2Ext);
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().setMessageExtensions(
          message: _message.rawMessage,
          extensions: v2Extensions,
        );

    if (result.code == 0 && result.data != null) {
      // Check if any extension failed to set
      for (final extResult in result.data!) {
        if (extResult.resultCode != 0) {
          print(
              "[MessageActionStore] Failed to set extension: key=${extResult.extension?.extensionKey ?? ""}, code=${extResult.resultCode}, message=${extResult.resultInfo}");
        }
      }
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Delete message extensions
  Future<CompletionHandler> _deleteMessageExtensionsInternal({List<String>? keys}) async {
    final handler = CompletionHandler();

    if (_message.rawMessage == null || _message.msgID == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().deleteMessageExtensions(
          message: _message.rawMessage,
          keys: keys ?? [],
        );

    if (result.code == 0 && result.data != null) {
      // Check if any extension failed to delete
      for (final extResult in result.data!) {
        if (extResult.resultCode != 0) {
          print(
              "[MessageActionStore] Failed to delete extension: key=${extResult.extension?.extensionKey ?? ""}, code=${extResult.resultCode}, message=${extResult.resultInfo}");
        }
      }
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Translate text
  Future<CompletionHandler> _translateTextInternal({
    required List<String> sourceTextList,
    String? sourceLanguage,
    required String targetLanguage,
  }) async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    if (sourceTextList.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "sourceTextList cannot be empty";
      return handler;
    }

    if (targetLanguage.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "targetLanguage cannot be empty";
      return handler;
    }

    final msgID = _message.msgID;
    if (msgID == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message ID not found";
      return handler;
    }

    final rawMessage = _message.rawMessage;
    if (rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    // Check if already translated (cached in localCustomData)
    final localCustomData = rawMessage.localCustomData;
    if (localCustomData != null && localCustomData.isNotEmpty) {
      final json = ChatUtil.jsonData2Dictionary(localCustomData);
      if (json != null) {
        final cachedMap = json[LocalCustomDataKey.textTranslation] as Map<String, dynamic>?;
        final cachedLanguage = json[LocalCustomDataKey.textTranslationLanguage] as String?;
        if (cachedMap != null && cachedMap.isNotEmpty && cachedLanguage == targetLanguage) {
          // Convert to Map<String, String>
          final translatedTextMap = cachedMap.map((key, value) => MapEntry(key, value.toString()));
          notificationCenter.post(
              MessageActionNotifyKey.messageTranslate,
              MessageTranslateEventData(
                messageID: _message.msgID,
                targetLanguage: targetLanguage,
                translatedText: translatedTextMap,
              ));
          return handler;
        }
      }
    }

    // The SDK API only supports translating one text at a time
    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().translateText(
          texts: sourceTextList,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage ?? '',
        );

    if (result.code == 0 && result.data != null) {
      notificationCenter.post(
          MessageActionNotifyKey.messageTranslate,
          MessageTranslateEventData(
            messageID: _message.msgID,
            targetLanguage: targetLanguage,
            translatedText: result.data,
          ));
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Convert voice to text
  Future<CompletionHandler> _convertVoiceToTextInternal({required String language}) async {
    _reportAtomicMetricsIfNeeded();

    final handler = CompletionHandler();

    final msgID = _message.msgID;
    if (msgID == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message ID not found";
      return handler;
    }

    final rawMessage = _message.rawMessage;
    if (rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    if (_message.messageType != MessageType.sound) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "This is not a voice message";
      return handler;
    }

    // Check if already converted (cached in localCustomData)
    final localCustomData = rawMessage.localCustomData;
    if (localCustomData != null && localCustomData.isNotEmpty) {
      final json = ChatUtil.jsonData2Dictionary(localCustomData);
      if (json != null) {
        final cachedText = json[LocalCustomDataKey.voiceToText] as String?;
        if (cachedText != null && cachedText.isNotEmpty) {
          notificationCenter.post(
              MessageActionNotifyKey.voiceConvertToText,
              VoiceConvertToTextEventData(
                messageID: msgID,
                language: language,
                convertedText: cachedText,
              ));
          return handler;
        }
      }
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().convertVoiceToText(
          message: rawMessage,
          language: language,
        );

    if (result.code == 0 && result.data != null) {
      notificationCenter.post(
          MessageActionNotifyKey.voiceConvertToText,
          VoiceConvertToTextEventData(
            messageID: msgID,
            language: language,
            convertedText: result.data,
          ));
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  void _reportAtomicMetricsIfNeeded() {
    if (_hasReported) return;
    _hasReported = true;
    DataReport.reportAtomicMetrics(AtomicMetrics.messageAction);
  }
}
