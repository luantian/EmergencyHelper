import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:atomic_x_core/api/contact/group_setting_store.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/api/login/login_store.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

enum MessageStatus {
  initStatus,
  sending,
  sendSuccess,
  sendFail,
  recalled,
  deleted,
  localImported,
  violation,
}

enum MessageType {
  unknown,
  text,
  image,
  video,
  sound,
  file,
  face,
  system,
  custom,
  merged,
}

class ReplyMessageInfo {
  String? msgID;
  String? msgSender;
  String? msgAbstract;
  MessageStatus? msgStatus;
  MessageType? messageType;
  MessageBody? messageBody;

  ReplyMessageInfo({
    this.msgID,
    this.msgSender,
    this.msgAbstract,
    this.msgStatus,
    this.messageType,
    this.messageBody,
  });
}

class CustomMessageInfo {
  String? data;
  String? description;
  String? extensionInfo;

  CustomMessageInfo({
    this.data,
    this.description,
    this.extensionInfo,
  });
}

class MessageSenderInfo {
  String userID;
  String? avatarURL;
  String? nickname;
  String? friendRemark;
  String? nameCard;

  MessageSenderInfo({
    this.userID = "",
    this.avatarURL,
    this.nickname,
    this.friendRemark,
    this.nameCard,
  });
}

class OfflinePushInfo {
  String title;
  String description;
  Map<String, dynamic> extensionInfo;

  OfflinePushInfo({
    this.title = "",
    this.description = "",
    this.extensionInfo = const {},
  });
}

class MessageInfo {
  String? msgID;
  MessageSenderInfo sender = MessageSenderInfo();
  bool isSelf = false;
  String? receiver;
  String? groupID;
  int? timestamp; // seconds
  MessageStatus status = MessageStatus.initStatus;
  int progress = 0; // (0-100)
  List<String> atUserList = [];
  bool isPinned = false;

  MessageType messageType = MessageType.unknown;
  MessageBody? messageBody;

  bool needReadReceipt = false;
  MessageReceipt? receipt;

  bool supportExtension = false;
  List<MessageExtension> extensionList = [];

  List<MessageReaction> reactionList = [];

  ReplyMessageInfo? replyMessageInfo;
  int repliedMessageCount = 0;

  ReplyMessageInfo? quoteMessageInfo;

  // Offline Push Info
  OfflinePushInfo? offlinePushInfo;

  V2TimMessage? rawMessage;

  MessageInfo();
}

class MessageExtension {
  String? extensionKey;
  String? extensionValue;

  MessageExtension({this.extensionKey, this.extensionValue});
}

class MessageReceipt {
  bool isPeerRead;
  int readCount;
  int unreadCount;

  MessageReceipt({
    this.isPeerRead = false,
    this.readCount = 0,
    this.unreadCount = 0,
  });
}

class MessageReaction {
  String reactionID;
  int totalUserCount;
  List<UserProfile> partialUserList;
  bool reactedByMyself;

  MessageReaction({
    required this.reactionID,
    this.totalUserCount = 0,
    this.partialUserList = const [],
    this.reactedByMyself = false,
  });
}

class MessageBody {
  String? text;
  String? translateLanguage;
  Map<String, String>? translatedText;

  String? originalImagePath;
  int originalImageWidth = 0;
  int originalImageHeight = 0;
  int originalImageSize = 0;
  String? thumbImagePath;
  String? largeImagePath;

  String? videoPath;
  String? videoType;
  int videoSize = 0;
  int videoDuration = 0;
  String? videoSnapshotPath;
  int videoSnapshotWidth = 0;
  int videoSnapshotHeight = 0;
  int videoSnapshotSize = 0;

  String? soundPath;
  int soundSize = 0;
  int soundDuration = 0;
  bool? isSoundPlayed;
  String? asrLanguage;
  String? asrText;

  String? filePath;
  String? fileName;
  int fileSize = 0;

  int faceIndex = 0;
  String? faceName;

  List<SystemMessageInfo>? systemMessage;
  CustomMessageInfo? customMessage;
  MergedMessageInfo? mergedMessage;

  MessageBody();
}

class MergedMessageInfo {
  String title;
  List<String>? abstractList;

  MergedMessageInfo({required this.title, this.abstractList});
}

sealed class SystemMessageInfo {}

class UnknownSystemMessage extends SystemMessageInfo {}

class JoinGroupSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String joinMember;

  JoinGroupSystemMessage({
    required this.groupID,
    required this.joinMember,
  });
}

class InviteToGroupSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String inviter;
  final String inviteesShowName;

  InviteToGroupSystemMessage({
    required this.groupID,
    required this.inviter,
    required this.inviteesShowName,
  });
}

class QuitGroupSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String quitMember;

  QuitGroupSystemMessage({
    required this.groupID,
    required this.quitMember,
  });
}

class KickedFromGroupSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String kickOperator;
  final String kickedMembersShowName;

  KickedFromGroupSystemMessage({
    required this.groupID,
    required this.kickOperator,
    required this.kickedMembersShowName,
  });
}

class SetGroupAdminSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String setAdminOperator;
  final String setAdminMembersShowName;

  SetGroupAdminSystemMessage({
    required this.groupID,
    required this.setAdminOperator,
    required this.setAdminMembersShowName,
  });
}

class CancelGroupAdminSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String cancelAdminOperator;
  final String cancelAdminMembersShowName;

  CancelGroupAdminSystemMessage({
    required this.groupID,
    required this.cancelAdminOperator,
    required this.cancelAdminMembersShowName,
  });
}

class ChangeGroupNameSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String groupNameOperator;
  final String groupName;

  ChangeGroupNameSystemMessage({
    required this.groupID,
    required this.groupNameOperator,
    required this.groupName,
  });
}

class ChangeGroupAvatarSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String groupAvatarOperator;
  final String groupAvatar;

  ChangeGroupAvatarSystemMessage({
    required this.groupID,
    required this.groupAvatarOperator,
    required this.groupAvatar,
  });
}

class ChangeGroupNotificationSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String groupNotificationOperator;
  final String groupNotification;

  ChangeGroupNotificationSystemMessage({
    required this.groupID,
    required this.groupNotificationOperator,
    required this.groupNotification,
  });
}

class ChangeGroupIntroductionSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String groupIntroductionOperator;
  final String groupIntroduction;

  ChangeGroupIntroductionSystemMessage({
    required this.groupID,
    required this.groupIntroductionOperator,
    required this.groupIntroduction,
  });
}

class ChangeGroupOwnerSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String groupOwnerOperator;
  final String groupOwner;

  ChangeGroupOwnerSystemMessage({
    required this.groupID,
    required this.groupOwnerOperator,
    required this.groupOwner,
  });
}

class ChangeGroupMuteAllSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String groupMuteAllOperator;
  final bool isMuteAll;

  ChangeGroupMuteAllSystemMessage({
    required this.groupID,
    required this.groupMuteAllOperator,
    required this.isMuteAll,
  });
}

class ChangeJoinGroupApprovalSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String groupJoinApprovalOperator;
  final GroupJoinOption groupJoinOption;

  ChangeJoinGroupApprovalSystemMessage({
    required this.groupID,
    required this.groupJoinApprovalOperator,
    required this.groupJoinOption,
  });
}

class ChangeInviteToGroupApprovalSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String groupInviteApprovalOperator;
  final GroupJoinOption groupInviteOption;

  ChangeInviteToGroupApprovalSystemMessage({
    required this.groupID,
    required this.groupInviteApprovalOperator,
    required this.groupInviteOption,
  });
}

class MuteGroupMemberSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String muteGroupMemberOperator;
  final bool isSelfMuted;
  final String mutedGroupMembersShowName;
  final int muteTime;

  MuteGroupMemberSystemMessage({
    required this.groupID,
    required this.muteGroupMemberOperator,
    required this.isSelfMuted,
    required this.mutedGroupMembersShowName,
    required this.muteTime,
  });
}

class PinGroupMessageSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String pinGroupMessageOperator;

  PinGroupMessageSystemMessage({
    required this.groupID,
    required this.pinGroupMessageOperator,
  });
}

class UnpinGroupMessageSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String unpinGroupMessageOperator;

  UnpinGroupMessageSystemMessage({
    required this.groupID,
    required this.unpinGroupMessageOperator,
  });
}

class RecallMessageSystemMessage extends SystemMessageInfo {
  final String groupID;
  final String recallMessageOperator;
  final bool isRecalledBySelf;
  final bool isInGroup;
  final String recallReason;

  RecallMessageSystemMessage({
    required this.groupID,
    required this.recallMessageOperator,
    required this.isRecalledBySelf,
    required this.isInGroup,
    required this.recallReason,
  });
}

enum MessageListType {
  history,
  pinned,
  replied,
  merged,
}

enum MessageFetchDirection {
  older,
  newer,
  both,
}

enum MessageForwardType {
  separate,
  merged,
}

