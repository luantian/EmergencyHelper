import 'dart:convert';
import 'dart:io';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/login/login_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_add_opt_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_change_info_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_tips_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/image_types.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart' as sdk_status;
import 'package:tencent_cloud_chat_sdk/enum/receive_message_opt_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/common_utils.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_change_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_tips_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_extension.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_reaction.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_info.dart';

const c2cConversationIDPrefix = "c2c_";
const groupConversationIDPrefix = "group_";

class ChatUtil {
  static String getHomePath({bool isCache = false}) {
    try {
      if (!isCache) {
        var directory = CommonUtils.appFileDir;
        return '${directory.path}/atomicx_core_data';
      } else {
        var directory = CommonUtils.appCacheDir;
        return directory.path;
      }
    } catch (e) {
      return '/tmp/atomicx_core_data';
    }
  }

  static String getMediaHomePath({required MessageType messageType, bool isCache = false}) {
    if (messageType == MessageType.image) {
      return '${getHomePath(isCache: isCache)}${isCache ? "" : "/image"}';
    } else if (messageType == MessageType.video) {
      return '${getHomePath(isCache: isCache)}${isCache ? "" : "/video"}';
    } else if (messageType == MessageType.sound) {
      return '${getHomePath(isCache: isCache)}${isCache ? "" : "/voice"}';
    } else if (messageType == MessageType.file) {
      return '${getHomePath(isCache: isCache)}${isCache ? "" : "/file"}';
    } else {
      return "";
    }
  }

  static String generateMediaPath(
      {required MessageType messageType, String? prefix, String? withExtension, bool isCache = false}) {
    final sdkAppID = LoginStore.shared.sdkAppID;
    final userID = LoginStoreImpl.instance.loginState.loginUserInfo?.userID;
    final uuid = "${DateTime.now().millisecondsSinceEpoch}";

    final mediaHomePath = getMediaHomePath(messageType: messageType, isCache: isCache);

    String prefixString = "";
    if (prefix != null && prefix.isNotEmpty) {
      prefixString = "${prefix}_";
    }

    String suffixString = "";
    if (withExtension != null && withExtension.isNotEmpty) {
      suffixString = ".$withExtension";
    }

    if (messageType == MessageType.image) {
      return "$mediaHomePath/${prefixString}image_${sdkAppID}_${userID ?? ""}_$uuid$suffixString";
    } else if (messageType == MessageType.video) {
      return "$mediaHomePath/${prefixString}video_${sdkAppID}_${userID ?? ""}_$uuid$suffixString";
    } else if (messageType == MessageType.sound) {
      return "$mediaHomePath/${prefixString}sound_${sdkAppID}_${userID ?? ""}_$uuid$suffixString";
    } else if (messageType == MessageType.file) {
      return "$mediaHomePath/${prefixString}file_${sdkAppID}_${userID ?? ""}_$uuid$suffixString";
    }

    return "";
  }

  static String getUserID(String? conversationID) {
    if (conversationID == null || conversationID.isEmpty) {
      return "";
    }

    if (conversationID.startsWith(c2cConversationIDPrefix)) {
      return conversationID.replaceFirst(c2cConversationIDPrefix, "");
    }
    return "";
  }

  static String getGroupID(String? conversationID) {
    if (conversationID == null || conversationID.isEmpty) {
      return "";
    }

    if (conversationID.startsWith(groupConversationIDPrefix)) {
      return conversationID.replaceFirst(groupConversationIDPrefix, "");
    }
    return "";
  }

  static String getMemberShowName(V2TimGroupMemberInfo? info) {
    if (info == null) return "";
    if (info.nameCard != null && info.nameCard!.isNotEmpty) {
      return info.nameCard!;
    } else if (info.nickName != null && info.nickName!.isNotEmpty) {
      return info.nickName!;
    } else {
      return info.userID ?? "";
    }
  }

  static String getMemberShowNameFromTips(V2TimGroupTipsElem? tips, String? userId) {
    if (tips == null || userId == null) return "";
    if (tips.memberList != null) {
      for (var info in tips.memberList!) {
        if (info?.userID == userId) {
          return getMemberShowName(info);
        }
      }
    }
    return "";
  }

