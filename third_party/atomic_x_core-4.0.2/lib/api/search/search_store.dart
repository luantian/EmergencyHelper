import 'package:flutter/foundation.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/api/login/login_store.dart';
import 'package:atomic_x_core/api/message/message_list_store.dart';
import 'package:atomic_x_core/api/contact/group_setting_store.dart';
import 'package:atomic_x_core/impl/search/search_store_impl.dart';

enum KeywordListMatchType {
  or(0),
  and(1);

  final int rawValue;
  const KeywordListMatchType(this.rawValue);
}

class SearchType {
  final int rawValue;

  const SearchType._(this.rawValue);

  static const user = SearchType._(1 << 0); // 只支持云端搜索
  static const friend = SearchType._(1 << 1); // 只支持本地搜索
  static const group = SearchType._(1 << 2); // 支持云端和本地搜索
  static const groupMember = SearchType._(1 << 3); // 支持云端和本地搜索
  static const message = SearchType._(1 << 4); // 支持云端和本地搜索

  bool contains(SearchType other) {
    return (rawValue & other.rawValue) != 0;
  }

  SearchType operator |(SearchType other) {
    return SearchType._(rawValue | other.rawValue);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchType && other.rawValue == rawValue;
  }

  @override
  int get hashCode => rawValue.hashCode;
}

class UserSearchFilter {
  Gender gender;
  int minBirthday;
  int? maxBirthday;

  UserSearchFilter({
    this.gender = Gender.unknown,
    this.minBirthday = 0,
    this.maxBirthday,
  });
}

class GroupMemberSearchFilter {
  List<String> groupIDList;

  GroupMemberSearchFilter({
    this.groupIDList = const [],
  });
}

class MessageSearchFilter {
  String? conversationID;
  int searchTimePosition;
  int searchTimePeriod;
  List<String>? senderUserIDList;
  List<MessageType>? messageTypeList;

  MessageSearchFilter({
    this.conversationID,
    this.searchTimePosition = 0,
    this.searchTimePeriod = 0,
    this.senderUserIDList,
    this.messageTypeList,
  });
}

class SearchOption {
  KeywordListMatchType keywordListMatchType;
  bool isCloudSearch;
  SearchType searchType;
  int searchCount;
  UserSearchFilter? userFilter;
  GroupMemberSearchFilter? groupMemberFilter;
  MessageSearchFilter? messageFilter;

  SearchOption({
    this.keywordListMatchType = KeywordListMatchType.or,
    this.isCloudSearch = false,
    SearchType? searchType,
    this.searchCount = 20,
    this.userFilter,
    this.groupMemberFilter,
    this.messageFilter,
  }) : searchType = searchType ?? 
        (SearchType.friend | SearchType.message | SearchType.group | SearchType.groupMember);
}

class FriendSearchInfo {
  String userID;
  String? friendRemark;
  int friendAddTime;
  Map<String, dynamic>? friendCustomInfo;
  UserProfile? userInfo;

  FriendSearchInfo({
    required this.userID,
    this.friendRemark,
    this.friendAddTime = 0,
    this.friendCustomInfo,
    this.userInfo,
  });
}

class GroupSearchInfo {
  String groupID;
  GroupType groupType;
  String groupName;
  int memberCount;
  String groupAvatarURL;
  String introduction;
  GroupJoinOption joinGroupApprovalType;
  GroupJoinOption inviteToGroupApprovalType;

  GroupSearchInfo({
    required this.groupID,
    this.groupType = GroupType.work,
    required this.groupName,
    this.memberCount = 0,
    required this.groupAvatarURL,
    required this.introduction,
    this.joinGroupApprovalType = GroupJoinOption.forbid,
    this.inviteToGroupApprovalType = GroupJoinOption.forbid,
  });
}

class MessageSearchResultItem {
  String conversationID;
  String conversationShowName;
  String conversationAvatarURL;
  int messageCount;
  List<MessageInfo> messageList;

  MessageSearchResultItem({
    required this.conversationID,
    required this.conversationShowName,
    required this.conversationAvatarURL,
    required this.messageCount,
    required this.messageList,
  });
}

class SearchState {
  List<UserProfile> userList;
  int userTotalCount;
  bool hasMoreUserList;

  List<FriendSearchInfo> friendList;
  int friendTotalCount;
  bool hasMoreFriendList;

  List<GroupSearchInfo> groupList;
  int groupTotalCount;
  bool hasMoreGroupList;

  Map<String, List<GroupMember>> groupMemberList;
  int groupMemberTotalCount;
  bool hasMoreGroupMemberList;

  List<MessageSearchResultItem> messageResults;
  int messageResultTotalCount;
  bool hasMoreMessageResults;

  SearchState({
    this.userList = const [],
    this.userTotalCount = 0,
    this.hasMoreUserList = true,
    this.friendList = const [],
    this.friendTotalCount = 0,
    this.hasMoreFriendList = true,
    this.groupList = const [],
    this.groupTotalCount = 0,
    this.hasMoreGroupList = true,
    this.groupMemberList = const {},
    this.groupMemberTotalCount = 0,
    this.hasMoreGroupMemberList = true,
    this.messageResults = const [],
    this.messageResultTotalCount = 0,
    this.hasMoreMessageResults = true,
  });
}

abstract class SearchStore extends ChangeNotifier {
  SearchState get searchState;

  static SearchStore create() {
    return SearchStoreImpl();
  }

  Future<CompletionHandler> search({
    required List<String> keywordList,
    required SearchOption option,
  });

  Future<CompletionHandler> searchMore({required SearchType searchType});
}
