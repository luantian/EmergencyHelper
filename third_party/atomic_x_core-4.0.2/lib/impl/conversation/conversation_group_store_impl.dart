import 'package:atomic_x_core/api/conversation/conversation_group_store.dart';
import 'package:atomic_x_core/api/define.dart';
import 'package:atomic_x_core/impl/common/data_report.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimConversationListener.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_imsdk_bindings_generated.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class ConversationGroupStoreImpl extends ConversationGroupStore {
  List<String> _groupList = [];
  ConversationGroupState? _conversationGroupState;
  bool _needUpdate = true;
  bool _disposed = false;
  V2TimConversationListener? _conversationListener;

  ConversationGroupStoreImpl() {
    _addConversationListener();
  }

  void _addConversationListener() {
    _conversationListener = V2TimConversationListener(
      onConversationGroupCreated: (groupName, conversationList) {
        _addGroupIfNeeded(groupName);
      },
      onConversationGroupDeleted: (groupName) {
        _groupList.remove(groupName);
        _markNeedUpdate();
      },
      onConversationGroupNameChanged: (oldName, newName) {
        final index = _groupList.indexOf(oldName);
        if (index != -1) {
          _groupList[index] = newName;
          _markNeedUpdate();
        }
      },
    );

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

  void _addGroupIfNeeded(String groupName) {
    if (groupName.isEmpty) {
      return;
    }
    if (!_groupList.contains(groupName)) {
      _groupList.add(groupName);
      _markNeedUpdate();
    }
  }

  @override
  ConversationGroupState get conversationGroupState {
    if (_needUpdate || _conversationGroupState == null) {
      _conversationGroupState = ConversationGroupState(
        groupList: List.unmodifiable(_groupList),
      );
      _needUpdate = false;
    }
    return _conversationGroupState!;
  }

  void _markNeedUpdate() {
    if (_disposed) return;
    _needUpdate = true;
    notifyListeners();
  }

  @override
  Future<CompletionHandler> fetchGroupList() async {
    DataReport.reportAtomicMetrics(AtomicMetrics.conversationGroup);

    final handler = CompletionHandler();

    try {
      final result = await TencentImSDKPlugin.v2TIMManager.getConversationManager().getConversationGroupList();

      if (result.code == 0 && result.data != null) {
        _groupList = List<String>.from(result.data!);
        _markNeedUpdate();
      } else {
        handler.errorCode = result.code;
        handler.errorMessage = result.desc ?? '';
      }
    } catch (e) {
      handler.errorCode = -1;
      handler.errorMessage = e.toString();
    }

    return handler;
  }

  @override
  Future<CompletionHandler> createGroup({
    required String groupName,
    required List<String> conversationIDList,
  }) async {
    final handler = CompletionHandler();

    if (groupName.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Group name is empty";
      return handler;
    }

    if (conversationIDList.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Conversation ID list is empty";
      return handler;
    }

    try {
      final result = await TencentImSDKPlugin.v2TIMManager.getConversationManager().createConversationGroup(
            groupName: groupName,
            conversationIDList: conversationIDList,
          );

      if (result.code == 0) {
        _addGroupIfNeeded(groupName);
      } else {
        handler.errorCode = result.code;
        handler.errorMessage = result.desc ?? '';
      }
    } catch (e) {
      handler.errorCode = -1;
      handler.errorMessage = e.toString();
    }

    return handler;
  }

  @override
  Future<CompletionHandler> deleteGroup({required String groupName}) async {
    final handler = CompletionHandler();

    if (groupName.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Group name is empty";
      return handler;
    }

    try {
      final result =
          await TencentImSDKPlugin.v2TIMManager.getConversationManager().deleteConversationGroup(groupName: groupName);

      if (result.code != 0) {
        handler.errorCode = result.code;
        handler.errorMessage = result.desc ?? '';
      }
    } catch (e) {
      handler.errorCode = -1;
      handler.errorMessage = e.toString();
    }

    return handler;
  }

  @override
  Future<CompletionHandler> renameGroup({
    required String oldName,
    required String newName,
  }) async {
    final handler = CompletionHandler();

    if (oldName.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Old group name is empty";
      return handler;
    }

    if (newName.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "New group name is empty";
      return handler;
    }

    try {
      final result = await TencentImSDKPlugin.v2TIMManager.getConversationManager().renameConversationGroup(
            oldName: oldName,
            newName: newName,
          );

      if (result.code != 0) {
        handler.errorCode = result.code;
        handler.errorMessage = result.desc ?? '';
      }
    } catch (e) {
      handler.errorCode = -1;
      handler.errorMessage = e.toString();
    }

    return handler;
  }

  @override
  Future<CompletionHandler> addConversationsToGroup({
    required String groupName,
    required List<String> conversationIDList,
  }) async {
    final handler = CompletionHandler();

    if (groupName.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Group name is empty";
      return handler;
    }

    if (conversationIDList.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Conversation ID list is empty";
      return handler;
    }

    try {
      final result = await TencentImSDKPlugin.v2TIMManager.getConversationManager().addConversationsToGroup(
            groupName: groupName,
            conversationIDList: conversationIDList,
          );

      if (result.code != 0) {
        handler.errorCode = result.code;
        handler.errorMessage = result.desc ?? '';
      }
    } catch (e) {
      handler.errorCode = -1;
      handler.errorMessage = e.toString();
    }

    return handler;
  }

  @override
  Future<CompletionHandler> deleteConversationsFromGroup({
    required String groupName,
    required List<String> conversationIDList,
  }) async {
    final handler = CompletionHandler();

    if (groupName.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Group name is empty";
      return handler;
    }

    if (conversationIDList.isEmpty) {
      handler.errorCode = TIMErrCode.ERR_INVALID_PARAMETERS.value;
      handler.errorMessage = "Conversation ID list is empty";
      return handler;
    }

    try {
      final result = await TencentImSDKPlugin.v2TIMManager.getConversationManager().deleteConversationsFromGroup(
            groupName: groupName,
            conversationIDList: conversationIDList,
          );

      if (result.code != 0) {
        handler.errorCode = result.code;
        handler.errorMessage = result.desc ?? '';
      }
    } catch (e) {
      handler.errorCode = -1;
      handler.errorMessage = e.toString();
    }

    return handler;
  }

  @override
  void dispose() {
    _disposed = true;
    _removeConversationListener();
    super.dispose();
  }
}