  static List<String> getMembersShowName(List<V2TimGroupMemberInfo?>? infoList) {
    if (infoList == null) return [];
    List<String> userNameList = [];
    for (var info in infoList) {
      if (info != null) {
        userNameList.add(getMemberShowName(info));
      }
    }
    return userNameList;
  }

  static String getMessageSenderName(MessageInfo? message) {
    if (message == null) return "";
    final rawMessage = message.rawMessage;
    if (rawMessage == null) return "";
    String showName = rawMessage.sender ?? "";
    if (rawMessage.nameCard != null && rawMessage.nameCard!.isNotEmpty) {
      showName = rawMessage.nameCard!;
    } else if (rawMessage.friendRemark != null && rawMessage.friendRemark!.isNotEmpty) {
      showName = rawMessage.friendRemark!;
    } else if (rawMessage.nickName != null && rawMessage.nickName!.isNotEmpty) {
      showName = rawMessage.nickName!;
    }
    return showName;
  }

  static MessageInfo convertToUIMessage(V2TimMessage imMessage) {
    MessageInfo message = MessageInfo();
    message.msgID = imMessage.msgID;
    message.status = convertToUIMessageStatus(imMessage);

    MessageSenderInfo sender = MessageSenderInfo();
    sender.userID = imMessage.sender ?? "";
    sender.nickname = imMessage.nickName;
    sender.avatarURL = imMessage.faceUrl;
    sender.friendRemark = imMessage.friendRemark;
    sender.nameCard = imMessage.nameCard;
    message.sender = sender;

    message.isSelf = imMessage.isSelf ?? false;
    message.receiver = imMessage.userID;
    message.groupID = imMessage.groupID;
    message.timestamp = imMessage.timestamp;
    message.needReadReceipt = imMessage.needReadReceipt ?? false;
    message.supportExtension = imMessage.isSupportMessageExtension ?? false;
    message.atUserList = imMessage.groupAtUserList ?? [];
    message.messageType = getMessageType(imMessage);
    message.messageBody = getMessageBody(imMessage);

    message.rawMessage = imMessage;
    return message;
  }

  static MessageStatus convertToUIMessageStatus(V2TimMessage imMessage) {
    if (imMessage.hasRiskContent ?? false) {
      return MessageStatus.violation;
    }

    if (imMessage.status != null) {
      switch (imMessage.status) {
        case sdk_status.MessageStatus.V2TIM_MSG_STATUS_SENDING:
          return MessageStatus.sending;
        case sdk_status.MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC:
          return MessageStatus.sendSuccess;
        case sdk_status.MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL:
          return MessageStatus.sendFail;
        case sdk_status.MessageStatus.V2TIM_MSG_STATUS_HAS_DELETED:
          return MessageStatus.deleted;
        case sdk_status.MessageStatus.V2TIM_MSG_STATUS_LOCAL_IMPORTED:
          return MessageStatus.localImported;
        case sdk_status.MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED:
          return MessageStatus.recalled;
        default:
          return MessageStatus.initStatus;
      }
    }

    return MessageStatus.initStatus;
  }

  static MessageType getMessageType(V2TimMessage imMessage) {
    if (imMessage.status == sdk_status.MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED) {
      return MessageType.system;
    }

    switch (imMessage.elemType) {
      case MessageElemType.V2TIM_ELEM_TYPE_TEXT:
        return MessageType.text;
      case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
        return MessageType.image;
      case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
        return MessageType.sound;
      case MessageElemType.V2TIM_ELEM_TYPE_FILE:
        return MessageType.file;
      case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
        return MessageType.video;
      case MessageElemType.V2TIM_ELEM_TYPE_FACE:
        return MessageType.face;
      case MessageElemType.V2TIM_ELEM_TYPE_CUSTOM:
        return MessageType.custom;
      case MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS:
        return MessageType.system;
      case MessageElemType.V2TIM_ELEM_TYPE_MERGER:
        return MessageType.merged;
      default:
        return MessageType.unknown;
    }
  }

