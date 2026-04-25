import 'dart:async';

import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/api/message/message_input_store.dart';
import 'package:atomic_x_core/api/message/message_list_store.dart';
import 'package:atomic_x_core/impl/common/chat_util.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';
import 'package:atomic_x_core/impl/common/notification_center.dart';
import 'package:atomic_x_core/impl/conversation/conversation_list_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_action_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';
import 'package:flutter/cupertino.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/image_types.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_extension.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_reaction_change_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_imsdk_bindings_generated.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

const String localExistKey = "isLocalExist";
const String filePathKey = "filePath";

// LocalCustomData keys for message
class LocalCustomDataKey {
  static const String textTranslation = 'text_translation';
  static const String textTranslationLanguage = 'text_translation_language';
  static const String voiceToText = 'voice_to_text';
}

// Message event data classes
class MessageSendEventData {
  final String conversationID;
  final dynamic message;
  final int? progress;
  final int? code;
  final String? desc;

  MessageSendEventData({
    required this.conversationID,
    this.message,
    this.progress,
    this.code,
    this.desc,
  });
}

class MessageDeleteEventData {
  final List<String> messageIDList;

  MessageDeleteEventData({required this.messageIDList});
}

class MessageRevokeEventData {
  final String messageID;

  MessageRevokeEventData({required this.messageID});
}

class MessageEditEventData {
  final dynamic message;

  MessageEditEventData({this.message});
}

class MessagePinEventData {
  final String messageID;
  final String groupID;
  final bool isPinned;

  MessagePinEventData({
    required this.messageID,
    required this.groupID,
    required this.isPinned,
  });
}

class MessageListStoreImpl extends MessageListStore {
  List<MessageInfo> _messageList = [];
  bool _hasMoreOlderMessage = false;
  bool _hasMoreNewerMessage = false;

  MessageListState? _messageListState;
  bool _needUpdate = true;
  bool _disposed = false;

  V2TimAdvancedMsgListener? _advancedMsgListener;

  final String _conversationID;
  final MessageListType messageListType;
  MessageFetchOption? _option;

  Set<String> _previousMessageIDs = {};

  // Message event stream controller
  final StreamController<MessageEvent> _messageEventController = StreamController<MessageEvent>.broadcast();

  MessageListStoreImpl({
    required String conversationID,
    required this.messageListType,
  }) : _conversationID = conversationID {
    _addMessageListener();
    _addNotificationListeners();
  }

  @override
  String get conversationID => _conversationID;

  @override
  Stream<MessageEvent> get messageEventStream => _messageEventController.stream;

  @override
  MessageListState get messageListState {
    if (_needUpdate || _messageListState == null) {
      _messageListState = MessageListState(
        messageList: List.unmodifiable(_messageList),
        hasMoreOlderMessage: _hasMoreOlderMessage,
        hasMoreNewerMessage: _hasMoreNewerMessage,
      );
      _needUpdate = false;
    }

    return _messageListState!;
  }

  void _markNeedUpdate() {
    if (_disposed) return;

    _needUpdate = true;
    notifyListeners();
  }

  late List<StreamSubscription> _eventSubscriptions;

  void _addNotificationListeners() {
    _eventSubscriptions = [
      notificationCenter.addListener<MessageSendEventData>(
          MessageSendNotifyKey.messageSendBegin, _handleMessageSendBegin),
      notificationCenter.addListener<MessageSendEventData>(
          MessageSendNotifyKey.messageSendSuccess, _handleMessageSendSuccess),
      notificationCenter.addListener<MessageSendEventData>(
          MessageSendNotifyKey.messageSendFailed, _handleMessageSendFailed),
      notificationCenter.addListener<MessageDeleteEventData>(
          MessageActionNotifyKey.messageDelete, _handleMessageDeleteEvent),
      notificationCenter.addListener<MessageRevokeEventData>(
          MessageActionNotifyKey.messageRecall, _handleMessageRevokeEvent),
      notificationCenter.addListener<MessageEditEventData>(MessageActionNotifyKey.messageEdit, _handleMessageEditEvent),
      notificationCenter.addListener<MessagePinEventData>(MessageActionNotifyKey.messagePin, _handleMessagePinEvent),
      notificationCenter.addListener<MessageListClearEventData>(
          ConversationNotificationNames.clearChatHistoryMessage, _handleMessageListClear),
      notificationCenter.addListener<MessageTranslateEventData>(
          MessageActionNotifyKey.messageTranslate, _handleTranslateMessage),
      notificationCenter.addListener<VoiceConvertToTextEventData>(
          MessageActionNotifyKey.voiceConvertToText, _handleVoiceConvertToText),
    ];
  }

  void _removeNotificationListeners() {
    for (var subscription in _eventSubscriptions) {
      subscription.cancel();
    }

    _eventSubscriptions.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _removeMessageListener();
    _removeNotificationListeners();
    _messageEventController.close();
    super.dispose();
  }

  /// State operation interface
  ///
  /// When messageListType is history, option cannot be null
  /// When messageListType is pinned, option is null
  /// When messageListType is replied, message in option cannot be null
  /// When messageListType is merged, message in option cannot be null
  @override
  Future<CompletionHandler> fetchMessageList({required MessageFetchOption option}) async {
    return _fetchMessagesInternal(option);
  }

  @override
  Future<CompletionHandler> fetchMoreMessageList({required MessageFetchDirection direction}) async {
    return _loadMoreMessagesInternal(direction);
  }

  @override
  Future<CompletionHandler> downloadMessageResource(
      {required MessageInfo message, required MessageMediaFileType resourceType}) async {
    return _downloadMessageResourceInternal(message, resourceType);
  }

  @override
  Future<CompletionHandler> sendMessageReadReceipts({required List<MessageInfo> messageList}) async {
    return _sendMessageReadReceiptsInternal(messageList);
  }

  @override
  Future<CompletionHandler> fetchMessageReactions(
      {required List<MessageInfo> messageList, required int maxUserCountPerReaction}) async {
    return _fetchMessageReactionsInternal(messageList, maxUserCountPerReaction);
  }

  @override
  Future<CompletionHandler> deleteMessages({required List<MessageInfo> messageList}) async {
    return _deleteMessagesInternal(messageList);
  }

  @override
  Future<CompletionHandler> forwardMessages({
    required List<MessageInfo> messageList,
    required MessageForwardOption forwardOption,
    required String conversationID,
  }) async {
    return _forwardMessagesInternal(messageList, forwardOption, conversationID);
  }

