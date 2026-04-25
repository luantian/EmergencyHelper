import 'dart:async';

import 'package:atomic_x_core/api/contact/contact_list_store.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';
import 'package:atomic_x_core/impl/common/notification_center.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimFriendshipListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimGroupListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/friend_application_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/friend_response_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/friend_type.dart' hide FriendApplicationType;
import 'package:tencent_cloud_chat_sdk/enum/friend_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_application_handle_result.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_application_handle_status.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_application_type.dart' as sdk;
import 'package:tencent_cloud_chat_sdk/enum/group_application_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_member_role_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_add_friend_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_application.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_check_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_operation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_application.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_imsdk_bindings_generated.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class ContactNotificationNames {
  static const String clearGroupApplicationUnreadCount = 'clear_group_application_unread_count';
}

class ContactListStoreImpl extends ContactListStore {
  List<ContactInfo> _blackList = [];
  List<ContactInfo> _friendList = [];
  List<ContactInfo> _groupList = [];
  List<FriendApplicationInfo> _friendApplicationList = [];
  List<GroupApplicationInfo> _groupApplicationList = [];
  int _friendApplicationUnreadCount = 0;
  int _groupApplicationUnreadCount = 0;
  String _createdGroupID = '';
  ContactInfo? _addFriendInfo;
  ContactInfo? _joinGroupInfo;

  ContactListState? _contactListState;
  bool _needUpdate = true;

  V2TimFriendshipListener? _friendshipListener;
  V2TimGroupListener? _groupListener;
  late List<StreamSubscription> _eventSubscriptions;

  ContactListStoreImpl() {
    _addListeners();
    _addNotificationListeners();
  }

  @override
  ContactListState get contactListState {
    if (_needUpdate || _contactListState == null) {
      _contactListState = ContactListState(
        blackList: List.unmodifiable(_blackList),
        friendList: List.unmodifiable(_friendList),
        groupList: List.unmodifiable(_groupList),
        friendApplicationList: List.unmodifiable(_friendApplicationList),
        groupApplicationList: List.unmodifiable(_groupApplicationList),
        friendApplicationUnreadCount: _friendApplicationUnreadCount,
        groupApplicationUnreadCount: _groupApplicationUnreadCount,
        createdGroupID: _createdGroupID,
        addFriendInfo: _addFriendInfo,
        joinGroupInfo: _joinGroupInfo,
      );
      _needUpdate = false;
    }

    return _contactListState!;
  }

  void _markNeedUpdate() {
    _needUpdate = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _removeListeners();
    _removeNotificationListeners();
    super.dispose();
  }

  void _addListeners() {
    _friendshipListener = V2TimFriendshipListener(
      onFriendInfoChanged: _onFriendInfoChanged,
      onFriendApplicationListAdded: _onFriendApplicationListAdded,
      onFriendApplicationListDeleted: _onFriendApplicationListDeleted,
      onFriendApplicationListRead: _onFriendApplicationListRead,
      onFriendListAdded: _onFriendListAdded,
      onFriendListDeleted: _onFriendListDeleted,
      onBlackListAdd: _onBlackListAdded,
      onBlackListDeleted: _onBlackListDeleted,
    );

    _groupListener = V2TimGroupListener(
      onReceiveJoinApplication: _onReceiveJoinApplication,
    );

    TencentImSDKPlugin.v2TIMManager.getFriendshipManager().addFriendListener(listener: _friendshipListener!);
    TencentImSDKPlugin.v2TIMManager.addGroupListener(listener: _groupListener!);
  }

  void _removeListeners() {
    if (_friendshipListener != null) {
      TencentImSDKPlugin.v2TIMManager.getFriendshipManager().removeFriendListener(listener: _friendshipListener!);
      _friendshipListener = null;
    }

    if (_groupListener != null) {
      TencentImSDKPlugin.v2TIMManager.removeGroupListener(listener: _groupListener!);
      _groupListener = null;
    }
  }

  void _addNotificationListeners() {
    _eventSubscriptions = [
      notificationCenter.addListener<int>(
          ContactNotificationNames.clearGroupApplicationUnreadCount, _handleClearGroupApplicationUnreadCount),
    ];
  }