  static MessageBody? getMessageBody(V2TimMessage imMessage) {
    if (imMessage.status == sdk_status.MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED) {
      MessageBody messageBody = MessageBody();
      messageBody.systemMessage = [ChatUtil.convertToSystemInfoFromRecall(imMessage, null, null)];
      return messageBody;
    }

    switch (imMessage.elemType) {
      case MessageElemType.V2TIM_ELEM_TYPE_TEXT:
        MessageBody messageBody = MessageBody();
        messageBody.text = imMessage.textElem?.text;
        // Parse translatedText from localCustomData
        final localCustomData = imMessage.localCustomData;
        if (localCustomData != null && localCustomData.isNotEmpty) {
          final json = jsonData2Dictionary(localCustomData);
          if (json != null) {
            final translatedTextMap = json['text_translation'] as Map<String, dynamic>?;
            if (translatedTextMap != null && translatedTextMap.isNotEmpty) {
              messageBody.translatedText = translatedTextMap.map((key, value) => MapEntry(key, value.toString()));
            }
            final translateLanguage = json['text_translation_language'] as String?;
            if (translateLanguage != null) {
              messageBody.translateLanguage = translateLanguage;
            }
          }
        }
        return messageBody;

      case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
        if (imMessage.imageElem != null) {
          MessageBody messageBody = MessageBody();

          if (imMessage.imageElem?.imageList != null) {
            for (var image in imMessage.imageElem!.imageList!) {
              if (image?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN) {
                messageBody.originalImageSize = image?.size ?? 0;
                messageBody.originalImageWidth = image?.width ?? 0;
                messageBody.originalImageHeight = image?.height ?? 0;
                final originalImageResult =
                    getActualMediaPath(MessageType.image, imMessage.imageElem!.path, image?.uuid ?? "", "origin_");

                final originalImagePath = originalImageResult[filePathKey];
                bool isLocalExist = originalImageResult[localExistKey];
                if (isLocalExist) {
                  messageBody.originalImagePath = originalImagePath;
                }
              } else if (image?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB) {
                final thumbImageResult =
                    getActualMediaPath(MessageType.image, image?.localUrl ?? "", image?.uuid ?? "", "thumb_");

                final thumbImagePath = thumbImageResult[filePathKey];
                bool isLocalExist = thumbImageResult[localExistKey];
                if (isLocalExist) {
                  messageBody.thumbImagePath = thumbImagePath;
                }
              } else if (image?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_LARGE) {
                final largeImageResult =
                    getActualMediaPath(MessageType.image, image?.localUrl ?? "", image?.uuid ?? '', "large_");

                final largeImagePath = largeImageResult[filePathKey];
                bool isLocalExist = largeImageResult[localExistKey];
                if (isLocalExist) {
                  messageBody.largeImagePath = largeImagePath;
                }
              }
            }
          }

          return messageBody;
        }
        break;

      case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
        if (imMessage.soundElem != null) {
          MessageBody messageBody = MessageBody();
          messageBody.soundSize = imMessage.soundElem?.dataSize ?? 0;
          messageBody.soundDuration = imMessage.soundElem?.duration ?? 0;
          final soundPathResult = getActualMediaPath(
            MessageType.sound,
            imMessage.soundElem!.path,
            imMessage.soundElem!.UUID ?? '',
            null,
          );

          final soundPath = soundPathResult[filePathKey];
          bool isLocalExist = soundPathResult[localExistKey];
          if (isLocalExist) {
            messageBody.soundPath = soundPath;
          }

          // Parse asrText from localCustomData
          final localCustomData = imMessage.localCustomData;
          if (localCustomData != null && localCustomData.isNotEmpty) {
            final json = jsonData2Dictionary(localCustomData);
            if (json != null) {
              final asrText = json['voice_to_text'] as String?;
              if (asrText != null) {
                messageBody.asrText = asrText;
              }
            }
          }

          return messageBody;
        }
        break;

      case MessageElemType.V2TIM_ELEM_TYPE_FILE:
        if (imMessage.fileElem != null) {
          MessageBody messageBody = MessageBody();
          messageBody.fileName = imMessage.fileElem?.fileName;
          messageBody.fileSize = imMessage.fileElem?.fileSize ?? 0;
          final filePathResult = getActualMediaPath(
            MessageType.file,
            imMessage.fileElem!.path,
            imMessage.fileElem!.UUID ?? '',
            null,
          );

          final filePath = filePathResult[filePathKey];
          bool isLocalExist = filePathResult[localExistKey];
          if (isLocalExist) {
            messageBody.filePath = filePath;
          }

          return messageBody;
        }
        break;

      case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
        if (imMessage.videoElem != null) {
          MessageBody messageBody = MessageBody();
          messageBody.videoSnapshotSize = imMessage.videoElem?.snapshotSize ?? 0;
          messageBody.videoSnapshotWidth = imMessage.videoElem?.snapshotWidth ?? 0;
          messageBody.videoSnapshotHeight = imMessage.videoElem?.snapshotHeight ?? 0;
          final snapshotPathResult = getActualMediaPath(
            MessageType.video,
            imMessage.videoElem!.snapshotPath,
            imMessage.videoElem!.snapshotUUID ?? '',
            null,
          );

          final snapshotPath = snapshotPathResult[filePathKey];
          bool isSnapshotLocalExist = snapshotPathResult[localExistKey];
          if (isSnapshotLocalExist) {
            messageBody.videoSnapshotPath = snapshotPath;
          }

          messageBody.videoSize = imMessage.videoElem?.videoSize ?? 0;
          messageBody.videoDuration = imMessage.videoElem?.duration ?? 0;
          final videoPathResult = getActualMediaPath(
            MessageType.video,
            imMessage.videoElem!.videoPath,
            imMessage.videoElem!.UUID ?? '',
            null,
          );

          final videoPath = videoPathResult[filePathKey];
          bool isVideoLocalExist = videoPathResult[localExistKey];
          if (isVideoLocalExist) {
            messageBody.videoPath = videoPath;
          }

          return messageBody;
        }
        break;

      case MessageElemType.V2TIM_ELEM_TYPE_FACE:
        if (imMessage.faceElem != null) {
          MessageBody messageBody = MessageBody();
          messageBody.faceIndex = imMessage.faceElem?.index ?? 0;
          messageBody.faceName = imMessage.faceElem?.data;
          return messageBody;
        }
        break;

      case MessageElemType.V2TIM_ELEM_TYPE_CUSTOM:
        if (imMessage.customElem != null) {
          MessageBody messageBody = MessageBody();
          messageBody.customMessage = CustomMessageInfo(
              data: imMessage.customElem!.data ?? '',
              description: imMessage.customElem!.desc ?? '',
              extensionInfo: imMessage.customElem!.extension ?? '');
          return messageBody;
        }
        break;

      case MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS:
        if (imMessage.groupTipsElem != null) {
          final tipsElem = imMessage.groupTipsElem!;
          if (tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_JOIN ||
              tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_INVITE ||
              tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_KICKED ||
              tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_QUIT ||
              tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_GROUP_INFO_CHANGE ||
              tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_SET_ADMIN ||
              tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_CANCEL_ADMIN ||
              tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_MEMBER_INFO_CHANGE ||
              tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_PINNED_MESSAGE_ADDED ||
              tipsElem.type == GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_PINNED_MESSAGE_DELETED) {
            MessageBody messageBody = MessageBody();
            messageBody.systemMessage = ChatUtil.convertToSystemInfoFromGroupTips(tipsElem);
            return messageBody;
          }
        }
        break;

      case MessageElemType.V2TIM_ELEM_TYPE_MERGER:
        if (imMessage.mergerElem != null) {
          final mergerElem = imMessage.mergerElem!;
          MessageBody messageBody = MessageBody();
          messageBody.mergedMessage = MergedMessageInfo(
            title: mergerElem.title ?? '',
            abstractList: mergerElem.abstractList,
          );
          return messageBody;
        }
        break;

      default:
        return null;
    }

    return null;
  }