  void _addMessageListener() {
    _advancedMsgListener = V2TimAdvancedMsgListener(
      onRecvNewMessage: _onRecvNewMessage,
      onRecvMessageReadReceipts: _onRecvMessageReadReceipts,
      onRecvMessageRevokedWithInfo: _onRecvMessageRevoked,
      onRecvMessageModified: _onRecvMessageModified,
      onRecvMessageReactionsChanged: _onRecvMessageReactionsChanged,
      onRecvMessageExtensionsChanged: _onRecvMessageExtensionsChanged,
      onRecvMessageExtensionsDeleted: _onRecvMessageExtensionsDeleted,
      onGroupMessagePinned: _onGroupMessagePinned,
      onSendMessageProgress: _onSendMessageProgress,
    );

    TencentImSDKPlugin.v2TIMManager.getMessageManager().addAdvancedMsgListener(listener: _advancedMsgListener!);

    // Add listener for message list changes to auto-fetch receipts and extensions
    addListener(_handleMessageListChanged);
  }

  void _handleMessageListChanged() {
    final currentMessageIDs = _messageList.where((msg) => msg.msgID != null).map((msg) => msg.msgID!).toSet();
    final newMessageIDs = currentMessageIDs.difference(_previousMessageIDs);
    _previousMessageIDs = currentMessageIDs;

    if (newMessageIDs.isEmpty) return;

    final newMessages = _messageList.where((msg) => msg.msgID != null && newMessageIDs.contains(msg.msgID!)).toList();

    final messagesNeedReceipt = newMessages.where((msg) => msg.needReadReceipt && msg.rawMessage != null).toList();
    final messagesNeedExtension = newMessages.where((msg) => msg.supportExtension && msg.rawMessage != null).toList();

    if (messagesNeedReceipt.isNotEmpty) {
      _fetchMessageReadReceiptsInternal(messagesNeedReceipt);
    }
    if (messagesNeedExtension.isNotEmpty) {
      _fetchMessageExtensionsInternal(messagesNeedExtension);
    }
  }

  Future<void> _fetchMessageReadReceiptsInternal(List<MessageInfo> messageList) async {
    final v2Messages = messageList.map((msg) => msg.rawMessage!).toList();
    if (v2Messages.isEmpty) return;

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getMessageReadReceipts(
          messageList: v2Messages,
        );

    if (result.code == 0 && result.data != null) {
      for (final receipt in result.data!) {
        if (receipt.msgID == null) continue;

        final index = _messageList.indexWhere((msg) => msg.msgID == receipt.msgID);
        if (index != -1) {
          _messageList[index].receipt = ChatUtil.convertToMessageReceipt(receipt);
        }
      }
      _markNeedUpdate();
    }
  }

  Future<void> _fetchMessageExtensionsInternal(List<MessageInfo> messageList) async {
    for (final message in messageList) {
      if (message.rawMessage == null) continue;

      final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getMessageExtensions(
            message: message.rawMessage,
          );

      if (result.code == 0 && result.data != null) {
        final index = _messageList.indexWhere((msg) => msg.msgID == message.msgID);
        if (index != -1) {
          _messageList[index].extensionList = ChatUtil.convertToMessageExtensions(result.data);
          _markNeedUpdate();
        }
      }
    }
  }

  void _removeMessageListener() {
    if (_advancedMsgListener != null) {
      TencentImSDKPlugin.v2TIMManager.getMessageManager().removeAdvancedMsgListener(listener: _advancedMsgListener!);
      _advancedMsgListener = null;
    }
  }

  Future<CompletionHandler> _fetchMessagesInternal(MessageFetchOption option) async {
    DataReport.reportAtomicMetrics(AtomicMetrics.messageList);

    _option = option;

    // Clear cache message data
    _messageList.clear();
    _hasMoreOlderMessage = false;
    _hasMoreNewerMessage = false;

    switch (messageListType) {
      case MessageListType.history:
        return await _fetchHistoryMessageList(option);
      case MessageListType.merged:
        return await _fetchMergedMessagesInternal(option);
      default:
        return CompletionHandler();
    }
  }

  Future<CompletionHandler> _fetchHistoryMessageList(MessageFetchOption option) async {
    if (option.direction == MessageFetchDirection.older || option.direction == MessageFetchDirection.newer) {
      return await _fetchOneSideMessageList(option, isFetchMore: false);
    } else {
      return await _fetchTwoSideMessageList(option);
    }
  }

  Future<CompletionHandler> _loadMoreMessagesInternal(MessageFetchDirection direction) async {
    final handler = CompletionHandler();
    if (_option == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Please call fetchMessages first";
      return handler;
    }

    if (direction == MessageFetchDirection.older) {
      if (!_hasMoreOlderMessage) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "No more older message";
        return handler;
      }

      MessageInfo? firstMessage;
      for (var msg in _messageList) {
        if (msg.rawMessage != null) {
          firstMessage = msg;
          break;
        }
      }

      if (firstMessage == null) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "No more older message";
        return handler;
      }