  void _removeNotificationListeners() {
    for (var subscription in _eventSubscriptions) {
      subscription.cancel();
    }

    _eventSubscriptions.clear();
  }

  @override
  Future<CompletionHandler> fetchBlackList() async {
    return _fetchBlackListInternal();
  }

  @override
  Future<CompletionHandler> fetchFriendApplicationList() async {
    return _fetchFriendApplicationListInternal();
  }

  @override
  Future<CompletionHandler> acceptFriendApplication({required FriendApplicationInfo info}) async {
    return _acceptFriendApplicationInternal(info);
  }

  @override
  Future<CompletionHandler> refuseFriendApplication({required FriendApplicationInfo info}) async {
    return _refuseFriendApplicationInternal(info);
  }

  @override
  Future<CompletionHandler> clearFriendApplicationUnreadCount() {
    return _clearFriendApplicationUnreadCount();
  }

  @override
  Future<CompletionHandler> fetchJoinedGroupList() async {
    return _fetchJoinedGroupListInternal();
  }

  @override
  Future<CompletionHandler> fetchFriendList() async {
    return _fetchFriendListInternal();
  }

  @override
  Future<CompletionHandler> joinGroup({required String groupID, String? message}) async {
    return _joinGroupInternal(groupID, message);
  }

  @override
  Future<CompletionHandler> fetchGroupApplicationList() async {
    return _fetchGroupApplicationListInternal();
  }

  @override
  Future<CompletionHandler> acceptGroupApplication({required GroupApplicationInfo info}) async {
    return _acceptGroupApplicationInternal(info);
  }

  @override
  Future<CompletionHandler> refuseGroupApplication({required GroupApplicationInfo info}) async {
    return _refuseGroupApplicationInternal(info);
  }

  @override
  Future<CompletionHandler> clearGroupApplicationUnreadCount() {
    return _clearGroupApplicationUnreadCount();
  }

  @override
  Future<CompletionHandler> fetchUserInfo({required String userID}) async {
    return _getUserInfoInternal(userID);
  }

  @override
  Future<CompletionHandler> fetchGroupInfo({required String groupID}) async {
    return _getGroupInfoInternal(groupID);
  }

  @override
  Future<CompletionHandler> addFriend({required String userID, String? remark, String? addWording}) async {
    final param = V2TimFriendAddFriendParam(
      userID: userID,
      remark: remark,
      addWording: addWording,
      addSource: "Flutter",
      addType: FriendTypeEnum.V2TIM_FRIEND_TYPE_BOTH,
    );
    return _addFriendInternal(param);
  }

  @override
  Future<CompletionHandler> createGroup({
    required String groupType,
    String? groupID,
    required String groupName,
    String? avatarURL,
    List<ContactInfo>? memberList,
  }) async {
    return _createGroupInternal(
      groupType: groupType,
      groupID: groupID,
      groupName: groupName,
      avatarURL: avatarURL,
      memberList: memberList,
    );
  }

  String _getContactTitle(V2TimFriendInfo friendInfo) {
    if (friendInfo.friendRemark?.isNotEmpty == true) {
      return friendInfo.friendRemark!;
    }

    if (friendInfo.userProfile?.nickName?.isNotEmpty == true) {
      return friendInfo.userProfile!.nickName!;
    }

    return friendInfo.userProfile?.userID ?? '';
  }

  Future<CompletionHandler> _fetchBlackListInternal() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().getBlackList();

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    final blackListContacts = _convertToBlackList(result.data ?? []);
    _blackList = blackListContacts;
    _markNeedUpdate();