  static Map<String, dynamic> getActualMediaPath(
      MessageType messageType, String? mediaPath, String uuid, String? extension) {
    String actualMediaPath = "";
    bool isLocalExist = false;
    final mediaHomePath = ChatUtil.getMediaHomePath(messageType: messageType);

    if (mediaPath != null && mediaPath.isNotEmpty) {
      actualMediaPath = mediaPath;
      if (File(actualMediaPath).existsSync()) {
        isLocalExist = true;
        return {'filePath': actualMediaPath, 'isLocalExist': isLocalExist};
      }
    }

    if (!isLocalExist) {
      if (messageType == MessageType.image) {
        actualMediaPath = "$mediaHomePath/$extension$uuid";
      } else if (messageType == MessageType.file) {
        actualMediaPath = "$mediaHomePath/$uuid";
      } else if (messageType == MessageType.video || messageType == MessageType.sound) {
        actualMediaPath = "$mediaHomePath/$uuid";
      }

      if (File(actualMediaPath).existsSync()) {
        isLocalExist = true;
      }
    }

    return {'filePath': actualMediaPath, 'isLocalExist': isLocalExist};
  }

  static RecallMessageSystemMessage convertToSystemInfoFromRecall(
      V2TimMessage message, V2TimUserFullInfo? operateUser, String? reason) {
    V2TimUserFullInfo revokerInfo;
    if (message.revokerInfo != null && message.revokerInfo!.userID != null && message.revokerInfo!.userID!.isNotEmpty) {
      revokerInfo = message.revokerInfo!;
    } else if (operateUser != null) {
      revokerInfo = operateUser;
    } else {
      revokerInfo = V2TimUserFullInfo(userID: message.sender, nickName: message.nickName);
    }

    final messageSender = message.sender ?? "";

    String operator = revokerInfo.nickName ?? '';
    if (operator.isEmpty) {
      operator = revokerInfo.userID ?? '';
    }

    bool isInGroup = false;
    if (message.userID != null && message.userID!.isNotEmpty) {
      isInGroup = false;
    } else if (message.groupID != null && message.groupID!.isNotEmpty) {
      isInGroup = true;
    }

    bool isRecalledBySelf = false;
    if (revokerInfo.userID == messageSender) {
      isRecalledBySelf = message.isSelf ?? false;
    }

    return RecallMessageSystemMessage(
      groupID: message.groupID ?? "",
      recallMessageOperator: operator,
      isRecalledBySelf: isRecalledBySelf,
      isInGroup: isInGroup,
      recallReason: reason ?? "",
    );
  }

