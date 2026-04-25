import 'package:flutter/foundation.dart';
import 'package:atomic_x_core/api/message/message_list_store.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';

abstract class MessageInputStore extends ChangeNotifier {
  static MessageInputStore create({required String conversationID}) {
    return MessageInputStoreImpl(conversationID);
  }

  Future<CompletionHandler> sendMessage({required MessageInfo message});
}
