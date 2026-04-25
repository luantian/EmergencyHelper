import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_param.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_search_result_item.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_search_param.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_imsdk_bindings_generated.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class SearchStoreImpl extends SearchStore {
  List<String> _currentKeywordList = [];
  SearchOption? _currentOption;

  String _userSearchCursor = "";
  String _groupSearchCursor = "";
  String _groupMemberSearchCursor = "";
  String _messageSearchCursor = "";

  List<UserProfile> _userList = [];
  int _userTotalCount = 0;
  bool _hasMoreUserList = true;

  List<FriendSearchInfo> _friendList = [];
  int _friendTotalCount = 0;
  bool _hasMoreFriendList = true;

  List<GroupSearchInfo> _groupList = [];
  int _groupTotalCount = 0;
  bool _hasMoreGroupList = true;

  Map<String, List<GroupMember>> _groupMemberList = {};
  int _groupMemberTotalCount = 0;
  bool _hasMoreGroupMemberList = true;

  List<MessageSearchResultItem> _messageResults = [];
  int _messageResultTotalCount = 0;
  bool _hasMoreMessageResults = true;

  SearchState? _searchState;
  bool _needUpdate = true;
  bool _disposed = false;

  SearchStoreImpl();

  @override
  SearchState get searchState {
    if (_needUpdate || _searchState == null) {
      _searchState = SearchState(
        userList: List.unmodifiable(_userList),
        userTotalCount: _userTotalCount,
        hasMoreUserList: _hasMoreUserList,
        friendList: List.unmodifiable(_friendList),
        friendTotalCount: _friendTotalCount,
        hasMoreFriendList: _hasMoreFriendList,
        groupList: List.unmodifiable(_groupList),
        groupTotalCount: _groupTotalCount,
        hasMoreGroupList: _hasMoreGroupList,
        groupMemberList: Map.unmodifiable(_groupMemberList),
        groupMemberTotalCount: _groupMemberTotalCount,
        hasMoreGroupMemberList: _hasMoreGroupMemberList,
        messageResults: List.unmodifiable(_messageResults),
        messageResultTotalCount: _messageResultTotalCount,
        hasMoreMessageResults: _hasMoreMessageResults,
      );
      _needUpdate = false;
    }

    return _searchState!;
  }

  void _markNeedUpdate() {
    if (_disposed) return;
    _needUpdate = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Future<CompletionHandler> search({
    required List<String> keywordList,
    required SearchOption option,
  }) async {
    DataReport.reportAtomicMetrics(AtomicMetrics.search);

    if (keywordList.isEmpty) {
      return CompletionHandler()
        ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
        ..errorMessage = "Keyword list cannot be empty";
    }

    if (option.searchType.rawValue == 0) {
      return CompletionHandler()
        ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
        ..errorMessage = "Search type cannot be empty";
    }

    if (option.searchCount <= 0) {
      return CompletionHandler()
        ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
        ..errorMessage = "Search count must be greater than 0";
    }

    _currentKeywordList = keywordList;
    _currentOption = option;
    _resetSearchData(option.searchType);

    bool searchSuccess = false;
    final List<Future<CompletionHandler>> futures = [];

    if (option.searchType.contains(SearchType.user)) {
      futures.add(_searchUsersInternal(keywordList, option));
    }

    if (option.searchType.contains(SearchType.friend)) {
      futures.add(_searchFriendsInternal(keywordList, option));
    }

    if (option.searchType.contains(SearchType.group)) {
      futures.add(_searchGroupsInternal(keywordList, option));
    }

    if (option.searchType.contains(SearchType.groupMember)) {
      futures.add(_searchGroupMembersInternal(keywordList, option));
    }

    if (option.searchType.contains(SearchType.message)) {
      futures.add(_searchMessagesInternal(keywordList, option));
    }

    final results = await Future.wait(futures);
    for (final result in results) {
      if (result.errorCode == 0) {
        searchSuccess = true;
      }
    }

    if (searchSuccess) {
      return CompletionHandler();
    } else {
      return CompletionHandler()
        ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
        ..errorMessage = "Search failed";
    }
  }

  @override
  Future<CompletionHandler> searchMore({required SearchType searchType}) async {
    if (_currentOption == null) {
      return CompletionHandler()
        ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
        ..errorMessage = "Please call search first";
    }

    // Check if only single search type is provided (check if power of 2)
    if (searchType.rawValue == 0 || (searchType.rawValue & (searchType.rawValue - 1)) != 0) {
      return CompletionHandler()
        ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
        ..errorMessage = "searchMore only supports single search type";
    }

    if (searchType == SearchType.user) {
      if (!_hasMoreUserList) {
        return CompletionHandler();
      }
      return await _searchUsersInternal(_currentKeywordList, _currentOption!);
    } else if (searchType == SearchType.friend) {
      if (!_hasMoreFriendList) {
        return CompletionHandler();
      }
      return CompletionHandler()
        ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
        ..errorMessage = "Friend search does not support pagination";
    } else if (searchType == SearchType.group) {
      if (!_hasMoreGroupList) {
        return CompletionHandler();
      }
      if (!_currentOption!.isCloudSearch) {
        return CompletionHandler()
          ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
          ..errorMessage = "Local group search does not support pagination";
      }
      return await _searchGroupsInternal(_currentKeywordList, _currentOption!);
    } else if (searchType == SearchType.groupMember) {
      if (!_hasMoreGroupMemberList) {
        return CompletionHandler();
      }
      if (!_currentOption!.isCloudSearch) {
        return CompletionHandler()
          ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
          ..errorMessage = "Local group member search does not support pagination";
      }
      return await _searchGroupMembersInternal(_currentKeywordList, _currentOption!);
    } else if (searchType == SearchType.message) {
      if (!_hasMoreMessageResults) {
        return CompletionHandler();
      }
      return await _searchMessagesInternal(_currentKeywordList, _currentOption!);
    }

    return CompletionHandler()
      ..errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value
      ..errorMessage = "Invalid search type";
  }

  void _resetSearchData(SearchType searchType) {
    if (searchType.contains(SearchType.user)) {
      _userSearchCursor = "";
      _userList.clear();
      _userTotalCount = 0;
      _hasMoreUserList = true;
    }

    if (searchType.contains(SearchType.friend)) {
      _friendList.clear();
      _friendTotalCount = 0;
      _hasMoreFriendList = true;
    }

    if (searchType.contains(SearchType.group)) {
      _groupSearchCursor = "";
      _groupList.clear();
      _groupTotalCount = 0;
      _hasMoreGroupList = true;
    }

    if (searchType.contains(SearchType.groupMember)) {
      _groupMemberSearchCursor = "";
      _groupMemberList.clear();
      _groupMemberTotalCount = 0;
      _hasMoreGroupMemberList = true;
    }

    if (searchType.contains(SearchType.message)) {
      _messageSearchCursor = "";
      _messageResults.clear();
      _messageResultTotalCount = 0;
      _hasMoreMessageResults = true;
    }

    _markNeedUpdate();
  }

  // User Search
  Future<CompletionHandler> _searchUsersInternal(List<String> keywordList, SearchOption option) async {
    final searchParam = V2TimUserSearchParam(
      keywordList: keywordList,
      searchCount: option.searchCount,
      searchCursor: _userSearchCursor,
    );

    if (option.userFilter != null) {
      searchParam.gender = ChatUtil.convertGenderToInt(option.userFilter!.gender);
      searchParam.minBirthday = option.userFilter!.minBirthday;
      if (option.userFilter!.maxBirthday != null) {
        searchParam.maxBirthday = option.userFilter!.maxBirthday!;
      }
    }

    final result = await TencentImSDKPlugin.v2TIMManager.searchUsers(searchParam: searchParam);

    if (result.code == 0 && result.data != null) {
      final isFirstPage = _userSearchCursor.isEmpty;
      _userSearchCursor = result.data!.nextCursor ?? "";

      final users = result.data!.userInfoList?.map((user) => ChatUtil.convertToUserProfile(user)).toList() ?? [];

      if (isFirstPage) {
        _userList = users;
      } else {
        _userList.addAll(users);
      }

      _userTotalCount = result.data!.totalCount ?? 0;
      _hasMoreUserList = !(result.data!.isFinished ?? true);

      _markNeedUpdate();

      return CompletionHandler();
    } else {
      return CompletionHandler()
        ..errorCode = result.code
        ..errorMessage = result.desc;
    }
  }

  // Friend Search
  Future<CompletionHandler> _searchFriendsInternal(List<String> keywordList, SearchOption option) async {
    final searchParam = V2TimFriendSearchParam(
      keywordList: keywordList,
      isSearchUserID: true,
      isSearchNickName: true,
      isSearchRemark: true,
    );

    final result = await TencentImSDKPlugin.v2TIMManager.getFriendshipManager().searchFriends(searchParam: searchParam);

    if (result.code == 0 && result.data != null) {
      final friendList = result.data!
          .where((item) => item.friendInfo != null)
          .map((item) => _convertToFriendSearchInfo(item.friendInfo!))
          .where((item) => item != null)
          .cast<FriendSearchInfo>()
          .toList();

      _friendList = friendList;
      _friendTotalCount = friendList.length;
      _hasMoreFriendList = false;

      _markNeedUpdate();

      return CompletionHandler();
    } else {
      return CompletionHandler()
        ..errorCode = result.code
        ..errorMessage = result.desc;
    }
  }

  // Group Search
  Future<CompletionHandler> _searchGroupsInternal(List<String> keywordList, SearchOption option) async {
    final searchParam = V2TimGroupSearchParam(
      keywordList: keywordList,
    );

    if (option.isCloudSearch) {
      // Cloud search
      searchParam.searchCount = option.searchCount;
      searchParam.searchCursor = _groupSearchCursor;
      searchParam.keywordListMatchType = option.keywordListMatchType == KeywordListMatchType.or
          ? KeywordListMatchType.or.index
          : KeywordListMatchType.and.index;

      final result =
          await TencentImSDKPlugin.v2TIMManager.getGroupManager().searchCloudGroups(searchParam: searchParam);

      if (result.code == 0 && result.data != null) {
        final isFirstPage = _groupSearchCursor.isEmpty;
        _groupSearchCursor = result.data!.nextCursor ?? "";

        final groups = result.data!.groupList
                ?.map((groupInfo) => _convertToGroupSearchInfo(groupInfo))
                .where((item) => item != null)
                .cast<GroupSearchInfo>()
                .toList() ??
            [];

        if (isFirstPage) {
          _groupList = groups;
        } else {
          _groupList.addAll(groups);
        }

        _groupTotalCount = result.data!.totalCount ?? 0;
        _hasMoreGroupList = !(result.data!.isFinished ?? true);

        _markNeedUpdate();

        return CompletionHandler();
      } else {
        return CompletionHandler()
          ..errorCode = result.code
          ..errorMessage = result.desc;
      }
    } else {
      // Local search
      searchParam.isSearchGroupID = true;
      searchParam.isSearchGroupName = true;

      final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().searchGroups(searchParam: searchParam);

      if (result.code == 0 && result.data != null) {
        final groups = result.data!
            .map((groupInfo) => _convertToGroupSearchInfo(groupInfo))
            .where((item) => item != null)
            .cast<GroupSearchInfo>()
            .toList();

        _groupList = groups;
        _groupTotalCount = groups.length;
        _hasMoreGroupList = false;

        _markNeedUpdate();

        return CompletionHandler();
      } else {
        return CompletionHandler()
          ..errorCode = result.code
          ..errorMessage = result.desc;
      }
    }
  }

  // Group Member Search
  Future<CompletionHandler> _searchGroupMembersInternal(List<String> keywordList, SearchOption option) async {
    final searchParam = V2TimGroupMemberSearchParam(
      keywordList: keywordList,
    );

    if (option.groupMemberFilter?.groupIDList != null && option.groupMemberFilter!.groupIDList.isNotEmpty) {
      searchParam.groupIDList = option.groupMemberFilter!.groupIDList;
    }

    if (option.isCloudSearch) {
      // Cloud search
      searchParam.searchCount = option.searchCount;
      searchParam.searchCursor = _groupMemberSearchCursor;
      searchParam.keywordListMatchType = option.keywordListMatchType == KeywordListMatchType.or
          ? KeywordListMatchType.or.index
          : KeywordListMatchType.and.index;

      final result =
          await TencentImSDKPlugin.v2TIMManager.getGroupManager().searchCloudGroupMembers(param: searchParam);

      if (result.code == 0 && result.data != null) {
        final isFirstPage = _groupMemberSearchCursor.isEmpty;
        _groupMemberSearchCursor = result.data!.nextCursor ?? "";

        final Map<String, List<GroupMember>> groupMemberDict = {};
        final searchResultItems = result.data!.groupMemberSearchResultItems;
        if (searchResultItems != null) {
          searchResultItems.forEach((groupID, members) {
            if (members is List) {
              groupMemberDict[groupID] =
                  members.map((member) => _convertToGroupMember(member as V2TimGroupMemberFullInfo)).toList();
            }
          });
        }

        if (isFirstPage) {
          _groupMemberList = groupMemberDict;
        } else {
          // Merge with existing results
          final currentMap = Map<String, List<GroupMember>>.from(_groupMemberList);
          groupMemberDict.forEach((groupID, members) {
            if (currentMap.containsKey(groupID)) {
              currentMap[groupID]!.addAll(members);
            } else {
              currentMap[groupID] = members;
            }
          });
          _groupMemberList = currentMap;
        }

        _groupMemberTotalCount = result.data!.totalCount ?? 0;
        _hasMoreGroupMemberList = !(result.data!.isFinished ?? true);

        _markNeedUpdate();

        return CompletionHandler();
      } else {
        return CompletionHandler()
          ..errorCode = result.code
          ..errorMessage = result.desc;
      }
    } else {
      // Local search
      searchParam.isSearchMemberUserID = true;
      searchParam.isSearchMemberNickName = true;
      searchParam.isSearchMemberRemark = true;
      searchParam.isSearchMemberNameCard = true;

      final result = await TencentImSDKPlugin.v2TIMManager.getGroupManager().searchGroupMembers(param: searchParam);

      if (result.code == 0 && result.data != null) {
        final Map<String, List<GroupMember>> groupMemberDict = {};

        final searchResultItems = result.data!.groupMemberSearchResultItems;
        if (searchResultItems != null) {
          searchResultItems.forEach((groupID, memberInfoList) {
            if (memberInfoList is List) {
              final members =
                  memberInfoList.map((member) => _convertToGroupMember(member as V2TimGroupMemberFullInfo)).toList();
              if (groupID.isNotEmpty) {
                groupMemberDict[groupID] = members;
              }
            }
          });
        }

        int totalCount = 0;
        for (final members in groupMemberDict.values) {
          totalCount += members.length;
        }

        _groupMemberList = groupMemberDict;
        _groupMemberTotalCount = totalCount;
        _hasMoreGroupMemberList = false;

        _markNeedUpdate();

        return CompletionHandler();
      } else {
        return CompletionHandler()
          ..errorCode = result.code
          ..errorMessage = result.desc;
      }
    }
  }

  // Message Search
  Future<CompletionHandler> _searchMessagesInternal(List<String> keywordList, SearchOption option) async {
    final searchParam = V2TimMessageSearchParam(
      keywordList: keywordList,
      type: option.keywordListMatchType == KeywordListMatchType.or
          ? KeywordListMatchType.or.index
          : KeywordListMatchType.and.index,
      pageSize: option.searchCount,
    );

    if (option.messageFilter != null) {
      final filter = option.messageFilter!;
      if (filter.conversationID != null) {
        searchParam.conversationID = filter.conversationID;
      }

      searchParam.searchTimePosition = filter.searchTimePosition;
      searchParam.searchTimePeriod = filter.searchTimePeriod;

      if (filter.messageTypeList != null) {
        searchParam.messageTypeList = filter.messageTypeList!.map((type) => _convertToV2TIMElemType(type)).toList();
      }
    }

    final isSearchInConversation = searchParam.conversationID != null && searchParam.conversationID!.isNotEmpty;

    if (option.isCloudSearch) {
      // Cloud search
      searchParam.searchCount = option.searchCount;
      searchParam.searchCursor = _messageSearchCursor;

      final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().searchCloudMessages(
            searchParam: searchParam,
          );

      if (result.code == 0 && result.data != null) {
        final isFirstPage = _messageSearchCursor.isEmpty;
        _messageSearchCursor = result.data!.searchCursor ?? "";

        final messageResults =
            result.data!.messageSearchResultItems?.map((item) => _convertToMessageSearchResultItem(item)).toList() ??
                [];
        final totalCount = result.data!.totalCount ?? 0;
        final hasMore = _messageSearchCursor.isNotEmpty;

        // Skip fetching conversation info if searching in a specific conversation (not first page)
        final updatedResults = (!isFirstPage && isSearchInConversation)
            ? messageResults
            : await _fetchConversationInfoForMessageResults(messageResults);

        _updateMessageResults(
          isFirstPage: isFirstPage,
          isSearchInConversation: isSearchInConversation,
          newResults: updatedResults,
          totalCount: totalCount,
          hasMore: hasMore,
        );

        return CompletionHandler();
      } else {
        return CompletionHandler()
          ..errorCode = result.code
          ..errorMessage = result.desc;
      }
    } else {
      // Local search
      final currentPageIndex = int.tryParse(_messageSearchCursor) ?? 0;
      searchParam.pageIndex = currentPageIndex;
      searchParam.pageSize = option.searchCount;

      final result = await TencentImSDKPlugin.v2TIMManager.getMessageManager().searchLocalMessages(
            searchParam: searchParam,
          );

      if (result.code == 0 && result.data != null) {
        final isFirstPage = currentPageIndex == 0;
        final messageResults =
            result.data!.messageSearchResultItems?.map((item) => _convertToMessageSearchResultItem(item)).toList() ??
                [];

        final totalCount = result.data!.totalCount ?? 0;
        final pageSize = option.searchCount;
        final totalPage = (totalCount % pageSize == 0) ? (totalCount ~/ pageSize) : (totalCount ~/ pageSize + 1);
        final hasMore = (currentPageIndex + 1) < totalPage;

        _messageSearchCursor = (currentPageIndex + 1).toString();

        // Skip fetching conversation info if searching in a specific conversation (not first page)
        final updatedResults = (!isFirstPage && isSearchInConversation)
            ? messageResults
            : await _fetchConversationInfoForMessageResults(messageResults);

        _updateMessageResults(
          isFirstPage: isFirstPage,
          isSearchInConversation: isSearchInConversation,
          newResults: updatedResults,
          totalCount: totalCount,
          hasMore: hasMore,
        );

        return CompletionHandler();
      } else {
        return CompletionHandler()
          ..errorCode = result.code
          ..errorMessage = result.desc;
      }
    }
  }

  void _updateMessageResults({
    required bool isFirstPage,
    required bool isSearchInConversation,
    required List<MessageSearchResultItem> newResults,
    required int totalCount,
    required bool hasMore,
  }) {
    if (isFirstPage) {
      // First page: replace all results
      _messageResults = newResults;
    } else if (isSearchInConversation) {
      // Searching in a specific conversation: append messageList to existing result
      if (_messageResults.isNotEmpty && newResults.isNotEmpty) {
        final existingResult = _messageResults.first;
        final newMessageList = newResults.first.messageList;

        _messageResults = [
          MessageSearchResultItem(
            conversationID: existingResult.conversationID,
            conversationShowName: existingResult.conversationShowName,
            conversationAvatarURL: existingResult.conversationAvatarURL,
            messageCount: existingResult.messageCount + newResults.first.messageCount,
            messageList: [...existingResult.messageList, ...newMessageList],
          )
        ];
      }
    } else {
      // Searching across all conversations: append results
      _messageResults.addAll(newResults);
    }

    _messageResultTotalCount = totalCount;
    _hasMoreMessageResults = hasMore;

    _markNeedUpdate();
  }

  // Conversion Methods
  FriendSearchInfo? _convertToFriendSearchInfo(V2TimFriendInfo friendInfo) {
    if (friendInfo.userID.isEmpty) return null;

    return FriendSearchInfo(
      userID: friendInfo.userID,
      userInfo: friendInfo.userProfile != null ? ChatUtil.convertToUserFullProfile(friendInfo.userProfile!) : null,
      friendRemark: friendInfo.friendRemark,
      friendAddTime: 0,
      // SDK doesn't provide friendAddTime in V2TimFriendInfo
      friendCustomInfo: friendInfo.friendCustomInfo,
    );
  }

  GroupSearchInfo? _convertToGroupSearchInfo(V2TimGroupInfo groupInfo) {
    if (groupInfo.groupID.isEmpty) return null;

    return GroupSearchInfo(
      groupID: groupInfo.groupID,
      groupName: groupInfo.groupName ?? "",
      groupAvatarURL: groupInfo.faceUrl ?? "",
      introduction: groupInfo.introduction ?? "",
      groupType: GroupType.fromV2TIMType(groupInfo.groupType),
      memberCount: groupInfo.memberCount ?? 0,
      joinGroupApprovalType: ChatUtil.convertGroupAddOptToJoinOption(groupInfo.groupAddOpt),
      inviteToGroupApprovalType: ChatUtil.convertApproveOptToInviteOption(groupInfo.approveOpt),
    );
  }

  MessageSearchResultItem _convertToMessageSearchResultItem(V2TimMessageSearchResultItem resultItem) {
    return MessageSearchResultItem(
      conversationID: resultItem.conversationID ?? "",
      conversationShowName: "",
      conversationAvatarURL: "",
      messageCount: (resultItem.messageCount ?? 0),
      messageList: resultItem.messageList?.map((msg) => ChatUtil.convertToUIMessage(msg)).toList() ?? [],
    );
  }

  int _convertToV2TIMElemType(MessageType messageType) {
    switch (messageType) {
      case MessageType.text:
        return MessageElemType.V2TIM_ELEM_TYPE_TEXT;
      case MessageType.image:
        return MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
      case MessageType.video:
        return MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
      case MessageType.sound:
        return MessageElemType.V2TIM_ELEM_TYPE_SOUND;
      case MessageType.file:
        return MessageElemType.V2TIM_ELEM_TYPE_FILE;
      case MessageType.face:
        return MessageElemType.V2TIM_ELEM_TYPE_FACE;
      case MessageType.system:
        return MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS;
      case MessageType.custom:
        return MessageElemType.V2TIM_ELEM_TYPE_CUSTOM;
      default:
        return MessageElemType.V2TIM_ELEM_TYPE_NONE;
    }
  }

  GroupMember _convertToGroupMember(V2TimGroupMemberFullInfo memberInfo) {
    return GroupMember(
      userID: memberInfo.userID,
      nickname: memberInfo.nickName,
      avatarURL: memberInfo.faceUrl,
      nameCard: memberInfo.nameCard,
      role: GroupMemberRole.fromV2TIMRole(memberInfo.role ?? 0),
      muteUntil: memberInfo.muteUntil ?? 0,
    );
  }

  Future<List<MessageSearchResultItem>> _fetchConversationInfoForMessageResults(
      List<MessageSearchResultItem> messageResults) async {
    if (messageResults.isEmpty) {
      return messageResults;
    }

    // Collect all non-empty conversation IDs
    final conversationIDList =
        messageResults.map((result) => result.conversationID).where((id) => id.isNotEmpty).toList();

    if (conversationIDList.isEmpty) {
      return messageResults;
    }

    try {
      // Batch fetch conversations
      final conversationResult = await TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .getConversationListByConversationIds(conversationIDList: conversationIDList);

      if (conversationResult.code == 0 && conversationResult.data != null) {
        // Create a map for quick lookup
        final conversationMap = <String, dynamic>{};
        for (final conversation in conversationResult.data!) {
          conversationMap[conversation.conversationID] = conversation;
        }

        // Update results with conversation info
        final updatedResults = messageResults.map((result) {
          if (result.conversationID.isEmpty) {
            return result;
          }

          final conversation = conversationMap[result.conversationID];
          if (conversation != null) {
            return MessageSearchResultItem(
              conversationID: result.conversationID,
              conversationShowName: conversation.showName ?? "",
              conversationAvatarURL: conversation.faceUrl ?? "",
              messageCount: result.messageCount,
              messageList: result.messageList,
            );
          }

          return result;
        }).toList();

        return updatedResults;
      }
    } catch (e) {
      // Ignore errors and return original results
    }

    return messageResults;
  }
}
