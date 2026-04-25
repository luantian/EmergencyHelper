import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/conversation/conversation_group_store_impl.dart';
import 'package:flutter/foundation.dart';

class ConversationGroupState {
  final List<String> groupList;

  const ConversationGroupState({
    this.groupList = const [],
  });
}

abstract class ConversationGroupStore extends ChangeNotifier {
  static ConversationGroupStore create() {
    return ConversationGroupStoreImpl();
  }

  ConversationGroupState get conversationGroupState;

  Future<CompletionHandler> fetchGroupList();

  Future<CompletionHandler> createGroup({
    required String groupName,
    required List<String> conversationIDList,
  });

  Future<CompletionHandler> deleteGroup({required String groupName});

  Future<CompletionHandler> renameGroup({
    required String oldName,
    required String newName,
  });

  Future<CompletionHandler> addConversationsToGroup({
    required String groupName,
    required List<String> conversationIDList,
  });

  Future<CompletionHandler> deleteConversationsFromGroup({
    required String groupName,
    required List<String> conversationIDList,
  });
}