  static List<SystemMessageInfo> convertToSystemInfoFromGroupTips(V2TimGroupTipsElem tipsElem) {
    final opUser = getMemberShowName(tipsElem.opMember);
    final userList = getMembersShowName(tipsElem.memberList);
    final groupID = tipsElem.groupID;

    switch (tipsElem.type) {
      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_JOIN:
        String joinMember;
        if (userList.isNotEmpty) {
          joinMember = userList.join(', ');
        } else {
          joinMember = opUser;
        }
        return [JoinGroupSystemMessage(groupID: groupID, joinMember: joinMember)];

      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_INVITE:
        final users = userList.join("、");
        return [
          InviteToGroupSystemMessage(
            groupID: groupID,
            inviter: opUser,
            inviteesShowName: users,
          )
        ];

      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_QUIT:
        return [QuitGroupSystemMessage(groupID: groupID, quitMember: opUser)];

      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_KICKED:
        final users = userList.join("、");
        return [
          KickedFromGroupSystemMessage(
            groupID: groupID,
            kickOperator: opUser,
            kickedMembersShowName: users,
          )
        ];

      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_SET_ADMIN:
        final users = userList.join("、");
        return [
          SetGroupAdminSystemMessage(
            groupID: groupID,
            setAdminOperator: opUser,
            setAdminMembersShowName: users,
          )
        ];

      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_CANCEL_ADMIN:
        final users = userList.join("、");
        return [
          CancelGroupAdminSystemMessage(
            groupID: groupID,
            cancelAdminOperator: opUser,
            cancelAdminMembersShowName: users,
          )
        ];

      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_GROUP_INFO_CHANGE:
        List<V2TimGroupChangeInfo?>? groupChangeInfoList = tipsElem.groupChangeInfoList;
        if (groupChangeInfoList != null) {
          return convertToSystemInfoFromGroupInfoChangedList(groupID, opUser, userList, groupChangeInfoList);
        }
        break;

      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_MEMBER_INFO_CHANGE:
        if (tipsElem.memberChangeInfoList != null && tipsElem.memberChangeInfoList!.isNotEmpty) {
          final info = tipsElem.memberChangeInfoList!.first;
          final userId = info?.userID;
          final myUserID = LoginStoreImpl.instance.loginState.loginUserInfo?.userID;
          final mutedMembersShowName = getMemberShowNameFromTips(tipsElem, userId);
          final isSelfMuted = userId == myUserID;
          final muteTime = info?.muteTime ?? 0;

          return [
            MuteGroupMemberSystemMessage(
              groupID: groupID,
              muteGroupMemberOperator: opUser,
              isSelfMuted: isSelfMuted,
              mutedGroupMembersShowName: mutedMembersShowName,
              muteTime: muteTime,
            )
          ];
        }
        break;

      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_PINNED_MESSAGE_ADDED:
        return [
          PinGroupMessageSystemMessage(
            groupID: groupID,
            pinGroupMessageOperator: opUser,
          )
        ];

      case GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_PINNED_MESSAGE_DELETED:
        return [
          UnpinGroupMessageSystemMessage(
            groupID: groupID,
            unpinGroupMessageOperator: opUser,
          )
        ];

      default:
        break;
    }

    return [UnknownSystemMessage()];
  }

