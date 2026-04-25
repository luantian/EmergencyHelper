import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/api/contact/c2c_setting_store.dart';
import 'package:atomic_x_core/impl/contact/group_setting_store_impl.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role_enum.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';

enum GroupType {
  work('Work'),
  publicGroup('Public'),
  meeting('Meeting'),
  avChatRoom('AVChatRoom'),
  community('Community');

  const GroupType(this.value);

  final String value;

  static GroupType fromV2TIMType(String type) {
    return GroupType.values.firstWhere(
      (e) => e.value == type,
      orElse: () => GroupType.work,
    );
  }
}

enum GroupJoinOption {
  forbid,
  auth,
  any,
}

enum GroupMemberRole {
  all(0),
  member(1),
  admin(2),
  owner(3);

  const GroupMemberRole(this.value);

  final int value;

  GroupMemberRoleTypeEnum get v2TIMRole {
    switch (this) {
      case GroupMemberRole.member:
        return GroupMemberRoleTypeEnum.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
      case GroupMemberRole.admin:
        return GroupMemberRoleTypeEnum.V2TIM_GROUP_MEMBER_ROLE_ADMIN;
      case GroupMemberRole.owner:
        return GroupMemberRoleTypeEnum.V2TIM_GROUP_MEMBER_ROLE_OWNER;
      default:
        return GroupMemberRoleTypeEnum.V2TIM_GROUP_MEMBER_UNDEFINED;
    }
  }

  static GroupMemberRole fromV2TIMRole(int role) {
    switch (role) {
      case GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER:
        return GroupMemberRole.owner;
      case GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN:
        return GroupMemberRole.admin;
      default:
        return GroupMemberRole.member;
    }
  }
}

class GroupMember {
  final String userID;
  String? nickname;
  String? avatarURL;
  String? nameCard;
  GroupMemberRole role;
  int muteUntil;

  GroupMember({
    required this.userID,
    this.nickname,
    this.avatarURL,
    this.nameCard,
    this.role = GroupMemberRole.member,
    this.muteUntil = 0,
  });

  bool get isMuted {
    if (muteUntil == 0) return false;
    final currentTime = TIMManager.instance.getServerTime();
    return muteUntil > currentTime;
  }
}

class GroupSettingState {
  final String avatarURL;
  final bool isNotDisturb;
  final bool isPinned;
  final GroupType groupType;
  final String groupName;
  final String notice;
  final bool isAllMuted;
  final GroupMember? groupOwner;
  final List<GroupMember> allMembers;
  final List<GroupMember>? membersInfo;
  final GroupMemberRole currentUserRole;
  final String selfNameCard;
  final int memberCount;
  final GroupJoinOption joinGroupApprovalType;
  final GroupJoinOption inviteToGroupApprovalType;
  final bool hasMoreGroupMembers;
  final ReceiveMessageOpt receiveMessageOpt;
  final Map<String, String>? groupAttributes;

  const GroupSettingState({
    this.avatarURL = '',
    this.isNotDisturb = false,
    this.isPinned = false,
    this.groupType = GroupType.work,
    this.groupName = '',
    this.notice = '',
    this.isAllMuted = false,
    this.groupOwner,
    required this.allMembers,
    this.membersInfo,
    this.currentUserRole = GroupMemberRole.member,
    this.selfNameCard = '',
    this.memberCount = 0,
    this.joinGroupApprovalType = GroupJoinOption.forbid,
    this.inviteToGroupApprovalType = GroupJoinOption.forbid,
    this.hasMoreGroupMembers = false,
    this.receiveMessageOpt = ReceiveMessageOpt.receive,
    this.groupAttributes,
  });
}

abstract class GroupSettingStore extends ChangeNotifier {
  static GroupSettingStore create({required String groupID}) {
    return GroupSettingStoreImpl(groupID);
  }

  GroupSettingState get groupSettingState;

  String get groupID;

  Future<CompletionHandler> fetchGroupInfo();

  Future<CompletionHandler> fetchSelfMemberInfo();

  Future<CompletionHandler> fetchGroupMemberList({required GroupMemberRole role});

  Future<CompletionHandler> fetchMoreGroupMemberList();

  Future<CompletionHandler> fetchGroupMembersInfo({required List<String> userIDList});

  Future<CompletionHandler> fetchGroupAttributes({List<String>? keys});

  Future<CompletionHandler> updateGroupProfile({String? name, String? notice, String? avatar});

  Future<CompletionHandler> setGroupJoinOption({required GroupJoinOption option});

  Future<CompletionHandler> setGroupInviteOption({required GroupJoinOption option});

  Future<CompletionHandler> addGroupMember({required List<String> userIDList});

  Future<CompletionHandler> deleteGroupMember({required List<GroupMember> members});

  Future<CompletionHandler> changeGroupOwner({required String newOwnerID});

  Future<CompletionHandler> setGroupMemberRole({required String userID, required GroupMemberRole role});

  Future<CompletionHandler> setGroupMemberMuteTime({required String userID, required int time});

  Future<CompletionHandler> setMuteAllMembers({required bool isMuted});

  Future<CompletionHandler> setSelfGroupNameCard({required String nameCard});

  Future<CompletionHandler> setReceiveMessageOpt({required ReceiveMessageOpt opt});

  Future<CompletionHandler> dismissGroup();

  Future<CompletionHandler> quitGroup();
}
