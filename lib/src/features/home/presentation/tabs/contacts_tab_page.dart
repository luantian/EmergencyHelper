import 'dart:convert';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/event/presentation/event_transfer_picker_page.dart';
import 'package:emergency_helper/src/features/trtc/data/trtc_service.dart';
import 'package:emergency_helper/src/features/trtc/presentation/trtc_call_route_extra.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactsTabPage extends StatefulWidget {
  const ContactsTabPage({super.key});

  @override
  State<ContactsTabPage> createState() => _ContactsTabPageState();
}

class _ContactsTabPageState extends State<ContactsTabPage> {
  final TrtcService _trtcService = const TrtcService();
  final Set<String> _expandedNodeIds = <String>{};
  late final TextEditingController _searchController;
  List<ContactGroup> _contactTree = contactTreeData();
  String _searchKeyword = '';
  bool _loading = false;
  String? _loadError;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    Future<void>.microtask(_loadContacts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _normalizeText(_searchKeyword);
    final autoExpandedIds = _collectSearchExpandedIds(normalizedQuery);
    final visibleRows = _buildVisibleRows(normalizedQuery, autoExpandedIds);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('\u901A\u8BAF\u5F55'),
        actions: [
          PopupMenuButton<_ContactTreeMenuAction>(
            tooltip: '\u66F4\u591A\u64CD\u4F5C',
            color: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 8,
            offset: const Offset(0, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFDCE5F1)),
            ),
            onSelected: (action) {
              switch (action) {
                case _ContactTreeMenuAction.expandAll:
                  _expandAll();
                case _ContactTreeMenuAction.collapseAll:
                  _collapseAll();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<_ContactTreeMenuAction>(
                value: _ContactTreeMenuAction.expandAll,
                height: 40,
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 18,
                      color: Color(0xFF42566D),
                    ),
                    SizedBox(width: 10),
                    Text('\u5168\u90E8\u5C55\u5F00'),
                  ],
                ),
              ),
              PopupMenuItem<_ContactTreeMenuAction>(
                value: _ContactTreeMenuAction.collapseAll,
                height: 40,
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.unfold_less_rounded,
                      size: 18,
                      color: Color(0xFF42566D),
                    ),
                    SizedBox(width: 10),
                    Text('\u5168\u90E8\u6536\u8D77'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: AppLoadingOverlay(
        loading: _loading,
        message: '\u6B63\u5728\u52A0\u8F7D\u901A\u8BAF\u5F55...',
        child: Column(
          children: [
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6E8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF2C67A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFC6781B),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _loadError!,
                          style: const TextStyle(
                            color: Color(0xFF8A5A14),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadContacts,
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('\u91CD\u8BD5'),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '\u641C\u7D22\u59D3\u540D/\u5C97\u4F4D',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchKeyword.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '\u6E05\u7A7A\u641C\u7D22',
                          onPressed: _clearSearch,
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFDCE4EF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFDCE4EF)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: visibleRows.isEmpty
                  ? const _EmptySearchResult()
                  : ListView.builder(
                      key: const Key('contacts-tree-list'),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: visibleRows.length,
                      itemBuilder: (context, index) {
                        final row = visibleRows[index];
                        if (row is _GroupRow) {
                          final group = row.group;
                          final hasChildren =
                              group.children.isNotEmpty ||
                              group.contacts.isNotEmpty;
                          final contactCount = _countContactsInGroup(group);
                          return _GroupTile(
                            key: ValueKey(group.id),
                            group: group,
                            depth: row.depth,
                            isExpanded: row.isExpanded,
                            isMatched: row.isMatched,
                            hasChildren: hasChildren,
                            contactCount: contactCount,
                            keyword: _searchKeyword,
                            onTap: hasChildren
                                ? () => _toggleGroup(group.id)
                                : null,
                          );
                        }
                        final personRow = row as _ContactRow;
                        return _ContactTile(
                          key: ValueKey('${personRow.contact.id}-tile'),
                          contact: personRow.contact,
                          depth: personRow.depth,
                          keyword: _searchKeyword,
                          isMatched: personRow.isMatched,
                          onVideoCall: () => _startVideoCall(personRow.contact),
                          onCall: () => _callContact(personRow.contact),
                          onCopyPhone: () => _copyContactPhone(personRow.contact),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchKeyword = value;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _toggleGroup(String groupId) {
    setState(() {
      if (_expandedNodeIds.contains(groupId)) {
        _expandedNodeIds.remove(groupId);
      } else {
        _expandedNodeIds.add(groupId);
      }
    });
  }

  void _expandAll() {
    setState(() {
      _expandedNodeIds
        ..clear()
        ..addAll(_collectAllGroupIds(_contactTree));
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedNodeIds.clear();
    });
  }

  Future<void> _loadContacts() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final dependencies = context.read<AppDependencies>();
      final remoteTree = await fetchContactTreeFromApi(dependencies.apiClient);
      if (!mounted) {
        return;
      }
      setState(() {
        _contactTree = remoteTree.isEmpty ? contactTreeData() : remoteTree;
        _expandedNodeIds.clear();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError =
            '\u63A5\u53E3\u52A0\u8F7D\u5931\u8D25\uFF0C\u5DF2\u4F7F\u7528\u672C\u5730\u901A\u8BAF\u5F55\u6570\u636E';
      });
    }
  }

  Future<void> _callContact(ContactPerson contact) async {
    final userId = contact.userId?.trim();
    if (userId == null || userId.isEmpty) {
      _showSnackBar(
        '\u8054\u7CFB\u4EBA\u7F3A\u5C11\u7528\u6237ID\uFF0C\u65E0\u6CD5\u67E5\u8BE2\u7535\u8BDD',
      );
      return;
    }

    final apiClient = context.read<AppDependencies>().apiClient;
    final localPhoneRaw = contact.phone.trim();
    String remotePhoneRaw = '';
    String? queryErrorMessage;
    try {
      final remotePhone = await fetchUserPhoneById(apiClient, userId);
      remotePhoneRaw = (remotePhone ?? '').trim();
    } on AppException catch (error) {
      queryErrorMessage = error.message;
    } catch (_) {
      queryErrorMessage =
          '\u67E5\u8BE2\u7535\u8BDD\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5';
    }

    // Keep the required flow: query detail endpoint first.
    // If detail endpoint has no phone/invalid phone, fallback to local contact data.
    final remoteDialPhone = _normalizeDialPhone(remotePhoneRaw);
    final localDialPhone = _normalizeDialPhone(localPhoneRaw);
    final phone = remoteDialPhone ?? localDialPhone;
    if (phone == null) {
      final hasRemoteText =
          remotePhoneRaw.isNotEmpty &&
          remotePhoneRaw != '--' &&
          remotePhoneRaw.toLowerCase() != 'null';
      final hasLocalText =
          localPhoneRaw.isNotEmpty &&
          localPhoneRaw != '--' &&
          localPhoneRaw.toLowerCase() != 'null';
      _showSnackBar(
        hasRemoteText || hasLocalText
            ? '\u67E5\u8BE2\u5230\u7684\u53F7\u7801\u4E0D\u53EF\u62E8\u6253\uFF0C\u8BF7\u6838\u5BF9\u53F7\u7801\u683C\u5F0F'
            : '\u8BE5\u8054\u7CFB\u4EBA\u672A\u914D\u7F6E\u8054\u7CFB\u7535\u8BDD',
      );
      return;
    }
    if (queryErrorMessage != null &&
        remoteDialPhone == null &&
        localDialPhone != null) {
      _showSnackBar(
        '\u8BE6\u60C5\u67E5\u53F7\u5F02\u5E38\uFF0C\u5DF2\u4F7F\u7528\u901A\u8BAF\u5F55\u53F7\u7801',
      );
    }

    final confirmed = await _confirmDial(contact.name, phone);
    if (!confirmed) {
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!mounted || launched) {
      return;
    }

    _showSnackBar('\u65E0\u6CD5\u62C9\u8D77\u62E8\u53F7\uFF1A$phone');
  }

  Future<void> _startVideoCall(ContactPerson contact) async {
    final userId = contact.userId?.trim();
    if (userId == null || userId.isEmpty) {
      _showSnackBar('联系人缺少用户ID，无法发起视频通话');
      return;
    }

    final currentUserId = await _ensureCurrentUserId();
    if (currentUserId == null || currentUserId.isEmpty) {
      _showSnackBar('未获取到当前登录用户ID，暂时无法发起视频通话');
      return;
    }

    if (userId == currentUserId) {
      _showSnackBar('不能和自己发起视频通话');
      return;
    }

    if (!mounted) {
      return;
    }

    final callType = await _showCallTypeDialog();
    if (callType == null || !mounted) {
      return;
    }

    final initialContact = _ContactInfo(
      userId: userId,
      name: contact.name,
      title: contact.title,
      department: _findDepartmentNameByContactId(contact.id) ?? '',
      phone: contact.phone,
    );

    if (callType == _CallType.single) {
      await _initiateSingleCall(initialContact);
    } else {
      await _pickMultiMembersAndCall(<_ContactInfo>[initialContact]);
    }
  }

  Future<void> _initiateSingleCall(_ContactInfo contact) async {
    final targetId = contact.userId.trim();
    if (targetId.isEmpty) {
      _showSnackBar('联系人信息不完整');
      return;
    }

    final selfId = await _ensureCurrentUserId();
    if (selfId == null || selfId.isEmpty) {
      _showSnackBar('未获取到当前用户ID');
      return;
    }

    if (!mounted) return;

    final extra = TrtcCallRouteExtra(
      calleeUserId: targetId,
      calleeName: contact.name,
      calleeTitles: <String>[contact.title],
      calleeDepartments: <String>[contact.department],
      calleePhones: <String>[contact.phone],
    );

    context.push(RoutePaths.trtcCallNew, extra: extra);
  }

  Future<_CallType?> _showCallTypeDialog() async {
    return showDialog<_CallType>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final maxHeight = MediaQuery.of(dialogContext).size.height * 0.72;
        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 430, maxHeight: maxHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x2B1B3556),
                      blurRadius: 26,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: <Color>[
                              Color(0xFF4E99F1),
                              Color(0xFF2B73CC),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: const <Widget>[
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Color(0x40FFFFFF),
                              child: Icon(
                                Icons.video_call_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '选择通话类型',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '请选择本次通话方式',
                        style: TextStyle(
                          color: Color(0xFF1F2B3A),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '单人适合一对一沟通，多人可邀请多位成员参会',
                        style: TextStyle(
                          color: Color(0xFF6E7D90),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _CallTypeChoiceCard(
                        icon: Icons.person_rounded,
                        title: '单人视频通话',
                        subtitle: '与当前联系人 1 对 1 沟通',
                        accentColor: const Color(0xFF3F86E3),
                        onTap: () =>
                            Navigator.of(dialogContext).pop(_CallType.single),
                      ),
                      const SizedBox(height: 10),
                      _CallTypeChoiceCard(
                        icon: Icons.groups_rounded,
                        title: '多人视频通话',
                        subtitle: '选择多位成员后发起群呼',
                        accentColor: const Color(0xFF2B73CC),
                        onTap: () =>
                            Navigator.of(dialogContext).pop(_CallType.multi),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF7A8798),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text(
                            '取消',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickMultiMembersAndCall(
    List<_ContactInfo> initialContacts,
  ) async {
    final selectedIds = initialContacts
        .map((c) => int.tryParse(c.userId))
        .whereType<int>()
        .toList(growable: false);

    final selection = await Navigator.of(context).push<EventTransferSelection>(
      MaterialPageRoute<EventTransferSelection>(
        builder: (_) => EventTransferPickerPage(
          eventId: 'trtc',
          checkPermission: false,
          titleText: '选择参会人员',
          confirmButtonText: '确认发起',
          emptySelectionHint: '请至少选择一位成员',
          initialSelectedUserIds: selectedIds,
          showContentField: false,
        ),
      ),
    );

    if (!mounted || selection == null || selection.userIds.isEmpty) {
      return;
    }

    final contacts = <_ContactInfo>[];
    for (var i = 0; i < selection.userIds.length; i++) {
      final uId = selection.userIds[i].toString();
      final name = i < selection.userNames.length
          ? selection.userNames[i].trim()
          : '';
      final title = i < selection.userTitles.length
          ? selection.userTitles[i].trim()
          : '';
      final department = i < selection.userDepartments.length
          ? selection.userDepartments[i].trim()
          : '';
      final phone = i < selection.userPhones.length
          ? selection.userPhones[i].trim()
          : '';
      contacts.add(
        _ContactInfo(
          userId: uId,
          name: name,
          title: title,
          department: department,
          phone: phone,
        ),
      );
    }

    await _navigateToCallPage(contacts);
  }

  Future<void> _navigateToCallPage(List<_ContactInfo> contacts) async {
    if (contacts.isEmpty) {
      _showSnackBar('请选择成员');
      return;
    }

    final userIds = contacts
        .map((c) => c.userId.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final names = contacts.map((c) => c.name.trim()).toList();
    final titles = contacts.map((c) => c.title.trim()).toList();
    final departments = contacts.map((c) => c.department.trim()).toList();
    final phones = contacts.map((c) => c.phone.trim()).toList();

    if (userIds.isEmpty) {
      _showSnackBar('成员信息不完整');
      return;
    }

    final extra = TrtcCallRouteExtra(
      calleeUserId: userIds.first,
      calleeName: names.isNotEmpty ? names.first : '',
      calleeUserIds: userIds,
      calleeNames: names,
      calleeTitles: titles,
      calleeDepartments: departments,
      calleePhones: phones,
    );

    if (!mounted) return;
    context.push(RoutePaths.trtcCallNew, extra: extra);
  }

  String? _findDepartmentNameByContactId(String contactId) {
    String? visit(List<ContactGroup> groups) {
      for (final group in groups) {
        final matched = group.contacts.where(
          (person) => person.id == contactId,
        );
        if (matched.isNotEmpty) {
          final personDepartment = _normalizeDepartmentName(
            matched.first.department,
          );
          if (personDepartment != null) {
            return personDepartment;
          }
          return _normalizeDepartmentName(group.name);
        }
        final nested = visit(group.children);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
      return null;
    }

    return visit(_contactTree);
  }

  String? _normalizeDepartmentName(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final compact = text.replaceAll(' ', '');
    if (compact == '\u672A\u5206\u914D\u4EBA\u5458' ||
        compact == '\u672A\u5206\u914D') {
      return null;
    }
    return text;
  }

  Future<String?> _ensureCurrentUserId() async {
    final cached = _currentUserId?.trim();
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final dependencies = context.read<AppDependencies>();
    var sessionInfo = await dependencies.authService.getCachedPermissionInfo();
    sessionInfo ??= await dependencies.authService
        .fetchPermissionInfoAndCache();

    final resolved = _trtcService.extractCurrentUserId(sessionInfo)?.trim();
    if (resolved == null || resolved.isEmpty) {
      return null;
    }

    _currentUserId = resolved;
    return resolved;
  }

  Future<bool> _confirmDial(String name, String phone) async {
    if (!mounted) {
      return false;
    }
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _DialConfirmDialog(name: name, phone: phone),
    );
    return result ?? false;
  }

  Future<void> _copyContactPhone(ContactPerson contact) async {
    final phone = contact.phone.trim();
    if (phone.isEmpty || phone == '--') {
      _showSnackBar('无可用电话号码');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: phone));
      _showSnackBar('已复制：$phone');
    } catch (_) {
      _showSnackBar('复制失败');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    AppCenterToast.show(context, message);
  }

  String? _normalizeDialPhone(String rawPhone) {
    final compact = rawPhone.trim();
    if (compact.isEmpty || compact == '--' || compact.toLowerCase() == 'null') {
      return null;
    }
    final candidates = compact.split(RegExp(r'[;,/|]+'));
    for (final candidate in candidates) {
      var normalized = candidate
          .trim()
          .replaceAll(RegExp(r'[\s\-()]'), '')
          .replaceAll('\u00A0', '');
      if (normalized.isEmpty || normalized.contains('*')) {
        continue;
      }
      if (normalized.startsWith('+86')) {
        normalized = normalized.substring(3);
      } else if (normalized.startsWith('86') &&
          normalized.length > 11 &&
          RegExp(r'^86\d+$').hasMatch(normalized)) {
        normalized = normalized.substring(2);
      }

      if (RegExp(r'^1\d{10}$').hasMatch(normalized)) {
        return normalized;
      }
      if (RegExp(r'^0\d{9,11}$').hasMatch(normalized)) {
        return normalized;
      }
      if (RegExp(r'^400\d{7}$').hasMatch(normalized)) {
        return normalized;
      }
      if (RegExp(r'^\d{7,8}$').hasMatch(normalized)) {
        return normalized;
      }
    }

    final mobileMatch = RegExp(r'(?:\+?86)?1\d{10}').firstMatch(compact);
    if (mobileMatch != null) {
      final normalized = mobileMatch.group(0)!.replaceAll('+86', '');
      if (RegExp(r'^1\d{10}$').hasMatch(normalized)) {
        return normalized;
      }
    }

    final landlineMatch = RegExp(r'0\d{2,3}[- ]?\d{7,8}').firstMatch(compact);
    if (landlineMatch != null) {
      return landlineMatch.group(0)!.replaceAll(RegExp(r'[- ]'), '');
    }

    final serviceMatch = RegExp(r'400[- ]?\d{3}[- ]?\d{4}').firstMatch(compact);
    if (serviceMatch != null) {
      return serviceMatch.group(0)!.replaceAll(RegExp(r'[- ]'), '');
    }
    return null;
  }

  List<_VisibleRow> _buildVisibleRows(
    String normalizedQuery,
    Set<String> autoExpandedIds,
  ) {
    final rows = <_VisibleRow>[];
    for (final group in _contactTree) {
      _appendGroupRows(rows, group, 0, normalizedQuery, autoExpandedIds);
    }
    return rows;
  }

  bool _appendGroupRows(
    List<_VisibleRow> rows,
    ContactGroup group,
    int depth,
    String normalizedQuery,
    Set<String> autoExpandedIds,
  ) {
    final hasQuery = normalizedQuery.isNotEmpty;
    final groupMatched = _matchesText(group.name, normalizedQuery);

    final visibleContacts = hasQuery
        ? group.contacts
              .where((item) => _contactMatches(item, normalizedQuery))
              .toList()
        : group.contacts;

    final visibleChildren = hasQuery
        ? group.children
              .where((item) => _groupHasMatches(item, normalizedQuery))
              .toList()
        : group.children;

    if (hasQuery &&
        !groupMatched &&
        visibleContacts.isEmpty &&
        visibleChildren.isEmpty) {
      return false;
    }

    final isExpanded =
        _expandedNodeIds.contains(group.id) ||
        autoExpandedIds.contains(group.id);

    rows.add(
      _GroupRow(
        group: group,
        depth: depth,
        isExpanded: isExpanded,
        isMatched: groupMatched,
      ),
    );

    if (!isExpanded) {
      return true;
    }

    for (final contact in visibleContacts) {
      rows.add(
        _ContactRow(
          contact: contact,
          depth: depth + 1,
          isMatched: _contactMatches(contact, normalizedQuery),
        ),
      );
    }

    for (final child in visibleChildren) {
      _appendGroupRows(
        rows,
        child,
        depth + 1,
        normalizedQuery,
        autoExpandedIds,
      );
    }

    return true;
  }

  bool _groupHasMatches(ContactGroup group, String normalizedQuery) {
    if (_matchesText(group.name, normalizedQuery)) {
      return true;
    }

    if (group.contacts.any((item) => _contactMatches(item, normalizedQuery))) {
      return true;
    }

    return group.children.any(
      (item) => _groupHasMatches(item, normalizedQuery),
    );
  }

  Set<String> _collectSearchExpandedIds(String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return <String>{};
    }

    final ids = <String>{};
    for (final group in _contactTree) {
      _collectSearchExpandedIdsFromGroup(group, normalizedQuery, ids);
    }
    return ids;
  }

  bool _collectSearchExpandedIdsFromGroup(
    ContactGroup group,
    String normalizedQuery,
    Set<String> ids,
  ) {
    final groupMatched = _matchesText(group.name, normalizedQuery);
    final contactMatched = group.contacts.any(
      (item) => _contactMatches(item, normalizedQuery),
    );

    var childMatched = false;
    for (final child in group.children) {
      if (_collectSearchExpandedIdsFromGroup(child, normalizedQuery, ids)) {
        childMatched = true;
      }
    }

    final hasMatch = groupMatched || contactMatched || childMatched;
    if (hasMatch) {
      ids.add(group.id);
    }
    return hasMatch;
  }

  bool _contactMatches(ContactPerson contact, String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return false;
    }

    return _matchesText(contact.name, normalizedQuery) ||
        _matchesText(contact.title, normalizedQuery);
  }

  bool _matchesText(String source, String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return false;
    }

    return _normalizeText(source).contains(normalizedQuery);
  }

  String _normalizeText(String value) {
    return value.trim().toLowerCase();
  }

  int _countContacts(List<ContactGroup> groups) {
    var count = 0;
    for (final group in groups) {
      count += group.contacts.length + _countContacts(group.children);
    }
    return count;
  }

  int _countContactsInGroup(ContactGroup group) {
    return group.contacts.length + _countContacts(group.children);
  }

  Set<String> _collectAllGroupIds(List<ContactGroup> groups) {
    final ids = <String>{};
    for (final group in groups) {
      ids.add(group.id);
      ids.addAll(_collectAllGroupIds(group.children));
    }
    return ids;
  }
}

enum _ContactTreeMenuAction { expandAll, collapseAll }

enum _CallType { single, multi }

class _ContactInfo {
  const _ContactInfo({
    required this.userId,
    required this.name,
    this.title = '',
    this.department = '',
    this.phone = '',
  });

  final String userId;
  final String name;
  final String title;
  final String department;
  final String phone;
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    super.key,
    required this.group,
    required this.depth,
    required this.isExpanded,
    required this.isMatched,
    required this.hasChildren,
    required this.contactCount,
    required this.keyword,
    required this.onTap,
  });

  final ContactGroup group;
  final int depth;
  final bool isExpanded;
  final bool isMatched;
  final bool hasChildren;
  final int contactCount;
  final String keyword;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final leftPadding = 8.0 + depth * 12.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMatched ? const Color(0xFFFFD66B) : const Color(0xFFE3E8F1),
          width: isMatched ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(leftPadding, 10, 12, 10),
          child: Row(
            children: [
              Icon(
                hasChildren
                    ? (isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right)
                    : Icons.circle_outlined,
                color: AppTheme.primaryBlue,
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.apartment_outlined,
                color: AppTheme.primaryBlue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: group.name,
                      keyword: keyword,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E3440),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.children.length}\u4E2A\u4E0B\u7EA7\u7EC4\u7EC7 \u00B7 $contactCount\u4EBA',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF768294),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    super.key,
    required this.contact,
    required this.depth,
    required this.keyword,
    required this.isMatched,
    required this.onVideoCall,
    required this.onCall,
    required this.onCopyPhone,
  });

  final ContactPerson contact;
  final int depth;
  final String keyword;
  final bool isMatched;
  final Future<void> Function() onVideoCall;
  final Future<void> Function() onCall;
  final Future<void> Function() onCopyPhone;

  @override
  Widget build(BuildContext context) {
    final leftPadding = 28.0 + depth * 12.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isMatched ? const Color(0xFFFFF9E8) : const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMatched ? const Color(0xFFFFD66B) : const Color(0xFFE6EBF3),
          width: isMatched ? 1.2 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(leftPadding, 8, 8, 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFE8F0FC),
              child: Text(
                _safeFirstChar(contact.name),
                style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightedText(
                    text: contact.name,
                    keyword: keyword,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D3442),
                    ),
                  ),
                  const SizedBox(height: 2),
                  _HighlightedText(
                    text: contact.title,
                    keyword: keyword,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF778396),
                    ),
                  ),
                  if (contact.phone != '--' && contact.phone.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 12,
                          color: Color(0xFF778396),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _HighlightedText(
                            text: contact.phone,
                            keyword: keyword,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF778396),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: () async => onVideoCall(),
              icon: const Icon(
                Icons.videocam_outlined,
                color: AppTheme.primaryBlue,
              ),
              tooltip: '\u89C6\u9891\u901A\u8BDD',
            ),
            IconButton(
              onPressed: () async => onCall(),
              icon: const Icon(
                Icons.call_outlined,
                color: AppTheme.primaryBlue,
              ),
              tooltip: '\u62E8\u6253\u7535\u8BDD',
            ),
            if (contact.phone != '--' && contact.phone.isNotEmpty)
              IconButton(
                onPressed: () async => onCopyPhone(),
                icon: const Icon(
                  Icons.content_copy_outlined,
                  color: AppTheme.primaryBlue,
                ),
                tooltip: '\u590D\u5236\u7535\u8BDD',
              ),
          ],
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.keyword,
    required this.style,
  });

  final String text;
  final String keyword;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final normalizedText = text.toLowerCase();
    final matchIndex = normalizedText.indexOf(normalizedKeyword);
    if (matchIndex < 0) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    var start = 0;

    while (start < text.length) {
      final index = normalizedText.indexOf(normalizedKeyword, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      final end = index + normalizedKeyword.length;
      spans.add(
        TextSpan(
          text: text.substring(index, end),
          style: style.copyWith(
            backgroundColor: const Color(0xFFFFD66B),
            color: const Color(0xFF2B2B2B),
            fontWeight: FontWeight.w700,
          ),
        ),
      );

      start = end;
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: style, children: spans),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '\u672A\u627E\u5230\u5339\u914D\u8054\u7CFB\u4EBA',
        style: TextStyle(
          color: Color(0xFF7A8698),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _CallTypeChoiceCard extends StatelessWidget {
  const _CallTypeChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD6E3F5)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1E2A39),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF738195),
                        fontSize: 12.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialConfirmDialog extends StatelessWidget {
  const _DialConfirmDialog({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 430, maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x2B1B3556),
                  blurRadius: 26,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF4E99F1), Color(0xFF2B73CC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: const <Widget>[
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(0x40FFFFFF),
                          child: Icon(
                            Icons.call_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '确认拨打电话',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FBFF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD6E3F5)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5F1FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _safeFirstChar(name, fallback: '联'),
                            style: const TextStyle(
                              color: Color(0xFF2C6EC4),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF1F2B3A),
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                '即将发起系统电话呼叫',
                                style: TextStyle(
                                  color: Color(0xFF7A889A),
                                  fontSize: 12.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F9FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD3E6FC)),
                    ),
                    child: Text(
                      phone,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF153E73),
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            side: const BorderSide(color: Color(0xFFD3DCE8)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            '取消',
                            style: TextStyle(
                              color: Color(0xFF5E6E82),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            backgroundColor: const Color(0xFF2B73CC),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.call_rounded, size: 18),
                          label: const Text(
                            '立即拨打',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _safeFirstChar(String text, {String fallback = '?'}) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return fallback;
  }
  return normalized.substring(0, 1);
}

class ContactGroup {
  const ContactGroup({
    required this.id,
    required this.name,
    this.children = const [],
    this.contacts = const [],
  });

  final String id;
  final String name;
  final List<ContactGroup> children;
  final List<ContactPerson> contacts;
}

class ContactPerson {
  const ContactPerson({
    required this.id,
    this.userId,
    required this.name,
    required this.title,
    required this.phone,
    this.department = '',
  });

  final String id;
  final String? userId;
  final String name;
  final String title;
  final String phone;
  final String department;
}

sealed class _VisibleRow {
  const _VisibleRow(this.depth);

  final int depth;
}

class _GroupRow extends _VisibleRow {
  const _GroupRow({
    required this.group,
    required int depth,
    required this.isExpanded,
    required this.isMatched,
  }) : super(depth);

  final ContactGroup group;
  final bool isExpanded;
  final bool isMatched;
}

class _ContactRow extends _VisibleRow {
  const _ContactRow({
    required this.contact,
    required int depth,
    required this.isMatched,
  }) : super(depth);

  final ContactPerson contact;
  final bool isMatched;
}

const List<ContactGroup> _fallbackContactTree = [
  ContactGroup(
    id: 'emergency-command',
    name: '\u5E94\u6025\u6307\u6325\u90E8',
    children: [
      ContactGroup(
        id: 'emergency-command-duty',
        name: '\u503C\u73ED\u7EC4',
        contacts: [
          ContactPerson(
            id: 'liu-zhiyong',
            name: '\u5218\u5FD7\u52C7',
            title: '\u503C\u73ED\u4E3B\u4EFB',
            phone: '13100010001',
          ),
          ContactPerson(
            id: 'li-min',
            name: '\u674E\u654F',
            title: '\u5E94\u6025\u8C03\u5EA6\u5458',
            phone: '13100010002',
          ),
        ],
      ),
      ContactGroup(
        id: 'emergency-command-disposal',
        name: '\u5904\u7F6E\u7EC4',
        contacts: [
          ContactPerson(
            id: 'wang-jianjun',
            name: '\u738B\u5EFA\u519B',
            title: '\u7EC4\u957F',
            phone: '13100010003',
          ),
        ],
        children: [
          ContactGroup(
            id: 'emergency-command-disposal-a',
            name: '\u673A\u52A8\u5904\u7F6E\u961FA',
            contacts: [
              ContactPerson(
                id: 'zhou-qiang',
                name: '\u5468\u5F3A',
                title: '\u961F\u957F',
                phone: '13100010004',
              ),
              ContactPerson(
                id: 'gao-yan',
                name: '\u9AD8\u5CA9',
                title: '\u961F\u5458',
                phone: '13100010005',
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  ContactGroup(
    id: 'fire-rescue',
    name: '\u6D88\u9632\u6551\u63F4\u652F\u961F',
    children: [
      ContactGroup(
        id: 'fire-rescue-command',
        name: '\u6307\u6325\u4E2D\u5FC3',
        contacts: [
          ContactPerson(
            id: 'sun-hao',
            name: '\u5B59\u6D69',
            title: '\u79D1\u957F',
            phone: '13100020001',
          ),
          ContactPerson(
            id: 'chen-yu',
            name: '\u9648\u5B87',
            title: '\u503C\u73ED\u5458',
            phone: '13100020002',
          ),
        ],
      ),
      ContactGroup(
        id: 'fire-rescue-station-1',
        name: '\u4E00\u53F7\u6D88\u9632\u7AD9',
        contacts: [
          ContactPerson(
            id: 'zhao-lei',
            name: '\u8D75\u78CA',
            title: '\u7AD9\u957F',
            phone: '13100020003',
          ),
        ],
      ),
    ],
  ),
  ContactGroup(
    id: 'medical-support',
    name: '\u533B\u7597\u4FDD\u969C\u7EC4',
    contacts: [
      ContactPerson(
        id: 'he-jing',
        name: '\u4F55\u9759',
        title: '\u533B\u7597\u7EC4\u957F',
        phone: '13100030001',
      ),
      ContactPerson(
        id: 'xu-lin',
        name: '\u5F90\u7433',
        title: '\u533B\u62A4\u4EBA\u5458',
        phone: '13100030002',
      ),
    ],
  ),
];

List<ContactPerson> allContactPersons([List<ContactGroup>? groups]) {
  final result = <ContactPerson>[];
  final source = groups ?? _fallbackContactTree;
  void collect(List<ContactGroup> groups) {
    for (final group in groups) {
      result.addAll(group.contacts);
      if (group.children.isNotEmpty) {
        collect(group.children);
      }
    }
  }

  collect(source);
  return List<ContactPerson>.unmodifiable(result);
}

List<ContactGroup> contactTreeData() {
  return List<ContactGroup>.unmodifiable(_fallbackContactTree);
}

Future<List<ContactGroup>> fetchContactTreeFromApi(ApiClient apiClient) async {
  final deptResponse = await apiClient.getJson(AppConstants.deptSimpleListPath);
  final userResponse = await apiClient.getJson(AppConstants.userSimpleListPath);

  final deptCode = _asInt(deptResponse['code']) ?? 0;
  final userCode = _asInt(userResponse['code']) ?? 0;
  if (deptCode != 0) {
    throw AppException(
      _asText(deptResponse['msg']) ??
          '\u90E8\u95E8\u5217\u8868\u52A0\u8F7D\u5931\u8D25',
    );
  }
  if (userCode != 0) {
    throw AppException(
      _asText(userResponse['msg']) ??
          '\u7528\u6237\u5217\u8868\u52A0\u8F7D\u5931\u8D25',
    );
  }

  final deptMaps = _asMapList(deptResponse['data']);
  final userMaps = _asMapList(userResponse['data']);
  if (deptMaps.isEmpty && userMaps.isEmpty) {
    return contactTreeData();
  }

  final deptById = <String, _MutableGroup>{};
  final rootGroups = <_MutableGroup>[];
  for (final item in deptMaps) {
    final id = _idText(item['id']);
    if (id == null) {
      continue;
    }
    final name = _repairMojibakeText(
      _asText(item['name']) ?? '\u672A\u547D\u540D\u90E8\u95E8',
    );
    final parentId = _idText(item['parentId']);
    deptById[id] = _MutableGroup(
      id: 'dept_$id',
      sourceDeptId: id,
      name: name,
      parentDeptId: parentId,
      children: <_MutableGroup>[],
      contacts: <ContactPerson>[],
    );
  }

  for (final group in deptById.values) {
    final parentDeptId = group.parentDeptId;
    if (parentDeptId == null || !deptById.containsKey(parentDeptId)) {
      rootGroups.add(group);
    } else {
      deptById[parentDeptId]!.children.add(group);
    }
  }

  final unassignedContacts = <ContactPerson>[];
  for (var index = 0; index < userMaps.length; index++) {
    final item = userMaps[index];
    final userId = _idText(item['id']) ?? 'index_$index';
    final nickname = _repairMojibakeText(
      _asText(item['nickname']) ??
          _asText(item['username']) ??
          _asText(item['name']) ??
          '\u7528\u6237$userId',
    );
    final deptId = _idText(item['deptId']);
    // Try to resolve department name from the dept tree first,
    // since the API often returns deptName as "null" string.
    String resolvedDeptName = '';
    if (deptId != null && deptById.containsKey(deptId)) {
      resolvedDeptName = deptById[deptId]!.name;
    } else {
      resolvedDeptName = _repairMojibakeText(
        _asText(item['deptName']) ??
            _asText(_asMap(item['dept'])?['name']) ??
            _asText(item['orgName']) ??
            '',
      );
    }
    // Use postNames as the title (position/job title).
    final postName = _extractPostNames(item);
    final title = postName.isNotEmpty ? postName : '\u6210\u5458';
    final phone = _extractPhoneFromUserMap(item) ?? '--';
    final person = ContactPerson(
      id: 'user_$userId',
      userId: userId,
      name: nickname,
      title: title,
      phone: phone,
      department: resolvedDeptName,
    );

    if (deptId != null && deptById.containsKey(deptId)) {
      deptById[deptId]!.contacts.add(person);
    } else {
      unassignedContacts.add(person);
    }
  }

  if (rootGroups.isEmpty && unassignedContacts.isNotEmpty) {
    return <ContactGroup>[
      ContactGroup(
        id: 'dept_root',
        name: '\u901A\u8BAF\u5F55',
        contacts: List<ContactPerson>.unmodifiable(unassignedContacts),
      ),
    ];
  }

  rootGroups.sort((a, b) => a.name.compareTo(b.name));
  final result = rootGroups.map(_toContactGroup).toList(growable: true);
  if (unassignedContacts.isNotEmpty) {
    unassignedContacts.sort((a, b) => a.name.compareTo(b.name));
    result.add(
      ContactGroup(
        id: 'dept_unassigned',
        name: '\u672A\u5206\u914D\u4EBA\u5458',
        contacts: List<ContactPerson>.unmodifiable(unassignedContacts),
      ),
    );
  }

  return List<ContactGroup>.unmodifiable(result);
}

Future<String?> fetchUserPhoneById(ApiClient apiClient, String userId) async {
  final response = await apiClient.getJson(
    AppConstants.userGetPath,
    queryParameters: <String, dynamic>{'id': userId},
  );
  final code = _asInt(response['code']) ?? -1;
  if (code != 0) {
    throw AppException(
      _asText(response['msg']) ??
          '\u7528\u6237\u8BE6\u60C5\u52A0\u8F7D\u5931\u8D25',
    );
  }
  final candidates = <Object?>[
    response['data'],
    _asMap(response['data'])?['data'],
    _asMap(response['data'])?['user'],
    response['result'],
  ];

  for (final candidate in candidates) {
    final map = _asMap(candidate);
    if (map == null) {
      continue;
    }
    final phone = _extractPhoneFromUserMap(map);
    if (phone != null) {
      return phone;
    }
  }
  return null;
}

ContactGroup _toContactGroup(_MutableGroup source) {
  final children = source.children.map(_toContactGroup).toList(growable: true);
  children.sort((a, b) => a.name.compareTo(b.name));
  final contacts = source.contacts.toList(growable: true)
    ..sort((a, b) => a.name.compareTo(b.name));
  return ContactGroup(
    id: source.id,
    name: source.name,
    children: List<ContactGroup>.unmodifiable(children),
    contacts: List<ContactPerson>.unmodifiable(contacts),
  );
}

class _MutableGroup {
  _MutableGroup({
    required this.id,
    required this.sourceDeptId,
    required this.name,
    required this.parentDeptId,
    required this.children,
    required this.contacts,
  });

  final String id;
  final String sourceDeptId;
  final String name;
  final String? parentDeptId;
  final List<_MutableGroup> children;
  final List<ContactPerson> contacts;
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => item.map((key, data) => MapEntry(key.toString(), data)))
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, data) => MapEntry(key.toString(), data));
  }
  return null;
}

String? _idText(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  if (text.isEmpty || text == '0' || text == 'null') {
    return null;
  }
  return text;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

String? _asText(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}

String _repairMojibakeText(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return text;
  }

  final suspicious = RegExp(r'[\u00C0-\u00FF]');
  if (!suspicious.hasMatch(text)) {
    return text;
  }

  try {
    final repaired = utf8.decode(latin1.encode(text), allowMalformed: false);
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(repaired) &&
        !suspicious.hasMatch(repaired)) {
      return repaired;
    }
  } catch (_) {}

  return text;
}

/// Extract postNames from simple-list API response.
/// postNames can be a String ("\u5C40\u957F") or a List<String> (["\u5C40\u957F", "\u4E66\u8BB0"]).
String _extractPostNames(Map<String, dynamic> item) {
  final postNamesRaw = item['postNames'];
  if (postNamesRaw == null) {
    return '';
  }
  if (postNamesRaw is List) {
    final parts = postNamesRaw.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.join('\u3001');
  }
  final text = postNamesRaw.toString().trim();
  return text == 'null' || text.isEmpty ? '' : text;
}

String? _extractPhoneFromUserMap(Map<String, dynamic> item) {
  const keys = <String>[
    'mobile',
    'mobileNumber',
    'mobileNo',
    'phone',
    'phonenumber',
    'phoneNumber',
    'telephone',
    'tel',
    'officePhone',
    'workPhone',
    'fixedPhone',
    'contactMobile',
    'contactPhone',
    'userPhone',
    'phoneNo',
    'cellphone',
    'cellPhone',
  ];
  final directMap = item.map((key, value) => MapEntry(key.toString(), value));
  for (final key in keys) {
    final normalized = _extractPhoneFromAny(directMap[key]);
    if (normalized != null) {
      return normalized;
    }
  }

  for (final nestedKey in const <String>[
    'user',
    'profile',
    'ext',
    'extraInfo',
    'contact',
    'userInfo',
  ]) {
    final normalized = _extractPhoneFromAny(directMap[nestedKey]);
    if (normalized != null) {
      return normalized;
    }
  }

  return _extractPhoneFromAny(directMap);
}

String? _extractPhoneFromAny(Object? raw, {int depth = 0}) {
  if (raw == null || depth > 4) {
    return null;
  }

  if (raw is String) {
    final direct = _normalizePhoneText(raw);
    if (direct != null) {
      return direct;
    }
    final trimmed = raw.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        final decoded = jsonDecode(trimmed);
        return _extractPhoneFromAny(decoded, depth: depth + 1);
      } catch (_) {}
    }
    final mobileMatch = RegExp(r'(?:\+?86)?1\d{10}').firstMatch(trimmed);
    if (mobileMatch != null) {
      return _normalizePhoneText(mobileMatch.group(0)!);
    }
    final landlineMatch = RegExp(r'0\d{2,3}[- ]?\d{7,8}').firstMatch(trimmed);
    if (landlineMatch != null) {
      return _normalizePhoneText(landlineMatch.group(0)!);
    }
    return null;
  }

  if (raw is num) {
    return _normalizePhoneText(raw.toString());
  }

  if (raw is Map) {
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    for (final key in const <String>[
      'mobile',
      'mobileNumber',
      'mobileNo',
      'phone',
      'phonenumber',
      'phoneNumber',
      'telephone',
      'tel',
      'officePhone',
      'workPhone',
      'fixedPhone',
      'contactMobile',
      'contactPhone',
      'userPhone',
      'phoneNo',
      'cellphone',
      'cellPhone',
    ]) {
      final normalized = _extractPhoneFromAny(map[key], depth: depth + 1);
      if (normalized != null) {
        return normalized;
      }
    }
    for (final value in map.values) {
      final normalized = _extractPhoneFromAny(value, depth: depth + 1);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }

  if (raw is Iterable) {
    for (final value in raw) {
      final normalized = _extractPhoneFromAny(value, depth: depth + 1);
      if (normalized != null) {
        return normalized;
      }
    }
  }

  return null;
}

String? _normalizePhoneText(String rawPhone) {
  final compact = rawPhone.trim();
  if (compact.isEmpty || compact == '--' || compact.toLowerCase() == 'null') {
    return null;
  }

  final candidates = compact.split(RegExp(r'[;,/|]+'));
  for (final candidate in candidates) {
    final display = candidate.trim().replaceAll('\u00A0', '');
    if (display.isEmpty) {
      continue;
    }

    var normalized = display.replaceAll(RegExp(r'[\s\-()]'), '');
    if (normalized.startsWith('+86')) {
      normalized = normalized.substring(3);
    } else if (normalized.startsWith('86') &&
        normalized.length > 11 &&
        RegExp(r'^86\d+$').hasMatch(normalized)) {
      normalized = normalized.substring(2);
    }

    if (_looksLikePhoneForDisplay(normalized)) {
      return display;
    }
  }
  return null;
}

bool _looksLikePhoneForDisplay(String normalized) {
  if (RegExp(r'^1\d{10}$').hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^1\d{2}\*{4}\d{4}$').hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^0\d{9,11}$').hasMatch(normalized)) {
    return true;
  }
  if (RegExp(r'^400\d{7}$').hasMatch(normalized)) {
    return true;
  }
  // 7-8 位本地号码（无区号的固话）
  if (RegExp(r'^\d{7,8}$').hasMatch(normalized)) {
    return true;
  }

  final digitCount = RegExp(r'\d').allMatches(normalized).length;
  if (digitCount >= 7 && normalized.contains('*')) {
    return true;
  }
  return false;
}