class MergedForwardInfo {
  String title;
  List<String>? abstractList;
  String compatibleText;

  bool needReadReceipt;
  bool supportExtension;
  OfflinePushInfo? offlinePushInfo;

  MergedForwardInfo({
    this.title = "",
    this.abstractList,
    this.compatibleText = "",
    this.needReadReceipt = false,
    this.supportExtension = false,
    this.offlinePushInfo,
  });
}

class MessageForwardOption {
  MessageForwardType forwardType;
  MergedForwardInfo? mergedForwardInfo;

  MessageForwardOption({
    this.forwardType = MessageForwardType.separate,
    this.mergedForwardInfo,
  });
}

class MessageFilterType {
  final int rawValue;

  const MessageFilterType(this.rawValue);

  static const all = MessageFilterType(0x1);
  static const image = MessageFilterType(0x1 << 1);
  static const video = MessageFilterType(0x1 << 2);

  MessageFilterType operator |(MessageFilterType other) {
    return MessageFilterType(rawValue | other.rawValue);
  }

  bool contains(MessageFilterType other) {
    return (rawValue & other.rawValue) != 0;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageFilterType && other.rawValue == rawValue;
  }

  @override
  int get hashCode => rawValue.hashCode;
}

class MessageFetchOption {
  MessageInfo? message;
  int messageSeq = 0;
  MessageFetchDirection direction = MessageFetchDirection.older;
  MessageFilterType filterType = MessageFilterType.all;
  int pageCount = 20;

  MessageFetchOption();
}

enum MessageMediaFileType {
  thumbImage,
  largeImage,
  originalImage,
  videoSnapshot,
  video,
  sound,
  file,
}

// Message Event
// UI generally determines the scrolling state of the message list based on the message event
// 1. When fetchMessages:
//    when direction is .newer, the message list generally scrolls to the top with animation
//    when direction is .older, the message list generally scrolls to the bottom with animation
//    when direction is .both, the message list generally scrolls to the center with animation
// 2. When fetchMoreMessages:
//    the message list generally doesn't need to scroll
// 3. When sendMessage:
//    the message list generally scrolls to the bottom with animation
// 4. When recvMessage:
//    the message list generally scrolls to the bottom with animation
// 5. When deleteMessages:
//    the message list generally doesn't need to scroll
sealed class MessageEvent {}

class FetchMessagesEvent extends MessageEvent {
  final List<MessageInfo> messageList;
  final MessageFetchDirection direction;

  FetchMessagesEvent({
    required this.messageList,
    required this.direction,
  });
}

class FetchMoreMessagesEvent extends MessageEvent {
  final List<MessageInfo> messageList;

  FetchMoreMessagesEvent({required this.messageList});
}

class SendMessageEvent extends MessageEvent {
  final MessageInfo message;

  SendMessageEvent({required this.message});
}

class RecvMessageEvent extends MessageEvent {
  final MessageInfo message;

  RecvMessageEvent({required this.message});
}

class DeleteMessagesEvent extends MessageEvent {
  final List<MessageInfo> messageList;

  DeleteMessagesEvent({required this.messageList});
}

class MessageListState {
  final List<MessageInfo> messageList;
  final bool hasMoreOlderMessage;
  final bool hasMoreNewerMessage;

  const MessageListState({
    required this.messageList,
    this.hasMoreOlderMessage = false,
    this.hasMoreNewerMessage = false,
  });
}

abstract class MessageListStore extends ChangeNotifier {
  static MessageListStore create({
    required String conversationID,
    required MessageListType messageListType,
  }) {
    return MessageListStoreImpl(conversationID: conversationID, messageListType: messageListType);
  }

  String get conversationID;

  MessageListState get messageListState;

  Stream<MessageEvent> get messageEventStream;

  Future<CompletionHandler> fetchMessageList({required MessageFetchOption option});

  Future<CompletionHandler> fetchMoreMessageList({required MessageFetchDirection direction});

  Future<CompletionHandler> downloadMessageResource(
      {required MessageInfo message, required MessageMediaFileType resourceType});

  Future<CompletionHandler> sendMessageReadReceipts({required List<MessageInfo> messageList});

  Future<CompletionHandler> fetchMessageReactions(
      {required List<MessageInfo> messageList, required int maxUserCountPerReaction});

  Future<CompletionHandler> deleteMessages({required List<MessageInfo> messageList});

  Future<CompletionHandler> forwardMessages({
    required List<MessageInfo> messageList,
    required MessageForwardOption forwardOption,
    required String conversationID,
  });
}