    return handler;
  }

  List<ContactInfo> _convertToBlackList(List<V2TimFriendInfo> v2List) {
    return v2List.map(_convertToUserContact).toList();
  }

  ContactInfo _convertToUserContact(V2TimFriendInfo friendInfo, {bool isFriend = false}) {
    return ContactInfo(
      contactID: friendInfo.userID,
      type: ContactType.user,
      avatarURL: friendInfo.userProfile?.faceUrl,
      title: _getContactTitle(friendInfo),
      isContact: isFriend,
    );
  }

  Future<CompletionHandler> _fetchFriendApplicationListInternal() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().getFriendApplicationList();

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    final applicationList = _convertToApplicationList(result.data?.friendApplicationList ?? []);
    _friendApplicationList = applicationList;
    _friendApplicationUnreadCount = result.data?.unreadCount ?? 0;
    _markNeedUpdate();

    return handler;
  }

  List<FriendApplicationInfo> _convertToApplicationList(List<V2TimFriendApplication?> v2List) {
    return v2List
        .where((app) => _convertToFriendApplicationInfo(app) != null)
        .map((app) => _convertToFriendApplicationInfo(app)!)
        .toList();
  }

  FriendApplicationInfo? _convertToFriendApplicationInfo(V2TimFriendApplication? application) {
    if (application == null) {
      return null;
    }

    if (application.type != FriendApplicationTypeEnum.V2TIM_FRIEND_APPLICATION_COME_IN.index) {
      return null;
    }

    return FriendApplicationInfo(
      application: application,
      applicationID: application.userID,
      avatarURL: application.faceUrl,
      title: application.nickname?.isNotEmpty == true ? application.nickname : application.userID,
      type: FriendApplicationType.received,
      addWording: application.addWording,
    );
  }

  Future<CompletionHandler> _acceptFriendApplicationInternal(FriendApplicationInfo info) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().acceptFriendApplication(
        responseType: FriendResponseTypeEnum.V2TIM_FRIEND_ACCEPT_AGREE_AND_ADD,
        type: FriendApplicationTypeEnum.V2TIM_FRIEND_APPLICATION_COME_IN,
        userID: info.applicationID);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _friendApplicationList.removeWhere((app) => app.applicationID == info.applicationID);
    _markNeedUpdate();

    return handler;
  }

  Future<CompletionHandler> _refuseFriendApplicationInternal(FriendApplicationInfo info) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().refuseFriendApplication(
        type: FriendApplicationTypeEnum.V2TIM_FRIEND_APPLICATION_COME_IN, userID: info.applicationID);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _friendApplicationList.removeWhere((app) => app.applicationID == info.applicationID);
    _markNeedUpdate();

    return handler;
  }

  Future<CompletionHandler> _clearFriendApplicationUnreadCount() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.v2TIMFriendshipManager.setFriendApplicationRead();
    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _friendApplicationUnreadCount = 0;
    _markNeedUpdate();

    return handler;
  }

  Future<CompletionHandler> _fetchJoinedGroupListInternal() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getJoinedGroupList();

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    final groupListContacts = _convertToGroupList(result.data ?? []);
    _groupList = groupListContacts;
    _markNeedUpdate();

    return handler;
  }

  List<ContactInfo> _convertToGroupList(List<V2TimGroupInfo> v2List) {
    return v2List
        .where((group) => _convertToGroupContact(group) != null)
        .map((group) => _convertToGroupContact(group)!)
        .toList();
  }

  ContactInfo? _convertToGroupContact(V2TimGroupInfo groupInfo) {
    if (groupInfo.groupID.isEmpty) {
      return null;
    }

    return ContactInfo(
      contactID: groupInfo.groupID,
      type: ContactType.group,
      avatarURL: groupInfo.faceUrl,
      title: groupInfo.groupName,
    );
  }

  Future<CompletionHandler> _fetchFriendListInternal() async {
    DataReport.reportAtomicMetrics(AtomicMetrics.contactList);

    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().getFriendList();

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    final friendListContacts = _convertToFriendList(result.data ?? []);
    _friendList = friendListContacts;
    _markNeedUpdate();

    return handler;
  }

  List<ContactInfo> _convertToFriendList(List<V2TimFriendInfo> v2List) {
    return v2List.map((friendInfo) => _convertToUserContact(friendInfo, isFriend: true)).toList();
  }

  Future<CompletionHandler> _addFriendInternal(V2TimFriendAddFriendParam application) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().addFriend(
        userID: application.userID,
        remark: application.remark,
        friendGroup: application.friendGroup,
        addWording: application.addWording,
        addSource: application.addSource,
        addType: application.addType);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    V2TimFriendOperationResult? operationResult = result.data;
    if (operationResult != null) {
      handler.errorCode = operationResult.resultCode!;
    }

    return handler;
  }

  Future<CompletionHandler> _joinGroupInternal(String groupID, String? message) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.joinGroup(groupID: groupID, message: message ?? "");

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    return handler;
  }

  Future<CompletionHandler> _fetchGroupApplicationListInternal() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getGroupApplicationList();
    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    final applicationList = _convertToGroupApplicationList(result.data?.groupApplicationList ?? []);
    _groupApplicationList = applicationList;
    _groupApplicationUnreadCount = result.data?.unreadCount ?? 0;
    _markNeedUpdate();

    return handler;
  }

  List<GroupApplicationInfo> _convertToGroupApplicationList(List<V2TimGroupApplication?> v2ApplicationList) {
    return v2ApplicationList
        .where((app) => app != null && app.handleStatus == 0)
        .map((app) => _convertToGroupApplicationInfo(app!))
        .toList();
  }

  GroupApplicationInfo _convertToGroupApplicationInfo(V2TimGroupApplication application) {
    return GroupApplicationInfo(
      application: application,
      applicationID: generateGroupApplicationID(application),
      groupID: application.groupID,
      fromUser: application.fromUser,
      fromUserNickname: application.fromUserNickName,
      fromUserAvatarURL: application.fromUserFaceUrl,
      toUser: application.toUser,
      addTime: application.addTime ?? 0,
      requestMsg: application.requestMsg,
      handledMsg: application.handledMsg,
      type: _toGroupApplicationType(application.type),
      handledStatus: _toGroupApplicationHandledStatus(application.handleStatus),
      handledResult: _toGroupApplicationHandledResult(application.handleResult),
    );
  }

  String generateGroupApplicationID(V2TimGroupApplication application) {
    return '${application.groupID}_${application.type}_${application.addTime}_${application.fromUser}_${application.toUser}';
  }

  GroupApplicationType _toGroupApplicationType(int type) {
    switch (type) {
      case sdk.GroupApplicationType.V2TIM_GROUP_APPLICATION_GET_TYPE_JOIN:
        return GroupApplicationType.joinApprovedByAdmin;
      case sdk.GroupApplicationType.V2TIM_GROUP_APPLICATION_GET_TYPE_INVITE:
        return GroupApplicationType.inviteApprovedByInvitee;
      case sdk.GroupApplicationType.V2TIM_GROUP_APPLICATION_NEED_ADMIN_APPROVE:
        return GroupApplicationType.inviteApprovedByAdmin;
      default:
        return GroupApplicationType.inviteApprovedByAdmin;
    }
  }

  GroupApplicationHandledStatus _toGroupApplicationHandledStatus(int status) {
    switch (status) {
      case GroupApplicationHandleStatus.V2TIM_GROUP_APPLICATION_HANDLE_STATUS_UNHANDLED:
        return GroupApplicationHandledStatus.unhandled;
      case GroupApplicationHandleStatus.V2TIM_GROUP_APPLICATION_HANDLE_STATUS_HANDLED_BY_OTHER:
        return GroupApplicationHandledStatus.byOther;
      case GroupApplicationHandleStatus.V2TIM_GROUP_APPLICATION_HANDLE_STATUS_HANDLED_BY_SELF:
        return GroupApplicationHandledStatus.byMyself;
      default:
        return GroupApplicationHandledStatus.unhandled;
    }
  }

  GroupApplicationHandledResult _toGroupApplicationHandledResult(int result) {
    switch (result) {
      case GroupApplicationHandleResult.V2TIM_GROUP_APPLICATION_HANDLE_RESULT_REFUSE:
        return GroupApplicationHandledResult.refused;
      case GroupApplicationHandleResult.V2TIM_GROUP_APPLICATION_HANDLE_RESULT_AGREE:
        return GroupApplicationHandledResult.agreed;
      default:
        return GroupApplicationHandledResult.refused;
    }
  }

  Future<CompletionHandler> _acceptGroupApplicationInternal(GroupApplicationInfo info) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().acceptGroupApplication(
        groupID: info.groupID,
        fromUser: info.application.fromUser ?? '',
        toUser: info.application.toUser ?? '',
        application: info.application);
    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    final index = _groupApplicationList.indexWhere((app) => app.applicationID == info.applicationID);
    if (index != -1) {
      _groupApplicationList[index].handledStatus = GroupApplicationHandledStatus.byMyself;
      _groupApplicationList[index].handledResult = GroupApplicationHandledResult.agreed;
    }

    _markNeedUpdate();

    return handler;
  }

  Future<CompletionHandler> _refuseGroupApplicationInternal(GroupApplicationInfo info) async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().refuseGroupApplication(
        groupID: info.groupID,
        fromUser: info.application.fromUser ?? '',
        toUser: info.application.toUser ?? '',
        addTime: info.application.addTime ?? 0,
        type: GroupApplicationTypeEnum.values.firstWhere((e) => e.index == info.application.type),
        application: info.application);
    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    final index = _groupApplicationList.indexWhere((app) => app.applicationID == info.applicationID);
    if (index != -1) {
      _groupApplicationList[index].handledStatus = GroupApplicationHandledStatus.byMyself;
      _groupApplicationList[index].handledResult = GroupApplicationHandledResult.refused;
    }

    _markNeedUpdate();

    return handler;
  }

  Future<CompletionHandler> _clearGroupApplicationUnreadCount() async {
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.v2TIMGroupManager.setGroupApplicationRead();
    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _groupApplicationUnreadCount = 0;
    _markNeedUpdate();

    notificationCenter.post(ContactNotificationNames.clearGroupApplicationUnreadCount, 0);

    return handler;
  }

  Future<CompletionHandler> _createGroupInternal({
    required String groupType,
    String? groupID,
    required String groupName,
    String? avatarURL,
    List<ContactInfo>? memberList,
  }) async {
    final handler = CompletionHandler();
    List<V2TimGroupMember>? v2MemberList;
    if (memberList != null) {
      v2MemberList = memberList.map((contact) {
        return V2TimGroupMember(
            userID: contact.contactID, role: GroupMemberRoleTypeEnum.V2TIM_GROUP_MEMBER_ROLE_MEMBER);
      }).toList();
    }

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().createGroup(
        groupType: groupType, groupID: groupID, groupName: groupName, faceUrl: avatarURL, memberList: v2MemberList);

    if (result.code != 0) {
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    _createdGroupID = result.data ?? '';
    return handler;
  }

  Future<CompletionHandler> _getUserInfoInternal(String userID) async {
    _addFriendInfo = null;
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getUsersInfo(userIDList: [userID]);

    if (result.code != 0) {
      _addFriendInfo = null;
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    final userInfoList = result.data ?? [];
    if (userInfoList.isNotEmpty) {
      final userInfo = userInfoList.first;
      final checkResult = await TencentImSDKPlugin.v2TIMManager.v2TIMFriendshipManager
          .checkFriend(userIDList: [userInfo.userID!], checkType: FriendTypeEnum.V2TIM_FRIEND_TYPE_BOTH);
      bool isFriend = false;
      final List<V2TimFriendCheckResult> friendCheckResultList = checkResult.data ?? [];
      if (friendCheckResultList.isNotEmpty) {
        V2TimFriendCheckResult friendCheckResult = friendCheckResultList.first;
        if (friendCheckResult.resultType == FriendType.V2TIM_FRIEND_TYPE_BOTH) {
          isFriend = true;
        }
      }

      _addFriendInfo = ContactInfo(
        contactID: userInfo.userID ?? '',
        type: ContactType.user,
        avatarURL: userInfo.faceUrl,
        title: userInfo.nickName ?? userInfo.userID ?? '',
        isContact: isFriend,
      );
    } else {
      _addFriendInfo = null;
      handler.errorCode = TIMErrCode.ERR_NO_SUCC_RESULT.value;
      handler.errorMessage = "user not exist";
    }

    _markNeedUpdate();
    return handler;
  }

  Future<CompletionHandler> _getGroupInfoInternal(String groupID) async {
    _joinGroupInfo = null;
    final handler = CompletionHandler();

    final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getGroupsInfo(groupIDList: [groupID]);
    if (result.code != 0) {
      _joinGroupInfo = null;
      handler.errorCode = result.code;
      handler.errorMessage = result.desc;
      return handler;
    }

    final groupInfoList = result.data ?? [];
    if (groupInfoList.isNotEmpty) {
      final groupInfoResult = groupInfoList.first;
      if (groupInfoResult.resultCode == TIMErrCode.ERR_SVR_GROUP_INVALID_GROUPID.value) {
        handler.errorCode = groupInfoResult.resultCode!;
        handler.errorMessage = "group id invalid";
        return handler;
      }

      bool isInGroup = false;
      final joinedResult = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getJoinedGroupList();
      if (joinedResult.code == 0) {
        isInGroup = joinedResult.data?.any((group) => group.groupID == groupInfoResult.groupInfo?.groupID) ?? false;
      }

      _joinGroupInfo = ContactInfo(
        contactID: groupInfoResult.groupInfo?.groupID ?? '',
        type: ContactType.group,
        avatarURL: groupInfoResult.groupInfo?.faceUrl,
        title: groupInfoResult.groupInfo?.groupName,
        isInGroup: isInGroup,
      );
    } else {
      _joinGroupInfo = null;
      handler.errorCode = TIMErrCode.ERR_NO_SUCC_RESULT.value;
      handler.errorMessage = "group not exist";
    }

    _markNeedUpdate();
    return handler;
  }

  /// ****** V2TimFriendshipListener ******
  void _onFriendInfoChanged(List<V2TimFriendInfo> infoList) {
    bool hasChanges = false;

    final friendMap = <String, ContactInfo>{};
    for (final contactInfo in _friendList) {
      friendMap[contactInfo.contactID] = contactInfo;
    }

    for (var friendInfo in infoList) {
      ContactInfo? contactInfo = friendMap[friendInfo.userID];
      if (contactInfo != null) {
        contactInfo.title = _getContactTitle(friendInfo);
        contactInfo.avatarURL = friendInfo.userProfile?.faceUrl;
        hasChanges = true;
      }
    }

    if (hasChanges) {
      _markNeedUpdate();
    }
  }

  void _onFriendApplicationListAdded(List<V2TimFriendApplication> applicationList) {
    final newApplications = _convertToApplicationList(applicationList);

    for (final newApp in newApplications) {
      final existingIndex = _friendApplicationList.indexWhere((app) => app.applicationID == newApp.applicationID);
      if (existingIndex == -1) {
        _friendApplicationList.add(newApp);
      } else {
        _friendApplicationList[existingIndex] = newApp;
      }
    }

    _friendApplicationUnreadCount = _friendApplicationList.length;
    _markNeedUpdate();
  }

  void _onFriendApplicationListDeleted(List<String> userIDList) {
    _friendApplicationList.removeWhere((app) => userIDList.contains(app.applicationID));
    _friendApplicationUnreadCount = _friendApplicationList.length;
    _markNeedUpdate();
  }

  void _onFriendApplicationListRead() {
    _friendApplicationUnreadCount = 0;
    _markNeedUpdate();
  }

  void _onFriendListAdded(List<V2TimFriendInfo> infoList) {
    final newFriends = _convertToFriendList(infoList);

    for (final newFriend in newFriends) {
      final existingIndex = _friendList.indexWhere((friend) => friend.contactID == newFriend.contactID);
      if (existingIndex == -1) {
        _friendList.add(newFriend);
      } else {
        _friendList[existingIndex] = newFriend;
      }
    }

    _markNeedUpdate();
  }

  void _onFriendListDeleted(List<String> userIDList) {
    _friendList.removeWhere((friend) => userIDList.contains(friend.contactID));
    _markNeedUpdate();
  }

  void _onBlackListAdded(List<V2TimFriendInfo> infoList) {
    final newBlackListContacts = _convertToBlackList(infoList);

    for (final newContact in newBlackListContacts) {
      final existingIndex = _blackList.indexWhere((contact) => contact.contactID == newContact.contactID);
      if (existingIndex == -1) {
        _blackList.add(newContact);
      } else {
        _blackList[existingIndex] = newContact;
      }
    }

    _markNeedUpdate();
  }

  void _onBlackListDeleted(List<String> userIDList) {
    _blackList.removeWhere((contact) => userIDList.contains(contact.contactID));
    _markNeedUpdate();
  }

  void _onReceiveJoinApplication(
    String groupID,
    V2TimGroupMemberInfo member,
    String opReason,
  ) {
    _fetchGroupApplicationListInternal();
  }

  void _handleClearGroupApplicationUnreadCount(int count) {
    _groupApplicationUnreadCount = count;
    _markNeedUpdate();
  }
}