  static List<SystemMessageInfo> convertToSystemInfoFromGroupInfoChangedList(
      String groupID, String opUser, List<String> userList, List<V2TimGroupChangeInfo?> groupChangeInfoList) {
    List<SystemMessageInfo> results = [];

    for (var info in groupChangeInfoList) {
      switch (info?.type) {
        case GroupChangeInfoType.V2TIM_GROUP_INFO_CHANGE_TYPE_NAME:
          if (info?.value != null) {
            results.add(ChangeGroupNameSystemMessage(
              groupID: groupID,
              groupNameOperator: opUser,
              groupName: info!.value!,
            ));
          }
          break;

        case GroupChangeInfoType.V2TIM_GROUP_INFO_CHANGE_TYPE_INTRODUCTION:
          if (info?.value != null) {
            results.add(ChangeGroupIntroductionSystemMessage(
              groupID: groupID,
              groupIntroductionOperator: opUser,
              groupIntroduction: info!.value!,
            ));
          }
          break;

        case GroupChangeInfoType.V2TIM_GROUP_INFO_CHANGE_TYPE_NOTIFICATION:
          results.add(ChangeGroupNotificationSystemMessage(
            groupID: groupID,
            groupNotificationOperator: opUser,
            groupNotification: info?.value ?? "",
          ));
          break;

        case GroupChangeInfoType.V2TIM_GROUP_INFO_CHANGE_TYPE_FACE_URL:
          results.add(ChangeGroupAvatarSystemMessage(
            groupID: groupID,
            groupAvatarOperator: opUser,
            groupAvatar: info?.value ?? "",
          ));
          break;

        case GroupChangeInfoType.V2TIM_GROUP_INFO_CHANGE_TYPE_OWNER:
          String groupOwner;
          if (userList.isNotEmpty) {
            groupOwner = userList.first;
          } else if (info?.value != null) {
            groupOwner = info!.value!;
          } else {
            groupOwner = "";
          }
          results.add(ChangeGroupOwnerSystemMessage(
            groupID: groupID,
            groupOwnerOperator: opUser,
            groupOwner: groupOwner,
          ));
          break;

        case GroupChangeInfoType.V2TIM_GROUP_INFO_CHANGE_TYPE_SHUT_UP_ALL:
          results.add(ChangeGroupMuteAllSystemMessage(
            groupID: groupID,
            groupMuteAllOperator: opUser,
            isMuteAll: info?.boolValue ?? false,
          ));
          break;

        case GroupChangeInfoType.V2TIM_GROUP_INFO_CHANGE_TYPE_GROUP_ADD_OPT:
          final addOpt = info?.intValue;
          GroupJoinOption groupJoinOption;
          if (addOpt == GroupAddOptType.V2TIM_GROUP_ADD_FORBID) {
            groupJoinOption = GroupJoinOption.forbid;
          } else if (addOpt == GroupAddOptType.V2TIM_GROUP_ADD_AUTH) {
            groupJoinOption = GroupJoinOption.auth;
          } else if (addOpt == GroupAddOptType.V2TIM_GROUP_ADD_ANY) {
            groupJoinOption = GroupJoinOption.any;
          } else {
            groupJoinOption = GroupJoinOption.any; // 默认值
          }

          results.add(ChangeJoinGroupApprovalSystemMessage(
            groupID: groupID,
            groupJoinApprovalOperator: opUser,
            groupJoinOption: groupJoinOption,
          ));
          break;

        case GroupChangeInfoType.V2TIM_GROUP_INFO_CHANGE_TYPE_GROUP_APPROVE_OPT:
          final addOpt = info?.intValue;
          GroupJoinOption groupInviteOption;
          if (addOpt == GroupAddOptType.V2TIM_GROUP_ADD_FORBID) {
            groupInviteOption = GroupJoinOption.forbid;
          } else if (addOpt == GroupAddOptType.V2TIM_GROUP_ADD_AUTH) {
            groupInviteOption = GroupJoinOption.auth;
          } else if (addOpt == GroupAddOptType.V2TIM_GROUP_ADD_ANY) {
            groupInviteOption = GroupJoinOption.any;
          } else {
            groupInviteOption = GroupJoinOption.any; // 默认值
          }

          results.add(ChangeInviteToGroupApprovalSystemMessage(
            groupID: groupID,
            groupInviteApprovalOperator: opUser,
            groupInviteOption: groupInviteOption,
          ));
          break;

        default:
          break;
      }
    }

    return results;
  }

