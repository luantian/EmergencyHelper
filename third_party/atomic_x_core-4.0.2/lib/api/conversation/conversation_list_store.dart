import 'package:atomic_x_core/api/contact/c2c_setting_store.dart';
import 'package:atomic_x_core/api/contact/group_setting_store.dart';
import 'package:atomic_x_core/api/message/message_list_store.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/conversation/conversation_list_store_impl.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

enum ConversationType {
  unknown,
  c2c,
  group,
}

enum GroupAtType {
  atMe,
  atAll,
  atAllAtMe,
}

class GroupAtInfo {
  final int msgSeq;
  final GroupAtType atType;

  GroupAtInfo({required this.msgSeq, required this.atType});
}

/// Custom extension marks need to satisfy bit shift values of 0x1 << n (32 <= n < 64, i.e., n must be >= 32 and < 64)
/// Example: ConversationMarkType(rawValue: 0x1 << 32) represents "custom xxx mark"
class ConversationMarkType {
  final int rawValue;

  const ConversationMarkType(this.rawValue);

  static const star = ConversationMarkType(0x1);
  static const unread = ConversationMarkType(0x1 << 1);
  static const fold = ConversationMarkType(0x1 << 2);
  static const hide = ConversationMarkType(0x1 << 3);

  bool get isEmpty => rawValue == 0;

  ConversationMarkType operator |(ConversationMarkType other) {
    return ConversationMarkType(rawValue | other.rawValue);
  }

  bool contains(ConversationMarkType other) {
    return (rawValue & other.rawValue) != 0;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConversationMarkType && other.rawValue == rawValue;
  }

  @override
  int get hashCode => rawValue.hashCode;
}

class ConversationInfo {
  final String conversationID;
  final ConversationType? type;
  final GroupType? groupType;
  final String? avatarURL;
  String? title;
  final MessageInfo? lastMessage;
  String? draft;
  final int? timestamp;
  int unreadCount;
  bool isPinned;
  final int orderKey;
  final ReceiveMessageOpt? receiveOption;
  List<GroupAtInfo>? groupAtInfoList;
  List<ConversationMarkType> markList;
  List<String> conversationGroupList;
  final V2TimConversation? rawConversation;

  ConversationInfo({
    required this.conversationID,
    this.type,
    this.groupType,
    this.avatarURL,
    this.title,
    this.lastMessage,
    this.draft,
    this.timestamp,
    this.unreadCount = 0,
    this.isPinned = false,
    this.orderKey = 0,
    this.receiveOption,
    this.groupAtInfoList,
    this.markList = const [],
    this.conversationGroupList = const [],
    this.rawConversation,
  });
}

class ConversationListFilter {
  ConversationType type;
  String? conversationGroup;
  ConversationMarkType? markType;
  bool? hasUnreadCount;
  bool? hasGroupAtInfo;

  ConversationListFilter({
    this.type = ConversationType.unknown,
    this.conversationGroup,
    this.markType,
    this.hasUnreadCount,
    this.hasGroupAtInfo,
  });
}

class ConversationFetchOption {
  int count;
  ConversationListFilter? filter;

  ConversationFetchOption({
    this.count = 100,
    this.filter,
  });
}

class ConversationListState {
  final List<ConversationInfo> conversationList;
  final bool hasMoreConversation;
  final int totalUnreadCount;

  const ConversationListState({
    required this.conversationList,
    this.hasMoreConversation = true,
    this.totalUnreadCount = 0,
  });
}

abstract class ConversationListStore extends ChangeNotifier {
  static ConversationListStore create() {
    return ConversationListStoreImpl();
  }

  ConversationListState get conversationListState;

  Future<CompletionHandler> fetchConversationList({required ConversationFetchOption option});

  Future<CompletionHandler> fetchMoreConversationList();

  Future<CompletionHandler> fetchConversationInfo({required String conversationID});

  Future<CompletionHandler> pinConversation({required String conversationID, required bool pin});

  Future<CompletionHandler> muteConversation({required String conversationID, required bool mute});

  Future<CompletionHandler> deleteConversation({required String conversationID});

  Future<CompletionHandler> setConversationDraft({required String conversationID, String? draft});

  Future<CompletionHandler> clearConversationMessages({required String conversationID});

  Future<CompletionHandler> clearConversationUnreadCount({required String conversationID});

  Future<CompletionHandler> getConversationTotalUnreadCount();

  Future<CompletionHandler> markConversation({
    required List<String> conversationIDList,
    required ConversationMarkType markType,
    required bool enable,
  });
}
