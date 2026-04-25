import 'dart:async';

import 'package:atomic_x_core/api/contact/c2c_setting_store.dart';
import 'package:atomic_x_core/api/contact/group_setting_store.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/common/chat_util.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';
import 'package:atomic_x_core/impl/common/notification_center.dart';
import 'package:atomic_x_core/impl/conversation/conversation_list_store_impl.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimConversationListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimFriendshipListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimGroupListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_add_opt_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_filter_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/receive_message_opt_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_change_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_change_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_imsdk_bindings_generated.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class GroupSettingStoreImpl extends GroupSettingStore {
  final String _groupID;
  GroupType _groupType = GroupType.work;
  String _groupName = '';
  String _avatar = '';
  String _notice = '';
  String _selfNameCard = '';
  bool _isNotDisturb = false;
  bool _isAllMuted = false;
  bool _isPinned = false;
  int _memberCount = 0;
  GroupJoinOption _joinGroupApprovalType = GroupJoinOption.forbid;
  GroupJoinOption _inviteToGroupApprovalType = GroupJoinOption.forbid;
  GroupMember? _groupOwner;
  List<GroupMember> _allMembers = [];
  List<GroupMember> _membersInfo = [];
  GroupMemberRole _currentUserRole = GroupMemberRole.member;
  bool _hasMoreGroupMember = false;
  ReceiveMessageOpt _receiveMessageOpt = ReceiveMessageOpt.receive;
  Map<String, String>? _groupAttributes;

  GroupSettingState? _groupSettingState;
  bool _needUpdate = true;

  String _memberNextSeq = '0';
  GroupMemberRole _memberRole = GroupMemberRole.all;

  @override
  String get groupID => _groupID;

  String get conversationID => "$groupConversationIDPrefix$groupID";
  String _currentUserID = "";
  V2TimGroupListener? _groupListener;
  V2TimConversationListener? _conversationListener;
  V2TimFriendshipListener? _friendshipListener;

  late ConversationListStoreImpl conversationListStoreImpl;
  late List<StreamSubscription> _eventSubscriptions;

  GroupSettingStoreImpl(this._groupID) {
    conversationListStoreImpl = ConversationListStoreImpl();
    _initCurrentUser();
    _addGroupListener();
    _addConversationListener();
    _addFriendshipListenerInternal();
    _addNotificationListeners();
  }

  @override
  void dispose() {
    conversationListStoreImpl.dispose();
    _removeGroupListener();
    _removeConversationListener();
    _removeFriendshipListener();
    _removeNotificationListeners();
    super.dispose();
  }

  void _addNotificationListeners() {
    _eventSubscriptions = [
      notificationCenter.addListener<ConversationMuteEventData>(
          ConversationNotificationNames.conversationMute, _handleConversationMute),
    ];
  }

  void _removeNotificationListeners() {
    for (var subscription in _eventSubscriptions) {
      subscription.cancel();
    }

    _eventSubscriptions.clear();
  }

  @override
  GroupSettingState get groupSettingState {
    if (_needUpdate || _groupSettingState == null) {
      _groupSettingState = GroupSettingState(
        avatarURL: _avatar,
        isNotDisturb: _isNotDisturb,
        isPinned: _isPinned,
        groupType: _groupType,
        groupName: _groupName,
        notice: _notice,
        isAllMuted: _isAllMuted,
        groupOwner: _groupOwner,
        allMembers: List.unmodifiable(_allMembers),
        membersInfo: List.unmodifiable(_membersInfo),
        currentUserRole: _currentUserRole,
        selfNameCard: _selfNameCard,
        memberCount: _memberCount,
        joinGroupApprovalType: _joinGroupApprovalType,
        inviteToGroupApprovalType: _inviteToGroupApprovalType,
        hasMoreGroupMembers: _hasMoreGroupMember,
        receiveMessageOpt: _receiveMessageOpt,
        groupAttributes: _groupAttributes,
      );
      _needUpdate = false;
    }

    return _groupSettingState!;
  }

  void _markNeedUpdate() {
    _needUpdate = true;
    notifyListeners();
  }

  @override
  Future<CompletionHandler> fetchGroupInfo() async {
    DataReport.reportAtomicMetrics(AtomicMetrics.groupSetting);

    return _fetchGroupInfo();
  }

  @override
  Future<CompletionHandler> fetchSelfMemberInfo() async {
    return _fetchSelfMemberInfo();
  }

  @override
  Future<CompletionHandler> fetchGroupMemberList({required GroupMemberRole role}) async {
    return _fetchGroupMembersInternal(role: role, nextSeq: '0');
  }

  @override
  Future<CompletionHandler> fetchMoreGroupMemberList() async {
    if (!_hasMoreGroupMember) {
      return CompletionHandler();
    }

    return _fetchGroupMembersInternal(role: _memberRole, nextSeq: _memberNextSeq);
  }

  @override
  Future<CompletionHandler> fetchGroupMembersInfo({required List<String> userIDList}) async {
    return _fetchGroupMembersInfoInternal(userIDList: userIDList);
  }

  @override
  Future<CompletionHandler> fetchGroupAttributes({List<String>? keys}) async {
    return _fetchGroupAttributesInternal(keys: keys);
  }

  @override
  Future<CompletionHandler> updateGroupProfile({
    String? name,
    String? notice,
    String? avatar,
  }) async {
    return _updateGroupProfileInternal(name: name, notice: notice, faceUrl: avatar);
  }

  @override
  Future<CompletionHandler> setGroupJoinOption({required GroupJoinOption option}) async {
    return _setGroupJoinOptionInternal(option: option);
  }

  @override
  Future<CompletionHandler> setGroupInviteOption({required GroupJoinOption option}) async {
    return _setGroupInviteOptionInternal(option: option);
  }

  @override
  Future<CompletionHandler> addGroupMember({required List<String> userIDList}) async {
    return _addGroupMemberInternal(userIDList: userIDList);
  }

  @override
  Future<CompletionHandler> deleteGroupMember({required List<GroupMember> members}) async {
    return _deleteGroupMemberInternal(members: members);
  }

  @override
  Future<CompletionHandler> changeGroupOwner({required String newOwnerID}) async {
    return _changeGroupOwnerInternal(newOwnerID: newOwnerID);
  }

  @override
  Future<CompletionHandler> setGroupMemberRole({
    required String userID,
    required GroupMemberRole role,
  }) async {
    return _setGroupMemberRoleInternal(userID: userID, role: role);
  }

  @override
  Future<CompletionHandler> setGroupMemberMuteTime({
    required String userID,
    required int time,
  }) async {
    return _setGroupMemberMuteTimeInternal(userID: userID, time: time);
  }

  @override
  Future<CompletionHandler> setMuteAllMembers({required bool isMuted}) async {
    return _setMuteAllMemberInternal(isMuted: isMuted);
  }

  @override
  Future<CompletionHandler> setSelfGroupNameCard({required String nameCard}) async {
    return _setSelfGroupNameCardInternal(nameCard: nameCard);
  }

  @override
  Future<CompletionHandler> setReceiveMessageOpt({required ReceiveMessageOpt opt}) async {
    return _setReceiveMessageOptInternal(opt: opt);
  }

  @override
  Future<CompletionHandler> dismissGroup() async {
    return _dismissGroupInternal();
  }

  @override
  Future<CompletionHandler> quitGroup() async {
    return _quitGroupInternal();
  }

  void _addGroupListener() {
    _groupListener = V2TimGroupListener(
      onMemberEnter: (String groupID, List<V2TimGroupMemberInfo> memberList) {
        if (groupID == this.groupID) {
          _addMembersLocally(memberList);
        }
      },
      onMemberLeave: (String groupID, V2TimGroupMemberInfo member) {
        if (groupID == this.groupID) {
          _removeMemberLocally(member);
        }
      },
      onMemberInvited: (String groupID, V2TimGroupMemberInfo opUser, List<V2TimGroupMemberInfo> memberList) {
        if (groupID == this.groupID) {
          _addMembersLocally(memberList);
        }
      },
      onMemberKicked: (String groupID, V2TimGroupMemberInfo opUser, List<V2TimGroupMemberInfo> memberList) {
        if (groupID == this.groupID) {
          _removeMembersLocally(memberList);
        }
      },
      onMemberInfoChanged: (String groupID, List<V2TimGroupMemberChangeInfo> changeInfos) {
        if (groupID == this.groupID) {
          _updateMembersInfoLocally(changeInfos);
        }
      },
      onGrantAdministrator: (String groupID, V2TimGroupMemberInfo opUser, List<V2TimGroupMemberInfo> memberList) {
        if (groupID == this.groupID) {
          _updateMemberRoleLocally(memberList, GroupMemberRole.admin);
        }
      },
      onRevokeAdministrator: (String groupID, V2TimGroupMemberInfo opUser, List<V2TimGroupMemberInfo> memberList) {
        if (groupID == this.groupID) {
          _updateMemberRoleLocally(memberList, GroupMemberRole.member);
        }
      },
      onGroupInfoChanged: (String groupID, List<V2TimGroupChangeInfo> changeInfos) {
        if (groupID == this.groupID) {
          _fetchGroupInfo();
        }
      },
      onGroupAttributeChanged: (
          String groupID,
          Map<String, String> groupAttributeMap,) {
        if (groupID == this.groupID) {
          _updateGroupAttributes(groupAttributeMap);
        }
      }
    );

    TencentImSDKPlugin.v2TIMManager.addGroupListener(listener: _groupListener!);
  }

  void _removeGroupListener() {
    if (_groupListener != null) {
      TencentImSDKPlugin.v2TIMManager.removeGroupListener(listener: _groupListener!);
      _groupListener = null;
    }
  }

  void _addConversationListener() {
    _conversationListener =
        V2TimConversationListener(onConversationChanged: (List<V2TimConversation> conversationList) {
      final existingIndex = conversationList.indexWhere((element) => element.conversationID == conversationID);
      if (existingIndex >= 0) {
        final conversation = conversationList[existingIndex];
        _isPinned = conversation.isPinned ?? false;
        _markNeedUpdate();
      }
    });

    TencentImSDKPlugin.v2TIMManager.getConversationManager().addConversationListener(listener: _conversationListener!);
  }

  void _removeConversationListener() {
    if (_conversationListener != null) {
      TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .removeConversationListener(listener: _conversationListener!);
      _conversationListener = null;
    }
  }

  void _addFriendshipListenerInternal() {
    _friendshipListener = V2TimFriendshipListener(
      onFriendInfoChanged: _onFriendInfoChanged,
    );

    TencentImSDKPlugin.v2TIMManager.getFriendshipManager().addFriendListener(listener: _friendshipListener!);
  }

  void _removeFriendshipListener() {
    if (_friendshipListener != null) {
      TencentImSDKPlugin.v2TIMManager.getFriendshipManager().removeFriendListener(listener: _friendshipListener);
    }
  }

  Future<void> _initCurrentUser() async {
    final result = await TencentImSDKPlugin.v2TIMManager.getLoginUser();
    if (result.code == 0 && result.data != null) {
      _currentUserID = result.data!;
    }
  }

  void _addMembersLocally(List<V2TimGroupMemberInfo> memberList) {
    for (final memberInfo in memberList) {
      final userID = memberInfo.userID;
      if (userID == null) continue;

      final existingIndex = _allMembers.indexWhere((member) => member.userID == userID);
      if (existingIndex == -1) {
        final newMember = _convertV2TimGroupMemberInfoToMember(memberInfo);
        _allMembers.add(newMember);
      }
    }

    _fetchGroupInfo();
    _markNeedUpdate();
  }

  void _removeMemberLocally(V2TimGroupMemberInfo memberInfo) {
    final userID = memberInfo.userID;
    if (userID == null) return;

    _allMembers.removeWhere((member) => member.userID == userID);
    _fetchGroupInfo();
    _markNeedUpdate();
  }

  void _removeMembersLocally(List<V2TimGroupMemberInfo> memberList) {
    for (final memberInfo in memberList) {
      final userID = memberInfo.userID;
      if (userID == null) continue;

      _allMembers.removeWhere((member) => member.userID == userID);
    }

    _fetchGroupInfo();
    _markNeedUpdate();
  }

  void _updateMembersInfoLocally(List<V2TimGroupMemberChangeInfo> changeInfos) async {
    bool hasChanges = false;

    for (final changeInfo in changeInfos) {
      final userID = changeInfo.userID;
      if (userID == null) continue;

      final memberIndex = _allMembers.indexWhere((member) => member.userID == userID);
      if (memberIndex != -1) {
        if (changeInfo.muteTime != null && changeInfo.muteTime! >= 0) {
          final result = await TencentImSDKPlugin.v2TIMManager.getServerTime();
          if (result.code == 0 && result.data != null && result.data! > 0) {
            _allMembers[memberIndex].muteUntil = result.data! + changeInfo.muteTime!;
            hasChanges = true;
          }
        }
      }
    }

    if (hasChanges) {
      _markNeedUpdate();
    }
  }

  GroupMember _convertV2TimGroupMemberInfoToMember(V2TimGroupMemberInfo memberInfo) {
    return GroupMember(
      userID: memberInfo.userID ?? "",
      nickname: memberInfo.nickName,
      avatarURL: memberInfo.faceUrl,
      nameCard: memberInfo.nameCard,
    );
  }

  void _updateMemberRoleLocally(List<V2TimGroupMemberInfo> memberList, GroupMemberRole newRole) {
    bool hasChanges = false;

    final allMemberMap = <String, GroupMember>{};
    for (final member in _allMembers) {
      allMemberMap[member.userID] = member;
    }

    for (final memberInfo in memberList) {
      GroupMember? groupMember = allMemberMap[memberInfo.userID];
      if (groupMember != null) {
        groupMember.role = newRole;
        hasChanges = true;
      }

      if (memberInfo.userID == _currentUserID) {
        _currentUserRole = newRole;
        hasChanges = true;
      }
    }

    if (hasChanges) {
      _markNeedUpdate();
    }
  }

  void _onFriendInfoChanged(List<V2TimFriendInfo> infoList) {
    bool hasChanges = false;

    final allMemberMap = <String, GroupMember>{};
    for (final member in _allMembers) {
      allMemberMap[member.userID] = member;
    }

    for (var friendInfo in infoList) {
      GroupMember? groupMember = allMemberMap[friendInfo.userID];
      if (groupMember != null && groupMember.nickname != friendInfo.userProfile?.nickName) {
        groupMember.nickname = friendInfo.userProfile?.nickName;
        hasChanges = true;
      }

      if (groupMember != null && groupMember.avatarURL != friendInfo.userProfile?.faceUrl) {
        groupMember.avatarURL = friendInfo.userProfile?.faceUrl;
        hasChanges = true;
      }
    }

    if (hasChanges) {
      _markNeedUpdate();
    }
  }

  Future<CompletionHandler> _fetchGroupInfo() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getGroupsInfo(groupIDList: [groupID]);

    if (result.code == 0 && result.data != null && result.data!.isNotEmpty) {
      final groupResult = result.data!.first;
      if (groupResult.resultCode == 0 && groupResult.groupInfo != null) {
        final groupInfo = groupResult.groupInfo!;
        _groupName = groupInfo.groupName ?? "";
        _avatar = groupInfo.faceUrl ?? "";
        _notice = groupInfo.notification ?? "";
        _groupType = GroupType.fromV2TIMType(groupInfo.groupType);
        _memberCount = groupInfo.memberCount ?? 0;
        _isAllMuted = groupInfo.isAllMuted ?? false;
        _joinGroupApprovalType = ChatUtil.convertGroupAddOptToJoinOption(groupInfo.groupAddOpt);
        _inviteToGroupApprovalType = ChatUtil.convertApproveOptToInviteOption(groupInfo.approveOpt);
        _receiveMessageOpt = ChatUtil.convertToReceiveMessageOpt(groupInfo.recvOpt ?? 0);
        _isNotDisturb = (_receiveMessageOpt == ReceiveMessageOpt.notNotify);
        _markNeedUpdate();

        CompletionHandler handler =
            await conversationListStoreImpl.fetchConversationInfo(conversationID: conversationID);
        if (handler.isSuccess) {
          final existingIndex = conversationListStoreImpl.conversationListState.conversationList
              .indexWhere((element) => element.conversationID == conversationID);
          if (existingIndex >= 0) {
            final conversationInfo = conversationListStoreImpl.conversationListState.conversationList[existingIndex];
            _isPinned = conversationInfo.isPinned;
          }
        }

        _markNeedUpdate();
      }
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  Future<CompletionHandler> _fetchSelfMemberInfo() async {
    final handler = CompletionHandler();

    if (_currentUserID.isEmpty) {
      await _initCurrentUser();
    }

    if (_currentUserID.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "_currentUserID is empty";
      return handler;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getGroupMembersInfo(
      groupID: groupID,
      memberList: [_currentUserID],
    );

    if (result.code == 0 && result.data != null && result.data!.isNotEmpty) {
      final memberInfo = result.data!.first;
      _selfNameCard = memberInfo.nameCard ?? "";

      _currentUserRole = GroupMemberRole.fromV2TIMRole(memberInfo.role ?? 0);

      _markNeedUpdate();
    } else {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
    }

    return handler;
  }

  GroupMember _convertToMember(V2TimGroupMemberFullInfo v2Member) {
    return GroupMember(
      userID: v2Member.userID,
      nickname: v2Member.nickName,
      avatarURL: v2Member.faceUrl,
      nameCard: v2Member.nameCard,
      role: GroupMemberRole.fromV2TIMRole(v2Member.role ?? 0),
      muteUntil: v2Member.muteUntil ?? 0,
    );
  }

  Future<CompletionHandler> _fetchGroupMembersInternal({required GroupMemberRole role, required String nextSeq}) async {
    final handler = CompletionHandler();

    _memberRole = role;
    _memberNextSeq = nextSeq;

    GroupMemberFilterTypeEnum filter;
    switch (role) {
      case GroupMemberRole.owner:
        filter = GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_OWNER;
        break;
      case GroupMemberRole.admin:
        filter = GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ADMIN;
        break;
      case GroupMemberRole.member:
        filter = GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_COMMON;
        break;
      default:
        filter = GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL;
        break;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getGroupMemberList(
          groupID: groupID,
          filter: filter,
          nextSeq: _memberNextSeq,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    if (result.data != null) {
      _memberNextSeq = result.data!.nextSeq ?? '0';
      _hasMoreGroupMember = _memberNextSeq != '0';

      final memberList = result.data!.memberInfoList ?? [];
      final members = memberList.map((member) => _convertToMember(member)).toList();

      _allMembers = members;

      _markNeedUpdate();
    }

    return handler;
  }

  Future<CompletionHandler> _fetchGroupMembersInfoInternal({required List<String> userIDList}) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager
        .getGroupManager()
        .getGroupMembersInfo(groupID: _groupID, memberList: userIDList);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    if (result.data != null) {
      List<V2TimGroupMemberFullInfo> memberList = result.data!;
      final members = memberList.map((member) => _convertToMember(member)).toList();
      _membersInfo = members;
      _markNeedUpdate();
    }

    return handler;
  }

  Future<CompletionHandler> _fetchGroupAttributesInternal({List<String>? keys}) async {
    final handler = CompletionHandler();

    final result =
      await TencentImSDKPlugin.v2TIMManager.getGroupManager().getGroupAttributes(groupID: _groupID, keys: keys);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    if (result.data != null) {
      _groupAttributes = result.data;
      _markNeedUpdate();
    }

    return handler;
  }

  void _updateGroupAttributes(Map<String, String> attributes) {
    _groupAttributes = attributes;

    _markNeedUpdate();
  }

  Future<CompletionHandler> _updateGroupProfileInternal({
    String? name,
    String? notice,
    String? faceUrl,
  }) async {
    final handler = CompletionHandler();

    final groupInfo = V2TimGroupInfo(
      groupID: groupID,
      groupType: _groupType.value,
    );
    if (name != null) {
      groupInfo.groupName = name;
    }
    if (notice != null) {
      groupInfo.notification = notice;
    }
    if (faceUrl != null) {
      groupInfo.faceUrl = faceUrl;
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().setGroupInfo(info: groupInfo);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    if (name != null) {
      _groupName = name;
    }
    if (notice != null) {
      _notice = notice;
    }
    if (faceUrl != null) {
      _avatar = faceUrl;
    }
    _markNeedUpdate();
    return handler;
  }

  Future<CompletionHandler> _addGroupMemberInternal({required List<String> userIDList}) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().inviteUserToGroup(
          groupID: groupID,
          userList: userIDList,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _fetchGroupInfo();
    return handler;
  }

  Future<CompletionHandler> _deleteGroupMemberInternal({required List<GroupMember> members}) async {
    final handler = CompletionHandler();

    final userIDs = members.map((member) => member.userID).toList();
    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().kickGroupMember(
          groupID: groupID,
          memberList: userIDs,
          reason: "",
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _fetchGroupInfo();
    return handler;
  }

  Future<CompletionHandler> _changeGroupOwnerInternal({required String newOwnerID}) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().transferGroupOwner(
          groupID: groupID,
          userID: newOwnerID,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    return handler;
  }

  Future<CompletionHandler> _setGroupMemberRoleInternal({
    required String userID,
    required GroupMemberRole role,
  }) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().setGroupMemberRole(
          groupID: groupID,
          userID: userID,
          role: role.v2TIMRole,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    return handler;
  }

  Future<CompletionHandler> _setGroupMemberMuteTimeInternal({
    required String userID,
    required int time,
  }) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().muteGroupMember(
          groupID: groupID,
          userID: userID,
          seconds: time,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    return handler;
  }

  Future<CompletionHandler> _setMuteAllMemberInternal({required bool isMuted}) async {
    final handler = CompletionHandler();

    final groupInfo = V2TimGroupInfo(
      groupID: groupID,
      groupType: _groupType.value,
    );
    groupInfo.isAllMuted = isMuted;

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().setGroupInfo(info: groupInfo);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _isAllMuted = isMuted;
    _markNeedUpdate();
    return handler;
  }

  Future<CompletionHandler> _dismissGroupInternal() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.dismissGroup(groupID: groupID);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    return handler;
  }

  Future<CompletionHandler> _quitGroupInternal() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.quitGroup(groupID: groupID);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    return handler;
  }

  Future<CompletionHandler> _setSelfGroupNameCardInternal({required String nameCard}) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().setGroupMemberInfo(
          groupID: groupID,
          userID: _currentUserID,
          nameCard: nameCard,
        );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _selfNameCard = nameCard;
    final memberIndex = _allMembers.indexWhere((member) => member.userID == _currentUserID);
    if (memberIndex != -1) {
      _allMembers[memberIndex].nameCard = nameCard;
    }

    _markNeedUpdate();
    return handler;
  }

  Future<CompletionHandler> _setGroupJoinOptionInternal({required GroupJoinOption option}) async {
    final handler = CompletionHandler();

    final groupInfo = V2TimGroupInfo(
      groupID: groupID,
      groupType: _groupType.value,
    );
    groupInfo.groupAddOpt = _convertJoinOptionToGroupAddOpt(option);

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().setGroupInfo(info: groupInfo);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _joinGroupApprovalType = option;
    _markNeedUpdate();
    return handler;
  }

  Future<CompletionHandler> _setGroupInviteOptionInternal({required GroupJoinOption option}) async {
    final handler = CompletionHandler();

    final groupInfo = V2TimGroupInfo(
      groupID: groupID,
      groupType: _groupType.value,
    );
    groupInfo.approveOpt = _convertInviteOptionToApproveOpt(option);

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().setGroupInfo(info: groupInfo);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _inviteToGroupApprovalType = option;
    _markNeedUpdate();
    return handler;
  }

  void _handleConversationMute(ConversationMuteEventData data) {
    if (!data.conversationID.contains(groupConversationIDPrefix)) {
      return;
    }

    String groupID = ChatUtil.getGroupID(data.conversationID);
    if (groupID != _groupID) {
      return;
    }

    _isNotDisturb = data.mute;
    _markNeedUpdate();
  }

  int _convertJoinOptionToGroupAddOpt(GroupJoinOption option) {
    switch (option) {
      case GroupJoinOption.forbid:
        return GroupAddOptType.V2TIM_GROUP_ADD_FORBID;
      case GroupJoinOption.auth:
        return GroupAddOptType.V2TIM_GROUP_ADD_AUTH;
      case GroupJoinOption.any:
        return GroupAddOptType.V2TIM_GROUP_ADD_ANY;
    }
  }

  int _convertInviteOptionToApproveOpt(GroupJoinOption option) {
    switch (option) {
      case GroupJoinOption.forbid:
        return GroupAddOptType.V2TIM_GROUP_ADD_FORBID;
      case GroupJoinOption.auth:
        return GroupAddOptType.V2TIM_GROUP_ADD_AUTH;
      case GroupJoinOption.any:
        return GroupAddOptType.V2TIM_GROUP_ADD_ANY;
    }
  }

  Future<CompletionHandler> _setReceiveMessageOptInternal({required ReceiveMessageOpt opt}) async {
    final handler = CompletionHandler();

    final v2Opt = ChatUtil.convertToV2TIMReceiveMessageOpt(opt);
    final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().setGroupReceiveMessageOpt(
      groupID: _groupID,
      opt: v2Opt,
    );

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _receiveMessageOpt = opt;
    _isNotDisturb = (opt == ReceiveMessageOpt.notNotify);
    _markNeedUpdate();

    return handler;
  }

}