  static dynamic dictionary2JsonData(Map<String, dynamic>? dictionary) {
    if (dictionary == null) return null;
    try {
      return jsonEncode(dictionary);
    } catch (e) {
      if (kDebugMode) {
        print("jsonEncode failed: $e");
      }
      return null;
    }
  }

  static Map<String, dynamic>? jsonData2Dictionary(dynamic jsonData) {
    if (jsonData == null) return null;
    try {
      if (jsonData is String) {
        return jsonDecode(jsonData) as Map<String, dynamic>;
      } else if (jsonData is List<int>) {
        final jsonString = utf8.decode(jsonData);
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print("jsonEncode failed: $e");
      }
      return null;
    }
  }

  static String? convertDateToHMStr(DateTime? date) {
    if (date == null || date == DateTime.fromMillisecondsSinceEpoch(0)) {
      return null;
    }

    return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }

  // MARK: - Message Read Receipt Conversion

  static MessageReceipt convertToMessageReceipt(V2TimMessageReceipt v2Receipt) {
    return MessageReceipt(
      isPeerRead: v2Receipt.isPeerRead ?? false,
      readCount: v2Receipt.readCount ?? 0,
      unreadCount: v2Receipt.unreadCount ?? 0,
    );
  }

  // MARK: - Message Reaction Conversion

  static List<MessageReaction> convertToMessageReactions(List<V2TimMessageReaction>? v2Reactions) {
    if (v2Reactions == null) return [];

    List<MessageReaction> reactions = [];
    for (final v2Reaction in v2Reactions) {
      final reaction = MessageReaction(
        reactionID: v2Reaction.reactionID,
        totalUserCount: v2Reaction.totalUserCount,
        reactedByMyself: v2Reaction.reactedByMyself,
        partialUserList: v2Reaction.partialUserList.map((v2UserInfo) => convertToUserProfile(v2UserInfo)).toList(),
      );
      reactions.add(reaction);
    }
    return reactions;
  }

  // MARK: - Message Extension Conversion

  static List<MessageExtension> convertToMessageExtensions(List<V2TimMessageExtension>? v2Extensions) {
    if (v2Extensions == null) return [];

    return v2Extensions
        .map((ext) => MessageExtension(
              extensionKey: ext.extensionKey,
              extensionValue: ext.extensionValue,
            ))
        .toList();
  }

  // MARK: - User Profile Conversion

  static UserProfile convertToUserProfile(V2TimUserInfo v2UserInfo) {
    return UserProfile(
      userID: v2UserInfo.userID,
      nickname: v2UserInfo.nickName,
      avatarURL: v2UserInfo.faceUrl,
    );
  }

  static UserProfile convertToUserFullProfile(V2TimUserFullInfo v2UserInfo) {
    return UserProfile(
      userID: v2UserInfo.userID ?? "",
      nickname: v2UserInfo.nickName,
      avatarURL: v2UserInfo.faceUrl,
      gender: convertToGender(v2UserInfo.gender),
      birthday: v2UserInfo.birthday,
      level: v2UserInfo.level,
      role: v2UserInfo.role,
      selfSignature: v2UserInfo.selfSignature,
      allowType: _convertToAllowType(v2UserInfo.allowType),
      customInfo: v2UserInfo.customInfo,
    );
  }

