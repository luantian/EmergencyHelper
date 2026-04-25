import 'dart:async';

import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/api/message/message_input_store.dart';
import 'package:atomic_x_core/api/message/message_list_store.dart';
import 'package:atomic_x_core/impl/common/chat_util.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';
import 'package:atomic_x_core/impl/common/notification_center.dart';
import 'package:atomic_x_core/impl/login/login_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:flutter/cupertino.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart' as sdk;
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_imsdk_bindings_generated.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class MessageSendNotifyKey {
  static const String messageSendBegin = 'message_send_begin';
  static const String messageSendProgress = 'message_send_progress';
  static const String messageSendSuccess = 'message_send_success';
  static const String messageSendFailed = 'message_send_failed';
}

class MessageInputStoreImpl extends MessageInputStore {
  String conversationID;

  MessageInputStoreImpl(this.conversationID);

  @override
  Future<CompletionHandler> sendMessage({required MessageInfo message}) async {
    return await _sendMessageInternal(message);
  }

  Future<CompletionHandler> _sendMessageInternal(MessageInfo message) async {
    DataReport.reportAtomicMetrics(AtomicMetrics.messageInput);

    final handler = CompletionHandler();

    var imMessage = message.rawMessage;
    imMessage ??= await _createIMMessage(message);

    if (imMessage == null) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Failed to create im message";
      return handler;
    }

    imMessage.needReadReceipt = message.needReadReceipt;
    imMessage.isSupportMessageExtension = message.supportExtension;

    final receiver = ChatUtil.getUserID(conversationID);
    final groupID = ChatUtil.getGroupID(conversationID);
    final imPushInfo = _convertToOfflinePushInfo(message.offlinePushInfo);

    var copyMessage = message;
    copyMessage.isSelf = true;
    copyMessage.rawMessage = imMessage;
    copyMessage.timestamp = imMessage.timestamp;
    copyMessage.status = MessageStatus.sending;

