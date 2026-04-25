import 'package:flutter/foundation.dart';
import 'package:atomic_x_core/api/contact/group_setting_store.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/api/login/login_store.dart';
import 'package:atomic_x_core/api/message/message_list_store.dart';
import 'package:atomic_x_core/impl/message/message_action_store_impl.dart';

class MessageActionState {
  final List<GroupMember>? readMemberList;
  final List<GroupMember>? unReadMemberList;
  final List<UserProfile>? reactionUserList;
  final bool hasMoreReadMembers;
  final bool hasMoreUnReadMembers;
  final bool hasMoreReactionUsers;

  const MessageActionState({
    this.readMemberList,
    this.unReadMemberList,
    this.reactionUserList,
    this.hasMoreReadMembers = true,
    this.hasMoreUnReadMembers = true,
    this.hasMoreReactionUsers = true,
  });
}

abstract class MessageActionStore extends ChangeNotifier {
  static MessageActionStore create(MessageInfo message) {
    return MessageActionStoreImpl(message);
  }

  MessageActionState get messageActionState;

  Future<CompletionHandler> deleteMessage();

  Future<CompletionHandler> recallMessage();

  Future<CompletionHandler> pinMessage({required bool isPinned});

  Future<CompletionHandler> fetchMessageReadMembers({required int count});

  Future<CompletionHandler> fetchMessageUnreadMembers({required int count});

  Future<CompletionHandler> fetchMoreMessageMembers({required bool isRead});

  Future<CompletionHandler> addMessageReaction({required String reactionID});

  Future<CompletionHandler> removeMessageReaction({required String reactionID});

  Future<CompletionHandler> fetchMessageReactionUsers({required String reactionID, required int count});

  Future<CompletionHandler> fetchMoreMessageReactionUsers();

  Future<CompletionHandler> setMessageExtensions({required List<MessageExtension> extensions});

  Future<CompletionHandler> deleteMessageExtensions({List<String>? keys});

  Future<CompletionHandler> translateText(
      {required List<String> sourceTextList, String? sourceLanguage, required String targetLanguage});

  Future<CompletionHandler> convertVoiceToText({required String language});
}