      _option!.message = firstMessage;
    } else if (direction == MessageFetchDirection.newer) {
      if (!_hasMoreNewerMessage) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "No more newer message";
        return handler;
      }

      MessageInfo? lastMessage;
      for (var i = _messageList.length - 1; i >= 0; i--) {
        if (_messageList[i].rawMessage != null) {
          lastMessage = _messageList[i];
          break;
        }
      }

      if (lastMessage == null) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "No more newer message";
        return handler;
      }

      _option!.message = lastMessage;
    }

    _option!.direction = direction;

    return await _fetchOneSideMessageList(_option!, isFetchMore: true);
  }

  Future<CompletionHandler> _fetchOneSideMessageList(MessageFetchOption option, {required bool isFetchMore}) async {
    final handler = CompletionHandler();

    final messageTypeList = _getMessageTypeList(option);
    HistoryMsgGetTypeEnum getType = HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG;
    if (option.direction == MessageFetchDirection.newer) {
      getType = messageTypeList.isNotEmpty
          ? HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG
          : HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG;
    } else if (option.direction == MessageFetchDirection.older) {
      getType = messageTypeList.isNotEmpty
          ? HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG
          : HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getHistoryMessageList(
          count: option.pageCount,
          getType: getType,
          userID: ChatUtil.getUserID(_conversationID),
          groupID: ChatUtil.getGroupID(_conversationID),
          lastMsg: option.message?.rawMessage,
          messageTypeList: messageTypeList,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    List<MessageInfo> fetchedMessages = [];
    if (option.direction == MessageFetchDirection.older) {
      List<V2TimMessage> reversedMessages = result.data != null ? List.from(result.data!.reversed) : [];
      fetchedMessages = _convertToUIMessageList(reversedMessages);
      _messageList.insertAll(0, fetchedMessages);
      _hasMoreOlderMessage = (result.data?.length ?? 0) >= option.pageCount;
    } else {
      fetchedMessages = result.data != null ? _convertToUIMessageList(result.data!) : [];
      _messageList.addAll(fetchedMessages);
      _hasMoreNewerMessage = (result.data?.length ?? 0) >= option.pageCount;
    }

    _markNeedUpdate();

    // Emit event based on isFetchMore
    if (fetchedMessages.isNotEmpty) {
      if (isFetchMore) {
        _messageEventController.add(FetchMoreMessagesEvent(messageList: fetchedMessages));
      } else {
        _messageEventController.add(FetchMessagesEvent(
          messageList: fetchedMessages,
          direction: option.direction,
        ));
      }
    }

    return handler;
  }

  Future<CompletionHandler> _fetchTwoSideMessageList(MessageFetchOption option) async {
    final handler = CompletionHandler();

    final messageTypeList = _getMessageTypeList(option);
    List<V2TimMessage> olderMsgs = [];
    List<V2TimMessage> newerMsgs = [];

    final olderResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getHistoryMessageList(
          count: option.pageCount,
          getType: messageTypeList.isNotEmpty
              ? HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG
              : HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
          userID: ChatUtil.getUserID(_conversationID),
          groupID: ChatUtil.getGroupID(_conversationID),
          lastMsg: option.message?.rawMessage,
          lastMsgSeq: option.messageSeq,
          messageTypeList: messageTypeList,
        );

    if (olderResult.code == 0 && olderResult.data != null) {
      olderMsgs = List.from(olderResult.data!.reversed);
      _hasMoreOlderMessage = olderResult.data!.length >= option.pageCount;
    }

    final newerResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getHistoryMessageList(
          count: option.pageCount,
          getType: messageTypeList.isNotEmpty
              ? HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG
              : HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
          userID: ChatUtil.getUserID(_conversationID),
          groupID: ChatUtil.getGroupID(_conversationID),
          lastMsg: option.message?.rawMessage,
          lastMsgSeq: option.messageSeq,
          messageTypeList: messageTypeList,
        );

    if (newerResult.code == 0 && newerResult.data != null) {
      newerMsgs = newerResult.data!;
      _hasMoreNewerMessage = newerResult.data!.length >= option.pageCount;
    }

    List<V2TimMessage> results = [];
    results.addAll(olderMsgs);

    if (option.message?.rawMessage != null) {
      results.add(option.message!.rawMessage!);
    } else if (results.isNotEmpty) {
      results.removeLast();
    }

    results.addAll(newerMsgs);

    _messageList = _convertToUIMessageList(results);

    _markNeedUpdate();

    // Emit fetch messages event
    if (_messageList.isNotEmpty) {
      _messageEventController.add(FetchMessagesEvent(
        messageList: _messageList,
        direction: MessageFetchDirection.both,
      ));
    }

    return handler;
  }

  List<int> _getMessageTypeList(MessageFetchOption option) {
    final List<int> messageTypeList = [];
    if (option.filterType.contains(MessageFilterType.image)) {
      messageTypeList.add(MessageElemType.V2TIM_ELEM_TYPE_IMAGE);
    }
    if (option.filterType.contains(MessageFilterType.video)) {
      messageTypeList.add(MessageElemType.V2TIM_ELEM_TYPE_VIDEO);
    }
    return messageTypeList;
  }

  Future<CompletionHandler> _downloadMessageResourceInternal(
      MessageInfo message, MessageMediaFileType resourceType) async {
    final handler = CompletionHandler();

    if (message.rawMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found for operation";
      return handler;
    }

    final int messageIndex = _messageList.indexWhere((msg) => msg.msgID == message.msgID);
    if (messageIndex == -1) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Message not found in message list";
      return handler;
    }

    switch (resourceType) {
      case MessageMediaFileType.thumbImage:
        return await _downloadThumbImage(message, messageIndex);
      case MessageMediaFileType.largeImage:
        return await _downloadLargeImage(message, messageIndex);
      case MessageMediaFileType.originalImage:
        return await _downloadOriginalImage(message, messageIndex);
      case MessageMediaFileType.videoSnapshot:
        return await _downloadVideoSnapshot(message, messageIndex);
      case MessageMediaFileType.video:
        return await _downloadVideo(message, messageIndex);
      case MessageMediaFileType.sound:
        return await _downloadSound(message, messageIndex);
      case MessageMediaFileType.file:
        return await _downloadFile(message, messageIndex);
      default:
        return handler;
    }
  }

  /// 下载缩略图
  Future<CompletionHandler> _downloadThumbImage(MessageInfo message, int messageIndex) async {
    final handler = CompletionHandler();

    if (message.messageType != MessageType.image) {
      return handler;
    }

    final imMessage = message.rawMessage!;
    String? uuid;

    for (final image in imMessage.imageElem?.imageList ?? []) {
      if (image.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB) {
        uuid = image.uuid;
        break;
      }
    }

    if (uuid == null || uuid.isEmpty) {
      uuid = message.msgID ?? "";
    }

    final thumbImageResult =
        ChatUtil.getActualMediaPath(MessageType.image, message.messageBody?.thumbImagePath, uuid, "thumb_");
    final thumbImagePath = thumbImageResult[filePathKey];
    bool isLocalExist = thumbImageResult[localExistKey];

    if (isLocalExist) {
      var messageCopy = _messageList[messageIndex];
      var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
      messageBodyCopy.thumbImagePath = thumbImagePath;
      messageCopy.messageBody = messageBodyCopy;
      messageCopy.progress = 100;
      _messageList[messageIndex] = messageCopy;
      _markNeedUpdate();
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().downloadMessage(
          message: imMessage,
          messageType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
          imageType: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB,
          isSnapshot: false,
          downloadPath: thumbImagePath,
        );

    if (result.code != 0) {
      var messageCopy = _messageList[messageIndex];
      messageCopy.progress = 0;
      _messageList[messageIndex] = messageCopy;
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    var messageCopy = _messageList[messageIndex];
    var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
    messageBodyCopy.thumbImagePath = thumbImagePath;
    messageCopy.messageBody = messageBodyCopy;
    messageCopy.progress = 100;
    _messageList[messageIndex] = messageCopy;
    _markNeedUpdate();

    return handler;
  }

  /// 下载大图
  Future<CompletionHandler> _downloadLargeImage(MessageInfo message, int messageIndex) async {
    final handler = CompletionHandler();

    if (message.messageType != MessageType.image) {
      return handler;
    }

    final imMessage = message.rawMessage!;
    String? uuid;

    for (final image in imMessage.imageElem?.imageList ?? []) {
      if (image.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_LARGE) {
        uuid = image.uuid;
        break;
      }
    }

    if (uuid == null || uuid.isEmpty) {
      uuid = message.msgID ?? "";
    }

    final largeImageResult =
        ChatUtil.getActualMediaPath(MessageType.image, message.messageBody?.largeImagePath, uuid, "large_");
    final largeImagePath = largeImageResult[filePathKey];
    bool isLocalExist = largeImageResult[localExistKey];

    if (isLocalExist) {
      var messageCopy = _messageList[messageIndex];
      var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
      messageBodyCopy.largeImagePath = largeImagePath;
      messageCopy.messageBody = messageBodyCopy;
      messageCopy.progress = 100;
      _messageList[messageIndex] = messageCopy;
      _markNeedUpdate();
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().downloadMessage(
          message: imMessage,
          messageType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
          imageType: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_LARGE,
          isSnapshot: false,
          downloadPath: largeImagePath,
        );

    if (result.code != 0) {
      var messageCopy = _messageList[messageIndex];
      messageCopy.progress = 0;
      _messageList[messageIndex] = messageCopy;
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    var messageCopy = _messageList[messageIndex];
    var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
    messageBodyCopy.largeImagePath = largeImagePath;
    messageCopy.messageBody = messageBodyCopy;
    messageCopy.progress = 100;
    _messageList[messageIndex] = messageCopy;
    _markNeedUpdate();

    return handler;
  }

  /// 下载原图
  Future<CompletionHandler> _downloadOriginalImage(MessageInfo message, int messageIndex) async {
    final handler = CompletionHandler();

    if (message.messageType != MessageType.image) {
      return handler;
    }

    final imMessage = message.rawMessage!;
    String? uuid;

    for (final image in imMessage.imageElem?.imageList ?? []) {
      if (image.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN) {
        uuid = image.uuid;
        break;
      }
    }

    if (uuid == null || uuid.isEmpty) {
      uuid = message.msgID ?? "";
    }

    final originalImageResult =
        ChatUtil.getActualMediaPath(MessageType.image, message.messageBody?.originalImagePath, uuid, "origin_");
    final originalImagePath = originalImageResult[filePathKey];
    bool isLocalExist = originalImageResult[localExistKey];

    if (isLocalExist) {
      var messageCopy = _messageList[messageIndex];
      var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
      messageBodyCopy.originalImagePath = originalImagePath;
      messageCopy.messageBody = messageBodyCopy;
      messageCopy.progress = 100;
      _messageList[messageIndex] = messageCopy;
      _markNeedUpdate();
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().downloadMessage(
          message: imMessage,
          messageType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
          imageType: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN,
          isSnapshot: false,
          downloadPath: originalImagePath,
        );

    if (result.code != 0) {
      var messageCopy = _messageList[messageIndex];
      messageCopy.progress = 0;
      _messageList[messageIndex] = messageCopy;
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    var messageCopy = _messageList[messageIndex];
    var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
    messageBodyCopy.originalImagePath = originalImagePath;
    messageCopy.messageBody = messageBodyCopy;
    messageCopy.progress = 100;
    _messageList[messageIndex] = messageCopy;
    _markNeedUpdate();

    return handler;
  }

  /// 下载视频缩略图
  Future<CompletionHandler> _downloadVideoSnapshot(MessageInfo message, int messageIndex) async {
    final handler = CompletionHandler();

    if (message.messageType != MessageType.video) {
      return handler;
    }

    final imMessage = message.rawMessage!;
    var uuid = imMessage.videoElem?.snapshotUUID;

    if (uuid == null || uuid.isEmpty) {
      uuid = message.msgID ?? "";
    }

    final videoSnapshotResult =
        ChatUtil.getActualMediaPath(MessageType.video, message.messageBody?.videoSnapshotPath, uuid, null);
    final videoSnapshotPath = videoSnapshotResult[filePathKey];
    bool isLocalExist = videoSnapshotResult[localExistKey];

    if (isLocalExist) {
      var messageCopy = _messageList[messageIndex];
      var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
      messageBodyCopy.videoSnapshotPath = videoSnapshotPath;
      messageCopy.messageBody = messageBodyCopy;
      messageCopy.progress = 100;
      _messageList[messageIndex] = messageCopy;
      _markNeedUpdate();
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().downloadMessage(
          message: imMessage,
          messageType: MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
          imageType: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN,
          isSnapshot: true,
          downloadPath: videoSnapshotPath,
        );

    if (result.code != 0) {
      var messageCopy = _messageList[messageIndex];
      messageCopy.progress = 0;
      _messageList[messageIndex] = messageCopy;
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    var messageCopy = _messageList[messageIndex];
    var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
    messageBodyCopy.videoSnapshotPath = videoSnapshotPath;
    messageCopy.messageBody = messageBodyCopy;
    messageCopy.progress = 100;
    _messageList[messageIndex] = messageCopy;
    _markNeedUpdate();

    return handler;
  }

  /// 下载视频
  Future<CompletionHandler> _downloadVideo(MessageInfo message, int messageIndex) async {
    final handler = CompletionHandler();

    if (message.messageType != MessageType.video) {
      return handler;
    }

    final imMessage = message.rawMessage!;
    var uuid = imMessage.videoElem?.UUID;
    final extension = imMessage.videoElem?.videoType;

    if (uuid == null || uuid.isEmpty) {
      uuid = message.msgID ?? "";
    }

    final videoPathResult =
        ChatUtil.getActualMediaPath(MessageType.video, message.messageBody?.videoPath, uuid, extension);
    final videoPath = videoPathResult[filePathKey];
    bool isLocalExist = videoPathResult[localExistKey];

    if (isLocalExist) {
      var messageCopy = _messageList[messageIndex];
      var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
      messageBodyCopy.videoPath = videoPath;
      messageCopy.messageBody = messageBodyCopy;
      messageCopy.progress = 100;
      _messageList[messageIndex] = messageCopy;
      _markNeedUpdate();
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().downloadMessage(
          message: imMessage,
          messageType: MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
          imageType: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN,
          isSnapshot: false,
          downloadPath: videoPath,
        );

    if (result.code != 0) {
      var messageCopy = _messageList[messageIndex];
      messageCopy.progress = 0;
      _messageList[messageIndex] = messageCopy;
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    var messageCopy = _messageList[messageIndex];
    var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
    messageBodyCopy.videoPath = videoPath;
    messageCopy.messageBody = messageBodyCopy;
    messageCopy.progress = 100;
    _messageList[messageIndex] = messageCopy;
    _markNeedUpdate();

    return handler;
  }

  /// 下载音频
  Future<CompletionHandler> _downloadSound(MessageInfo message, int messageIndex) async {
    final handler = CompletionHandler();

    if (message.messageType != MessageType.sound) {
      return handler;
    }

    final imMessage = message.rawMessage!;
    var uuid = imMessage.soundElem?.UUID;

    if (uuid == null || uuid.isEmpty) {
      uuid = message.msgID ?? "";
    }

    final soundPathResult = ChatUtil.getActualMediaPath(
      MessageType.sound,
      message.messageBody?.soundPath,
      uuid,
      null,
    );
    final soundPath = soundPathResult[filePathKey];
    bool isLocalExist = soundPathResult[localExistKey];

    if (isLocalExist) {
      var messageCopy = _messageList[messageIndex];
      var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
      messageBodyCopy.soundPath = soundPath;
      messageCopy.messageBody = messageBodyCopy;
      messageCopy.progress = 100;
      _messageList[messageIndex] = messageCopy;
      _markNeedUpdate();
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().downloadMessage(
          message: imMessage,
          messageType: MessageElemType.V2TIM_ELEM_TYPE_SOUND,
          imageType: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN,
          isSnapshot: false,
          downloadPath: soundPath,
        );

    if (result.code != 0) {
      var messageCopy = _messageList[messageIndex];
      messageCopy.progress = 0;
      _messageList[messageIndex] = messageCopy;
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    var messageCopy = _messageList[messageIndex];
    var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
    messageBodyCopy.soundPath = soundPath;
    messageCopy.messageBody = messageBodyCopy;
    messageCopy.progress = 100;
    _messageList[messageIndex] = messageCopy;
    _markNeedUpdate();

    return handler;
  }

  /// 下载文件
  Future<CompletionHandler> _downloadFile(MessageInfo message, int messageIndex) async {
    final handler = CompletionHandler();

    if (message.messageType != MessageType.file) {
      return handler;
    }

    final imMessage = message.rawMessage!;
    var uuid = imMessage.fileElem?.UUID;

    if (uuid == null || uuid.isEmpty) {
      uuid = message.msgID ?? "";
    }

    final filePathResult = ChatUtil.getActualMediaPath(
      MessageType.file,
      message.messageBody?.filePath,
      uuid,
      null,
    );
    final filePath = filePathResult[filePathKey];
    bool isLocalExist = filePathResult[localExistKey];

    if (isLocalExist) {
      var messageCopy = _messageList[messageIndex];
      var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
      messageBodyCopy.filePath = filePath;
      messageCopy.messageBody = messageBodyCopy;
      messageCopy.progress = 100;
      _messageList[messageIndex] = messageCopy;
      _markNeedUpdate();
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().downloadMessage(
          message: imMessage,
          messageType: MessageElemType.V2TIM_ELEM_TYPE_FILE,
          imageType: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN,
          isSnapshot: false,
          downloadPath: filePath,
        );

    if (result.code != 0) {
      var messageCopy = _messageList[messageIndex];
      messageCopy.progress = 0;
      _messageList[messageIndex] = messageCopy;
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    var messageCopy = _messageList[messageIndex];
    var messageBodyCopy = messageCopy.messageBody ?? MessageBody();
    messageBodyCopy.filePath = filePath;
    messageCopy.messageBody = messageBodyCopy;
    messageCopy.progress = 100;
    _messageList[messageIndex] = messageCopy;
    _markNeedUpdate();

    return handler;
  }

  List<MessageInfo> _convertToUIMessageList(List<V2TimMessage> imMessages) {
    List<MessageInfo> messageList = [];
    for (V2TimMessage imMessage in imMessages) {
      MessageInfo message = ChatUtil.convertToUIMessage(imMessage);
      messageList.add(message);
    }
    return messageList;
  }

  void onMessageSendBegin(String conversationID, MessageInfo message) {
    if (messageListType != MessageListType.history) return;

    if (conversationID != this._conversationID) return;

    final isResend = (message.status != MessageStatus.initStatus);
    if (isResend) {
      final index = _messageList.indexWhere((msg) => msg.msgID == message.msgID);
      if (index != -1) {
        _messageList.removeAt(index);
      }
    }

    _messageList.add(message);
    _markNeedUpdate();

    // Emit send message event
    _messageEventController.add(SendMessageEvent(message: message));
  }

  void onMessageSendSuccess(String conversationID, MessageInfo message) {
    if (messageListType != MessageListType.history) return;

    if (conversationID != this._conversationID) return;

    final index = _messageList.indexWhere((msg) => msg.msgID == message.msgID);
    if (index != -1) {
      if (_messageList[index].rawMessage != null) {
        final updateMessage = ChatUtil.convertToUIMessage(_messageList[index].rawMessage!);
        _messageList[index] = updateMessage;
        _markNeedUpdate();
      }
    }
  }

  void onMessageSendFailed(String conversationID, MessageInfo message, int code, String desc) {
    if (messageListType != MessageListType.history) return;

    if (conversationID != this._conversationID) return;

    final index = _messageList.indexWhere((msg) => msg.msgID == message.msgID);
    if (index != -1) {
      var messageCopy = _messageList[index];
      messageCopy.status = MessageStatus.sendFail;
      _messageList[index] = messageCopy;
      _markNeedUpdate();
    }
  }

  void _handleMessageDelete(List<String> messageIDList) {
    if (messageListType != MessageListType.history) return;
    if (messageIDList.isEmpty) return;

    final messageIDSet = messageIDList.toSet();
    final deletedMessages = _messageList.where((message) {
      if (message.msgID == null) return false;
      return messageIDSet.contains(message.msgID);
    }).toList();

    _messageList.removeWhere((message) {
      if (message.msgID == null) return false;
      return messageIDSet.contains(message.msgID);
    });

    _markNeedUpdate();

    // Emit delete messages event
    if (deletedMessages.isNotEmpty) {
      _messageEventController.add(DeleteMessagesEvent(messageList: deletedMessages));
    }
  }

  void _handleMessageRevoke(String msgID) {
    if (messageListType != MessageListType.history) return;

    final index = _messageList.indexWhere((message) => message.msgID == msgID);
    if (index != -1) {
      if (_messageList[index].status != MessageStatus.recalled) {
        _messageList[index].status = MessageStatus.recalled;
        _messageList[index].messageType = MessageType.system;
        MessageBody messageBody = MessageBody();
        messageBody.systemMessage = [
          ChatUtil.convertToSystemInfoFromRecall(_messageList[index].rawMessage!, null, null)
        ];
        _messageList[index].messageBody = messageBody;

        _markNeedUpdate();
      }
    }
  }

  void _handleMessageEdit(V2TimMessage receivedMessage) {
    if (messageListType != MessageListType.history) return;

    final index = _messageList.indexWhere((message) => message.msgID == receivedMessage.msgID);
    if (index != -1) {
      _messageList[index] = ChatUtil.convertToUIMessage(receivedMessage);
      _markNeedUpdate();
    }
  }

  /// ****** V2TIMAdvancedMsgListener ******
  void _onRecvNewMessage(V2TimMessage message) {
    if (messageListType != MessageListType.history) return;

    if (message.groupID != null && message.groupID!.isNotEmpty) {
      if (message.groupID != ChatUtil.getGroupID(_conversationID)) {
        return;
      }
    }

    if (message.userID != null && message.userID!.isNotEmpty) {
      if (message.userID != ChatUtil.getUserID(_conversationID)) {
        return;
      }
    }

    final messageInfo = ChatUtil.convertToUIMessage(message);

    _messageList.add(messageInfo);
    _markNeedUpdate();

    // Emit recv message event
    _messageEventController.add(RecvMessageEvent(message: messageInfo));
  }

  void _onRecvMessageReadReceipts(List<V2TimMessageReceipt> receiptList) {
    if (messageListType != MessageListType.history) return;

    for (final receipt in receiptList) {
      if (receipt.msgID == null) continue;

      final index = _messageList.indexWhere((msg) => msg.msgID == receipt.msgID);
      if (index != -1) {
        _messageList[index].receipt = ChatUtil.convertToMessageReceipt(receipt);
        _markNeedUpdate();
      }
    }
  }

  void _onRecvMessageRevoked(String msgID, V2TimUserFullInfo operateUser, String reason) {
    if (messageListType != MessageListType.history) return;

    final index = _messageList.indexWhere((message) => message.msgID == msgID);
    if (index != -1) {
      if (_messageList[index].status != MessageStatus.recalled) {
        _messageList[index].status = MessageStatus.recalled;
        _messageList[index].messageType = MessageType.system;
        MessageBody messageBody = MessageBody();
        messageBody.systemMessage = [
          ChatUtil.convertToSystemInfoFromRecall(_messageList[index].rawMessage!, operateUser, reason)
        ];
        _messageList[index].messageBody = messageBody;

        _markNeedUpdate();
      }
    }
  }

  void _onRecvMessageModified(V2TimMessage receivedMessage) {
    if (messageListType != MessageListType.history) return;

    if (receivedMessage.groupID != null && receivedMessage.groupID!.isNotEmpty) {
      if (receivedMessage.groupID != ChatUtil.getGroupID(_conversationID)) {
        return;
      }
    }

    if (receivedMessage.userID != null && receivedMessage.userID!.isNotEmpty) {
      if (receivedMessage.userID != ChatUtil.getUserID(_conversationID)) {
        return;
      }
    }

    final index = _messageList.indexWhere((message) => message.msgID == receivedMessage.msgID);
    if (index != -1) {
      _messageList[index] = ChatUtil.convertToUIMessage(receivedMessage);
      _markNeedUpdate();
    }
  }

  void _onRecvMessageReactionsChanged(List<V2TIMMessageReactionChangeInfo> changeInfos) {
    if (messageListType != MessageListType.history) return;

    final ids = changeInfos.map((info) => info.messageID).whereType<String>().toSet();
    if (ids.isEmpty) return;

    bool hasUpdate = false;
    for (int i = 0; i < _messageList.length; i++) {
      final message = _messageList[i];
      if (ids.contains(message.msgID)) {
        final changeInfo = changeInfos.cast<V2TIMMessageReactionChangeInfo?>().firstWhere(
              (info) => info?.messageID == message.msgID,
              orElse: () => null,
            );
        if (changeInfo != null) {
          final changedReactions = ChatUtil.convertToMessageReactions(changeInfo.reactionList);
          final mergedReactions = _mergeReactions(message.reactionList, changedReactions);
          _messageList[i].reactionList = mergedReactions;
          hasUpdate = true;
        }
      }
    }

    if (hasUpdate) {
      _markNeedUpdate();
    }
  }

  List<MessageReaction> _mergeReactions(
    List<MessageReaction> existingReactions,
    List<MessageReaction> changedReactions,
  ) {
    final reactionMap = <String, MessageReaction>{};
    for (final reaction in existingReactions) {
      reactionMap[reaction.reactionID] = reaction;
    }

    for (final changedReaction in changedReactions) {
      if (changedReaction.totalUserCount == 0) {
        reactionMap.remove(changedReaction.reactionID);
      } else {
        reactionMap[changedReaction.reactionID] = changedReaction;
      }
    }

    return reactionMap.values.toList();
  }

  void _onRecvMessageExtensionsChanged(String msgID, List<V2TimMessageExtension> extensions) {
    if (messageListType != MessageListType.history) return;

    final index = _messageList.indexWhere((msg) => msg.msgID == msgID);
    if (index != -1) {
      _messageList[index].extensionList = ChatUtil.convertToMessageExtensions(extensions);
      _markNeedUpdate();
    }
  }

  void _onRecvMessageExtensionsDeleted(String msgID, List<String> extensionKeys) {
    if (messageListType != MessageListType.history) return;

    final index = _messageList.indexWhere((msg) => msg.msgID == msgID);
    if (index != -1) {
      _messageList[index]
          .extensionList
          .removeWhere((ext) => ext.extensionKey != null && extensionKeys.contains(ext.extensionKey!));
      _markNeedUpdate();
    }
  }

  void _onGroupMessagePinned(String groupID, V2TimMessage message, bool isPinned, V2TimGroupMemberInfo opUser) {
    if (messageListType != MessageListType.history) return;

    final currentGroupID = ChatUtil.getGroupID(_conversationID);
    if (currentGroupID != groupID) return;

    final index = _messageList.indexWhere((msg) => msg.msgID == message.msgID);
    if (index != -1) {
      _messageList[index].isPinned = isPinned;
      _markNeedUpdate();
    }
  }

  void _onSendMessageProgress(V2TimMessage receivedMessage, int progress) {
    if (messageListType != MessageListType.history) {
      debugPrint("messageListType is not history");
      return;
    }

    final index = _messageList.indexWhere((message) => message.msgID == receivedMessage.msgID);
    if (index != -1) {
      _messageList[index].progress = progress;
      _markNeedUpdate();
    }
  }

  void _handleMessageSendBegin(MessageSendEventData data) {
    if (data.conversationID != _conversationID) return;
    if (messageListType != MessageListType.history) return;

    final message = data.message as MessageInfo?;
    if (message != null) {
      onMessageSendBegin(data.conversationID, message);
    }
  }

  void _handleMessageSendSuccess(MessageSendEventData data) {
    if (data.conversationID != _conversationID) return;
    if (messageListType != MessageListType.history) return;

    final message = data.message as MessageInfo?;
    if (message != null) {
      onMessageSendSuccess(data.conversationID, message);
    }
  }

  void _handleMessageSendFailed(MessageSendEventData data) {
    if (data.conversationID != _conversationID) return;
    if (messageListType != MessageListType.history) return;

    final message = data.message as MessageInfo?;
    if (message != null) {
      onMessageSendFailed(data.conversationID, message, data.code ?? -1, data.desc ?? "");
    }
  }

  void _handleMessageDeleteEvent(MessageDeleteEventData data) {
    _handleMessageDelete(data.messageIDList);
  }

  void _handleMessageRevokeEvent(MessageRevokeEventData data) {
    _handleMessageRevoke(data.messageID);
  }

  void _handleMessageEditEvent(MessageEditEventData data) {
    if (data.message != null) {
      _handleMessageEdit(data.message as V2TimMessage);
    }
  }

  void _handleMessagePinEvent(MessagePinEventData data) {
    if (messageListType != MessageListType.history) return;

    final currentGroupID = ChatUtil.getGroupID(_conversationID);
    if (currentGroupID != data.groupID) return;

    final index = _messageList.indexWhere((msg) => msg.msgID == data.messageID);
    if (index != -1) {
      _messageList[index].isPinned = data.isPinned;
      _markNeedUpdate();
    }
  }

  void _handleMessageListClear(MessageListClearEventData data) {
    if (data.conversationID != _conversationID) return;
    _messageList.clear();
    _markNeedUpdate();
  }

  void _handleTranslateMessage(MessageTranslateEventData data) {
    if (messageListType != MessageListType.history) return;

    final messageID = data.messageID;
    final targetLanguage = data.targetLanguage;
    final translatedTextMap = data.translatedText;

    if (messageID == null || targetLanguage == null || translatedTextMap == null) return;

    final index = _messageList.indexWhere((msg) => msg.msgID == messageID);
    if (index == -1) return;

    final message = _messageList[index];
    final messageBody = message.messageBody;
    if (messageBody == null) return;

    // Update translatedText in messageBody
    messageBody.translatedText ??= {};
    messageBody.translatedText!.addAll(translatedTextMap);
    messageBody.translateLanguage = targetLanguage;

    // Save translated text map to localCustomData for persistence
    final rawMessage = message.rawMessage;
    if (rawMessage != null) {
      Map<String, dynamic> dict = {};
      final localCustomData = rawMessage.localCustomData;
      if (localCustomData != null && localCustomData.isNotEmpty) {
        final existingDict = ChatUtil.jsonData2Dictionary(localCustomData);
        if (existingDict != null) {
          dict = existingDict;
        }
      }
      dict[LocalCustomDataKey.textTranslation] = translatedTextMap;
      dict[LocalCustomDataKey.textTranslationLanguage] = targetLanguage;
      final newLocalCustomData = ChatUtil.dictionary2JsonData(dict);
      rawMessage.localCustomData = newLocalCustomData;
      // Flutter needs to call an API to save the data.
      TencentImSDKPlugin.v2TIMManager.getMessageManager().setLocalCustomData(
        message: rawMessage,
        localCustomData: newLocalCustomData ?? '',
      );
    }

    _markNeedUpdate();
  }

  void _handleVoiceConvertToText(VoiceConvertToTextEventData data) {
    if (messageListType != MessageListType.history) return;

    final messageID = data.messageID;
    final language = data.language;
    final convertedText = data.convertedText;

    if (messageID == null || convertedText == null) return;

    final index = _messageList.indexWhere((msg) => msg.msgID == messageID);
    if (index == -1) return;

    final message = _messageList[index];
    var messageBody = message.messageBody ?? MessageBody();
    messageBody.asrLanguage = language;
    messageBody.asrText = convertedText;
    message.messageBody = messageBody;

    // Save asrText to localCustomData for persistence
    final rawMessage = message.rawMessage;
    if (rawMessage != null && convertedText.isNotEmpty) {
      Map<String, dynamic> dict = {};
      final localCustomData = rawMessage.localCustomData;
      if (localCustomData != null && localCustomData.isNotEmpty) {
        final existingDict = ChatUtil.jsonData2Dictionary(localCustomData);
        if (existingDict != null) {
          dict = existingDict;
        }
      }
      dict[LocalCustomDataKey.voiceToText] = convertedText;
      final newLocalCustomData = ChatUtil.dictionary2JsonData(dict);
      rawMessage.localCustomData = newLocalCustomData;
      // Flutter needs to call an API to save the data.
      TencentImSDKPlugin.v2TIMManager.getMessageManager().setLocalCustomData(
        message: rawMessage,
        localCustomData: newLocalCustomData ?? '',
      );
    }

    _markNeedUpdate();
  }

  // Send message read receipts
  Future<CompletionHandler> _sendMessageReadReceiptsInternal(List<MessageInfo> messageList) async {
    final handler = CompletionHandler();

    if (messageList.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "messageList cannot be empty";
      return handler;
    }

    final v2MessageList = <V2TimMessage>[];
    for (final messageInfo in messageList) {
      if (messageInfo.rawMessage == null) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "MessageInfo.rawMessage cannot be null";
        return handler;
      }
      v2MessageList.add(messageInfo.rawMessage!);
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().sendMessageReadReceipts(
          messageList: v2MessageList,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Fetch message reactions
  Future<CompletionHandler> _fetchMessageReactionsInternal(
      List<MessageInfo> messageList, int maxUserCountPerReaction) async {
    final handler = CompletionHandler();

    if (messageList.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "messageList cannot be empty";
      return handler;
    }

    final v2MessageList = <V2TimMessage>[];
    for (final messageInfo in messageList) {
      if (messageInfo.rawMessage == null) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "MessageInfo.rawMessage cannot be null";
        return handler;
      }
      v2MessageList.add(messageInfo.rawMessage!);
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().getMessageReactions(
          messageList: v2MessageList,
          maxUserCountPerReaction: maxUserCountPerReaction,
        );

    if (result.code == 0 && result.data != null) {
      for (final reactionResult in result.data!) {
        final index = _messageList.indexWhere((msg) => msg.msgID == reactionResult.messageID);
        if (index != -1 && reactionResult.reactionList != null) {
          _messageList[index].reactionList = ChatUtil.convertToMessageReactions(reactionResult.reactionList);
        }
      }
      _markNeedUpdate();
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Fetch merged messages
  Future<CompletionHandler> _fetchMergedMessagesInternal(MessageFetchOption option) async {
    final handler = CompletionHandler();

    if (option.message == null || option.message!.rawMessage == null) {
      handler.errorCode = -1;
      handler.errorMessage = "Invalid merged message";
      return handler;
    }

    final rawMessage = option.message!.rawMessage!;
    if (rawMessage.elemType != MessageElemType.V2TIM_ELEM_TYPE_MERGER || rawMessage.mergerElem == null) {
      handler.errorCode = -1;
      handler.errorMessage = "Invalid merged message";
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().downloadMergerMessage(
          message: rawMessage,
        );

    if (result.code == 0 && result.data != null) {
      _messageList = _convertToUIMessageList(result.data!);
      _markNeedUpdate();

      // Emit fetch messages event
      _messageEventController.add(FetchMessagesEvent(
        messageList: _messageList,
        direction: option.direction,
      ));
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Delete messages
  Future<CompletionHandler> _deleteMessagesInternal(List<MessageInfo> messageList) async {
    final handler = CompletionHandler();

    if (messageList.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "messageList cannot be empty";
      return handler;
    }

    List<V2TimMessage> v2MessageList = [];
    List<String> messageIDList = [];

    for (final messageInfo in messageList) {
      if (messageInfo.rawMessage == null) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "MessageInfo.rawMessage cannot be null";
        return handler;
      }

      if (messageInfo.msgID == null) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "MessageInfo.msgID cannot be null";
        return handler;
      }

      v2MessageList.add(messageInfo.rawMessage!);
      messageIDList.add(messageInfo.msgID!);
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().deleteMessages(
          messageList: v2MessageList,
        );

    if (result.code == 0) {
      // Post notification with messageIDList for batch deletion
      NotificationCenter().post(
        MessageActionNotifyKey.messageDelete,
        MessageDeleteEventData(messageIDList: messageIDList),
      );
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  // Forward messages
  Future<CompletionHandler> _forwardMessagesInternal(
    List<MessageInfo> messageList,
    MessageForwardOption forwardOption,
    String conversationID,
  ) async {
    final handler = CompletionHandler();

    if (messageList.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "messageList cannot be empty";
      return handler;
    }

    for (final message in messageList) {
      if (message.rawMessage == null) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "MessageInfo.rawMessage cannot be null";
        return handler;
      }

      if (message.status != MessageStatus.sendSuccess) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "Only successfully sent messages can be forwarded";
        return handler;
      }

      if (message.messageType == MessageType.system || message.messageType == MessageType.unknown) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "System messages and unknown messages cannot be forwarded";
        return handler;
      }
    }

    if (conversationID.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "conversationID cannot be empty";
      return handler;
    }

    if (forwardOption.forwardType == MessageForwardType.merged) {
      if (messageList.length > 300) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage = "messageList count cannot exceed 300 when forwardType is .merged";
        return handler;
      }

      if (forwardOption.mergedForwardInfo == null || forwardOption.mergedForwardInfo!.title.isEmpty) {
        handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
        handler.errorMessage =
            "mergedForwardInfo and mergedForwardInfo.title cannot be empty when forwardType is .merged";
        return handler;
      }

      return await _forwardMergedMessages(messageList, forwardOption.mergedForwardInfo!, conversationID);
    } else {
      return await _forwardSeparateMessages(messageList, conversationID);
    }
  }

  Future<CompletionHandler> _forwardMergedMessages(
    List<MessageInfo> messageList,
    MergedForwardInfo mergedForwardInfo,
    String conversationID,
  ) async {
    final v2MessageList = messageList.map((msg) => msg.rawMessage!).toList();

    final createResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createMergerMessage(
          messageList: v2MessageList,
          title: mergedForwardInfo.title,
          abstractList: mergedForwardInfo.abstractList ?? [],
          compatibleText: mergedForwardInfo.compatibleText,
        );

    if (createResult.code != 0 || createResult.data?.messageInfo == null) {
      return CompletionHandler()
        ..errorCode = createResult.code
        ..errorMessage = createResult.desc.isEmpty ? "Failed to create merger message" : createResult.desc;
    }

    final mergerMessage = createResult.data!.messageInfo!;

    var messageInfo = MessageInfo();
    var messageBody = MessageBody();
    final mergerMessageInfo = MergedMessageInfo(
      title: mergedForwardInfo.title,
      abstractList: mergedForwardInfo.abstractList,
    );
    messageBody.mergedMessage = mergerMessageInfo;
    messageInfo.messageType = MessageType.merged;
    messageInfo.messageBody = messageBody;
    messageInfo.needReadReceipt = mergedForwardInfo.needReadReceipt;
    messageInfo.supportExtension = mergedForwardInfo.supportExtension;
    messageInfo.offlinePushInfo = mergedForwardInfo.offlinePushInfo;
    messageInfo.rawMessage = mergerMessage;

    return await _sendMessageToConversation(messageInfo, conversationID);
  }

  Future<CompletionHandler> _forwardSeparateMessages(
    List<MessageInfo> messageList,
    String conversationID,
  ) async {
    CompletionHandler? lastError;
    bool hasError = false;

    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (message.rawMessage == null) continue;

      final createResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createForwardMessage(
            message: message.rawMessage,
          );

      if (createResult.code != 0 || createResult.data?.messageInfo == null) {
        return CompletionHandler()
          ..errorCode = createResult.code
          ..errorMessage = createResult.desc.isEmpty ? "Failed to create forward message" : createResult.desc;
      }

      final forwardMessage = createResult.data!.messageInfo!;

      var messageInfo = MessageInfo();
      messageInfo.messageType = message.messageType;
      messageInfo.messageBody = message.messageBody;
      messageInfo.needReadReceipt = message.needReadReceipt;
      messageInfo.supportExtension = message.supportExtension;
      messageInfo.offlinePushInfo = message.offlinePushInfo;
      messageInfo.rawMessage = forwardMessage;

      // Add delay between messages to avoid rate limiting
      if (i > 0) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final result = await _sendMessageToConversation(messageInfo, conversationID);
      if (result.errorCode != 0) {
        hasError = true;
        lastError = result;
      }
    }

    if (hasError && lastError != null) {
      return lastError;
    }

    return CompletionHandler();
  }

  Future<CompletionHandler> _sendMessageToConversation(
    MessageInfo messageInfo,
    String conversationID,
  ) async {
    final inputStore = MessageInputStore.create(conversationID: conversationID);
    return await inputStore.sendMessage(message: messageInfo);
  }
}