    final userInfo = LoginStoreImpl.instance.loginState.loginUserInfo;
    if (userInfo != null) {
      MessageSenderInfo sender = MessageSenderInfo();
      sender.userID = userInfo.userID;
      sender.avatarURL = userInfo.avatarURL;
      sender.nickname = userInfo.nickname;
      copyMessage.sender = sender;
      // flutter sdk need set sender
      copyMessage.rawMessage!.sender = userInfo.userID;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().sendMessage(
          message: imMessage,
          receiver: receiver,
          groupID: groupID,
          priority: MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
          onlineUserOnly: false,
          offlinePushInfo: imPushInfo,
          onSyncMsgID: (String syncMsgID) {
            copyMessage.msgID = syncMsgID;
            copyMessage.rawMessage?.msgID = syncMsgID;

            notificationCenter.post(MessageSendNotifyKey.messageSendBegin,
                MessageSendEventData(conversationID: conversationID, message: copyMessage));
          },
        );

    if (result.code == 0 && result.data != null) {
      copyMessage.rawMessage = result.data;
      notificationCenter.post(MessageSendNotifyKey.messageSendSuccess,
          MessageSendEventData(conversationID: conversationID, message: copyMessage));
    } else {
      copyMessage.rawMessage = result.data;
      notificationCenter.post(
          MessageSendNotifyKey.messageSendFailed,
          MessageSendEventData(
              conversationID: conversationID, message: copyMessage, code: result.code, desc: result.desc));

      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  Future<V2TimMessage?> _createIMMessage(MessageInfo message) async {
    if (message.messageBody == null) {
      return null;
    }

    final messageBody = message.messageBody!;
    V2TimMessage? imMsg;

    switch (message.messageType) {
      case MessageType.text:
        if (messageBody.text != null) {
          final createResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createTextMessage(
                text: messageBody.text!,
              );
          imMsg = createResult.data?.messageInfo;
          // Support @ mention for group messages
          if (createResult.code == 0 && createResult.data?.messageInfo != null && message.atUserList.isNotEmpty) {
            final textMessage = createResult.data!.messageInfo!;
            final atResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createAtSignedGroupMessage(
                  message: textMessage,
                  atUserList: message.atUserList,
                );

            if (atResult.code == 0 && atResult.data?.messageConvID != null) {
              imMsg = atResult.data;
            }
          }
        }
        break;

      case MessageType.image:
        if (messageBody.originalImagePath != null) {
          final createResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createImageMessage(
                imagePath: messageBody.originalImagePath!,
              );
          imMsg = createResult.data?.messageInfo;
        } else {
          debugPrint("message image, path:${messageBody.originalImagePath}");
        }
        break;

      case MessageType.sound:
        if (messageBody.soundPath != null) {
          final createResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createSoundMessage(
                soundPath: messageBody.soundPath!,
                duration: messageBody.soundDuration,
              );
          imMsg = createResult.data?.messageInfo;
        } else {
          debugPrint("message sound, path:${messageBody.soundPath}");
        }
        break;

      case MessageType.file:
        if (messageBody.filePath != null && messageBody.fileName != null) {
          final createResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createFileMessage(
                filePath: messageBody.filePath!,
                fileName: messageBody.fileName!,
              );
          imMsg = createResult.data?.messageInfo;
        } else {
          debugPrint("message file, path:${messageBody.filePath}, fileName:${messageBody.fileName}");
        }
        break;

      case MessageType.video:
        if (messageBody.videoPath != null && messageBody.videoSnapshotPath != null && messageBody.videoType != null) {
          final createResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createVideoMessage(
                videoFilePath: messageBody.videoPath!,
                type: messageBody.videoType!,
                duration: messageBody.videoDuration,
                snapshotPath: messageBody.videoSnapshotPath!,
              );
          imMsg = createResult.data?.messageInfo;
        } else {
          debugPrint(
              "message video, path:${messageBody.videoPath}, snapshotPath:${messageBody.videoSnapshotPath}, videoType:${messageBody.videoType}");
        }
        break;

      case MessageType.face:
        if (messageBody.faceName != null) {
          final createResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createFaceMessage(
                index: messageBody.faceIndex,
                data: messageBody.faceName!,
              );
          imMsg = createResult.data?.messageInfo;
        }
        break;

      case MessageType.custom:
        final customMessage = messageBody.customMessage;
        if (customMessage != null && customMessage.data != null) {
          final createResult = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createCustomMessage(
                data: customMessage.data!,
                desc: customMessage.description ?? '',
                extension: customMessage.extensionInfo ?? '',
              );
          imMsg = createResult.data?.messageInfo;
        }
        break;

      default:
        return null;
    }

    return imMsg;
  }

  sdk.OfflinePushInfo? _convertToOfflinePushInfo(OfflinePushInfo? offlinePushInfo) {
    if (offlinePushInfo == null) {
      return null;
    }

    final imPushInfo = sdk.OfflinePushInfo();
    imPushInfo.title = offlinePushInfo.title;
    imPushInfo.desc = offlinePushInfo.description;

    final extensionInfo = offlinePushInfo.extensionInfo;

    // String
    if (extensionInfo['ext'] is String) {
      imPushInfo.ext = extensionInfo['ext'] as String;
    }
    if (extensionInfo['iOSSound'] is String) {
      imPushInfo.iOSSound = extensionInfo['iOSSound'] as String;
    }
    if (extensionInfo['iOSInterruptionLevel'] is String) {
      imPushInfo.iOSInterruptionLevel = extensionInfo['iOSInterruptionLevel'] as String;
    }
    if (extensionInfo['iOSImage'] is String) {
      imPushInfo.iOSImage = extensionInfo['iOSImage'] as String;
    }
    if (extensionInfo['AndroidSound'] is String) {
      imPushInfo.androidSound = extensionInfo['AndroidSound'] as String;
    }
    if (extensionInfo['AndroidOPPOChannelID'] is String) {
      imPushInfo.androidOPPOChannelID = extensionInfo['AndroidOPPOChannelID'] as String;
    }
    if (extensionInfo['AndroidFCMChannelID'] is String) {
      imPushInfo.androidFCMChannelID = extensionInfo['AndroidFCMChannelID'] as String;
    }
    if (extensionInfo['AndroidXiaoMiChannelID'] is String) {
      imPushInfo.androidXiaoMiChannelID = extensionInfo['AndroidXiaoMiChannelID'] as String;
    }
    if (extensionInfo['AndroidVIVOCategory'] is String) {
      imPushInfo.androidVIVOCategory = extensionInfo['AndroidVIVOCategory'] as String;
    }
    if (extensionInfo['AndroidHuaWeiCategory'] is String) {
      imPushInfo.androidHuaWeiCategory = extensionInfo['AndroidHuaWeiCategory'] as String;
    }
    if (extensionInfo['AndroidOPPOCategory'] is String) {
      imPushInfo.androidOPPOCategory = extensionInfo['AndroidOPPOCategory'] as String;
    }
    if (extensionInfo['AndroidHonorImportance'] is String) {
      imPushInfo.androidHonorImportance = extensionInfo['AndroidHonorImportance'] as String;
    }
    if (extensionInfo['AndroidHuaWeiImage'] is String) {
      imPushInfo.androidHuaWeiImage = extensionInfo['AndroidHuaWeiImage'] as String;
    }
    if (extensionInfo['AndroidHonorImage'] is String) {
      imPushInfo.androidHonorImage = extensionInfo['AndroidHonorImage'] as String;
    }
    if (extensionInfo['AndroidFCMImage'] is String) {
      imPushInfo.androidFCMImage = extensionInfo['AndroidFCMImage'] as String;
    }
    if (extensionInfo['HarmonyImage'] is String) {
      imPushInfo.harmonyImage = extensionInfo['HarmonyImage'] as String;
    }
    if (extensionInfo['HarmonyCategory'] is String) {
      imPushInfo.harmonyCategory = extensionInfo['HarmonyCategory'] as String;
    }

    // Bool
    if (extensionInfo['disablePush'] is bool) {
      imPushInfo.disablePush = extensionInfo['disablePush'] as bool;
    }
    if (extensionInfo['ignoreIOSBadge'] is bool) {
      imPushInfo.ignoreIOSBadge = extensionInfo['ignoreIOSBadge'] as bool;
    }
    if (extensionInfo['enableIOSBackgroundNotification'] is bool) {
      imPushInfo.enableIOSBackgroundNotification = extensionInfo['enableIOSBackgroundNotification'] as bool;
    }
    if (extensionInfo['ignoreHarmonyBadge'] is bool) {
      imPushInfo.ignoreHarmonyBadge = extensionInfo['ignoreHarmonyBadge'] as bool;
    }

    // Int
    if (extensionInfo['AndroidVIVOClassification'] is int) {
      imPushInfo.androidVIVOClassification = extensionInfo['AndroidVIVOClassification'] as int;
    }
    if (extensionInfo['AndroidOPPONotifyLevel'] is int) {
      imPushInfo.androidOPPONotifyLevel = extensionInfo['AndroidOPPONotifyLevel'] as int;
    }
    if (extensionInfo['AndroidMeizuNotifyType'] is int) {
      imPushInfo.androidMeizuNotifyType = extensionInfo['AndroidMeizuNotifyType'] as int;
    }
    if (extensionInfo['iOSPushType'] is int) {
      imPushInfo.iOSPushType = extensionInfo['iOSPushType'] as int;
    }

    return imPushInfo;
  }
}
