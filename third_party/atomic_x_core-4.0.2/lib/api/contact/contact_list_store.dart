import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/contact/contact_list_store_impl.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_application.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_application.dart';

enum ContactOnlineStatus {
  unknown,
  online,
  offline,
}

enum ContactType {
  unknown,
  user,
  group,
}

enum FriendApplicationType {
  received,
  sent,
  both,
}

enum GroupApplicationType {
  joinApprovedByAdmin,
  inviteApprovedByInvitee,
  inviteApprovedByAdmin,
}

enum GroupApplicationHandledStatus {
  unhandled,
  byOther,
  byMyself,
}

enum GroupApplicationHandledResult {
  refused,
  agreed,
}

class ContactInfo {
  final String contactID;
  final ContactType type;
  String? avatarURL;
  String? title;
  final bool? isContact;
  final bool? isInGroup;
  final ContactOnlineStatus onlineStatus;

  ContactInfo({
    required this.contactID,
    required this.type,
    this.avatarURL,
    this.title,
    this.isContact,
    this.isInGroup,
    this.onlineStatus = ContactOnlineStatus.unknown,
  });
}

class FriendApplicationInfo {
  final V2TimFriendApplication application;
  final String applicationID;
  final String? avatarURL;
  final String? title;
  final String? source;
  final FriendApplicationType type;
  final String? addWording;

  const FriendApplicationInfo({
    required this.application,
    required this.applicationID,
    this.avatarURL,
    this.title,
    this.source,
    required this.type,
    this.addWording,
  });
}

class GroupApplicationInfo {
  final V2TimGroupApplication application;
  final String applicationID;
  final String groupID;
  final String? fromUser;
  final String? fromUserNickname;
  final String? fromUserAvatarURL;
  final String? toUser;
  final int addTime;
  final String? requestMsg;
  final String? handledMsg;
  final GroupApplicationType type;
  GroupApplicationHandledStatus? handledStatus;
  GroupApplicationHandledResult? handledResult;

  GroupApplicationInfo({
    required this.application,
    required this.applicationID,
    required this.groupID,
    this.fromUser,
    this.fromUserNickname,
    this.fromUserAvatarURL,
    this.toUser,
    this.addTime = 0,
    this.requestMsg,
    this.handledMsg,
    required this.type,
    this.handledStatus,
    this.handledResult,
  });
}

class ContactListState {
  final List<ContactInfo> blackList;
  final List<ContactInfo> friendList;
  final List<ContactInfo> groupList;
  final List<FriendApplicationInfo> friendApplicationList;
  final List<GroupApplicationInfo> groupApplicationList;
  final int friendApplicationUnreadCount;
  final int groupApplicationUnreadCount;
  final String createdGroupID;
  final ContactInfo? addFriendInfo;
  final ContactInfo? joinGroupInfo;

  const ContactListState({
    required this.blackList,
    required this.friendList,
    required this.groupList,
    required this.friendApplicationList,
    required this.groupApplicationList,
    this.friendApplicationUnreadCount = 0,
    this.groupApplicationUnreadCount = 0,
    this.createdGroupID = '',
    this.addFriendInfo,
    this.joinGroupInfo,
  });
}

abstract class ContactListStore extends ChangeNotifier {
  static ContactListStore create() {
    return ContactListStoreImpl();
  }

  ContactListState get contactListState;

  Future<CompletionHandler> fetchJoinedGroupList();

  Future<CompletionHandler> fetchFriendList();

  Future<CompletionHandler> fetchBlackList();

  Future<CompletionHandler> fetchFriendApplicationList();

  Future<CompletionHandler> acceptFriendApplication({required FriendApplicationInfo info});

  Future<CompletionHandler> refuseFriendApplication({required FriendApplicationInfo info});

  Future<CompletionHandler> clearFriendApplicationUnreadCount();

  Future<CompletionHandler> joinGroup({required String groupID, String? message});

  Future<CompletionHandler> fetchGroupApplicationList();

  Future<CompletionHandler> acceptGroupApplication({required GroupApplicationInfo info});

  Future<CompletionHandler> refuseGroupApplication({required GroupApplicationInfo info});

  Future<CompletionHandler> clearGroupApplicationUnreadCount();

  Future<CompletionHandler> fetchUserInfo({required String userID});

  Future<CompletionHandler> fetchGroupInfo({required String groupID});

  Future<CompletionHandler> addFriend({required String userID, String? remark, String? addWording});

  Future<CompletionHandler> createGroup(
      {required String groupType,
      String? groupID,
      required String groupName,
      String? avatarURL,
      List<ContactInfo>? memberList});
}