  static Gender convertToGender(int? gender) {
    if (gender == null) return Gender.unknown;
    switch (gender) {
      case 1:
        return Gender.male;
      case 2:
        return Gender.female;
      default:
        return Gender.unknown;
    }
  }

  static int convertGenderToInt(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 1; // V2TIM_GENDER_MALE
      case Gender.female:
        return 2; // V2TIM_GENDER_FEMALE
      case Gender.unknown:
        return 0; // V2TIM_GENDER_UNKNOWN
    }
  }

  static AllowType? _convertToAllowType(int? allowType) {
    if (allowType == null) return null;
    switch (allowType) {
      case 0:
        return AllowType.allowAny;
      case 1:
        return AllowType.needConfirm;
      case 2:
        return AllowType.denyAny;
      default:
        return AllowType.allowAny;
    }
  }

  // MARK: - Group Join Option Conversion

  static GroupJoinOption convertGroupAddOptToJoinOption(int? groupAddOpt) {
    switch (groupAddOpt) {
      case GroupAddOptType.V2TIM_GROUP_ADD_FORBID:
        return GroupJoinOption.forbid;
      case GroupAddOptType.V2TIM_GROUP_ADD_AUTH:
        return GroupJoinOption.auth;
      case GroupAddOptType.V2TIM_GROUP_ADD_ANY:
        return GroupJoinOption.any;
      default:
        return GroupJoinOption.forbid;
    }
  }

  static GroupJoinOption convertApproveOptToInviteOption(int? approveOpt) {
    switch (approveOpt) {
      case GroupAddOptType.V2TIM_GROUP_ADD_FORBID:
        return GroupJoinOption.forbid;
      case GroupAddOptType.V2TIM_GROUP_ADD_AUTH:
        return GroupJoinOption.auth;
      case GroupAddOptType.V2TIM_GROUP_ADD_ANY:
        return GroupJoinOption.any;
      default:
        return GroupJoinOption.forbid;
    }
  }

  // MARK: - Group Member Conversion

  static GroupMember convertToGroupMember(V2TimGroupMemberInfo v2Member) {
    return GroupMember(
      userID: v2Member.userID ?? "",
      nickname: v2Member.nickName,
      avatarURL: v2Member.faceUrl,
      nameCard: v2Member.nameCard,
    );
  }


  static ReceiveMessageOpt convertToReceiveMessageOpt(int v2Opt) {
    switch (v2Opt) {
      case 0: // V2TIM_RECEIVE_MESSAGE
        return ReceiveMessageOpt.receive;
      case 1: // V2TIM_NOT_RECEIVE_MESSAGE
        return ReceiveMessageOpt.notReceive;
      case 2: // V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE
        return ReceiveMessageOpt.notNotify;
      case 3: // V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE_EXCEPT_AT
        return ReceiveMessageOpt.notNotifyExceptMention;
      case 4: // V2TIM_NOT_RECEIVE_MESSAGE_EXCEPT_AT
        return ReceiveMessageOpt.notReceiveExceptMention;
      default:
        return ReceiveMessageOpt.receive;
    }
  }

  static ReceiveMsgOptEnum convertToV2TIMReceiveMessageOpt(ReceiveMessageOpt opt) {
    switch (opt) {
      case ReceiveMessageOpt.receive:
        return ReceiveMsgOptEnum.V2TIM_RECEIVE_MESSAGE;
      case ReceiveMessageOpt.notReceive:
        return ReceiveMsgOptEnum.V2TIM_NOT_RECEIVE_MESSAGE;
      case ReceiveMessageOpt.notNotify:
        return ReceiveMsgOptEnum.V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE;
      case ReceiveMessageOpt.notNotifyExceptMention:
        return ReceiveMsgOptEnum.V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE_EXCEPT_AT;
      case ReceiveMessageOpt.notReceiveExceptMention:
        return ReceiveMsgOptEnum.V2TIM_NOT_RECEIVE_MESSAGE_EXCEPT_AT;
    }
  }
}
