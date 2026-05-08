import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/features/home/presentation/tabs/contacts_tab_page.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class EventTransferSelection {
  const EventTransferSelection({
    required this.userIds,
    required this.userNames,
    this.userTitles = const <String>[],
    this.userDepartments = const <String>[],
    this.userPhones = const <String>[],
    this.content = '',
  });

  final List<int> userIds;
  final List<String> userNames;
  final List<String> userTitles;
  final List<String> userDepartments;
  final List<String> userPhones;
  final String content;
}

class EventTransferPickerPage extends StatefulWidget {
  const EventTransferPickerPage({
    required this.eventId,
    this.checkPermission = true,
    this.titleText = '\u9009\u62E9\u901A\u8BAF\u5F55',
    this.confirmButtonText = '\u786E\u8BA4\u6307\u6D3E',
    this.emptySelectionHint =
        '\u8BF7\u81F3\u5C11\u9009\u62E9\u4E00\u4F4D\u8054\u7CFB\u4EBA',
    this.permissionDeniedHint =
        '\u5F53\u524D\u8D26\u53F7\u65E0\u4E8B\u4EF6\u8F6C\u6D3E\u6743\u9650',
    this.initialSelectedUserIds = const <int>[],
    this.showContentField = true,
    super.key,
  });

  final String eventId;
  final bool checkPermission;
  final String titleText;
  final String confirmButtonText;
  final String emptySelectionHint;
  final String permissionDeniedHint;
  final List<int> initialSelectedUserIds;
  final bool showContentField;

  @override
  State<EventTransferPickerPage> createState() =>
      _EventTransferPickerPageState();
}

class _EventTransferPickerPageState extends State<EventTransferPickerPage> {
  late final TextEditingController _searchController;
  late final TextEditingController _contentController;
  late final Set<int> _initialSelectedUserIds;
  List<ContactGroup> _contactTree = contactTreeData();
  List<ContactPerson> _allContacts = allContactPersons();
  final Set<String> _expandedGroupIds = <String>{};
  final Set<String> _selectedIds = <String>{};
  bool _loading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _contentController = TextEditingController();
    _initialSelectedUserIds = widget.initialSelectedUserIds
        .where((id) => id > 0)
        .toSet();
    Future<void>.microtask(_initializePage);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _initializePage() async {
    if (widget.checkPermission) {
      final dependencies = context.read<AppDependencies>();
      EventCenter.instance.bindApiClient(dependencies.apiClient);
      final canTransfer = await EventCenter.instance.canTransfer(
        widget.eventId,
      );
      if (!canTransfer) {
        if (mounted) {
          AppCenterToast.show(context, widget.permissionDeniedHint);
          Navigator.of(context).pop();
        }
        return;
      }
    }
    await _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _normalize(_searchController.text.trim());
    final autoExpandedIds = _collectSearchExpandedIds(keyword);
    final visibleRows = _buildVisibleRows(
      groups: _contactTree,
      depth: 0,
      keyword: keyword,
      autoExpandedIds: autoExpandedIds,
    );

    return Scaffold(
      key: const Key('event-transfer-picker-root'),
      appBar: AppBar(
        title: Text(widget.titleText),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: <Widget>[_buildTreeMenuButton()],
      ),
      backgroundColor: const Color(0xFFF2F3F5),
      body: AppLoadingOverlay(
        loading: _loading,
        message: '\u6B63\u5728\u52A0\u8F7D\u901A\u8BAF\u5F55...',
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: <Widget>[
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
                    children: <Widget>[
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
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) {
                  setState(() {});
                },
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索姓名/岗位',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: keyword.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFD8DFE9)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFD8DFE9)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: <Widget>[
                  Text(
                    '已选 ${_selectedIds.length} 人',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF4E5968),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () {
                            setState(() {
                              _selectedIds.clear();
                            });
                          },
                    child: const Text('清空选择'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: visibleRows.isEmpty
                  ? const Center(
                      child: Text(
                        '未找到匹配联系人',
                        style: TextStyle(
                          color: Color(0xFF7A8492),
                          fontSize: 15,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: visibleRows.length,
                      itemBuilder: (context, index) {
                        final row = visibleRows[index];
                        if (row is _GroupRow) {
                          final hasQuery = keyword.isNotEmpty;
                          final hasChildren =
                              row.group.children.isNotEmpty ||
                              row.group.contacts.isNotEmpty;
                          return _GroupTile(
                            group: row.group,
                            depth: row.depth,
                            isExpanded: row.isExpanded,
                            isMatched: row.isMatched,
                            hasChildren: hasChildren,
                            contactCount: _countContactsInGroup(row.group),
                            disableToggle: hasQuery,
                            onTap: () => _toggleGroup(row.group.id),
                          );
                        }

                        final contactRow = row as _ContactRow;
                        final person = contactRow.person;
                        final selected = _selectedIds.contains(person.id);
                        return _ContactTile(
                          person: person,
                          depth: contactRow.depth,
                          isMatched: contactRow.isMatched,
                          selected: selected,
                          onTap: () => _toggleContact(person.id),
                        );
                      },
                    ),
            ),
            if (widget.showContentField)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                color: const Color(0xFFF2F3F5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '转派说明',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E3440),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _contentController,
                      maxLines: 3,
                      maxLength: 200,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: '请输入转派说明',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8DFE9),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8DFE9),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF2088E8),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2088E8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          widget.confirmButtonText,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!widget.showContentField)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2088E8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      widget.confirmButtonText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    );
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
        _allContacts = allContactPersons(_contactTree);
        // Reconcile existing selections: keep only IDs that exist in the new data.
        final validIds = _allContacts.map((p) => p.id).toSet();
        _selectedIds.retainWhere((id) => validIds.contains(id));
        if (_selectedIds.isEmpty && _initialSelectedUserIds.isNotEmpty) {
          _selectedIds.addAll(_buildInitialSelectedContactIds(_allContacts));
        }
        _expandedGroupIds.clear();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = '接口加载失败，已使用本地通讯录数据';
        if (_selectedIds.isEmpty && _initialSelectedUserIds.isNotEmpty) {
          _selectedIds.addAll(_buildInitialSelectedContactIds(_allContacts));
        }
      });
    }
  }

  List<_VisibleRow> _buildVisibleRows({
    required List<ContactGroup> groups,
    required int depth,
    required String keyword,
    required Set<String> autoExpandedIds,
  }) {
    final rows = <_VisibleRow>[];

    for (final group in groups) {
      if (keyword.isNotEmpty && !_groupHasMatches(group, keyword)) {
        continue;
      }
      final groupMatched = keyword.isNotEmpty && _contains(group.name, keyword);

      final isExpanded = keyword.isNotEmpty
          ? autoExpandedIds.contains(group.id)
          : _expandedGroupIds.contains(group.id);
      rows.add(
        _GroupRow(
          group: group,
          depth: depth,
          isExpanded: isExpanded,
          isMatched: groupMatched,
        ),
      );

      if (!isExpanded) {
        continue;
      }

      final visibleContacts = keyword.isEmpty
          ? group.contacts
          : group.contacts.where((p) => _contactMatches(p, keyword)).toList();
      for (final person in visibleContacts) {
        rows.add(
          _ContactRow(
            person: person,
            depth: depth + 1,
            isMatched: keyword.isNotEmpty && _contactMatches(person, keyword),
          ),
        );
      }

      rows.addAll(
        _buildVisibleRows(
          groups: group.children,
          depth: depth + 1,
          keyword: keyword,
          autoExpandedIds: autoExpandedIds,
        ),
      );
    }

    return rows;
  }

  bool _groupHasMatches(ContactGroup group, String keyword) {
    if (_contains(group.name, keyword)) {
      return true;
    }
    if (group.contacts.any((p) => _contactMatches(p, keyword))) {
      return true;
    }
    for (final child in group.children) {
      if (_groupHasMatches(child, keyword)) {
        return true;
      }
    }
    return false;
  }

  bool _contactMatches(ContactPerson person, String keyword) {
    return _contains(person.name, keyword) || _contains(person.title, keyword);
  }

  Set<String> _collectSearchExpandedIds(String keyword) {
    if (keyword.isEmpty) {
      return _expandedGroupIds;
    }
    final ids = <String>{};

    bool visit(ContactGroup group) {
      final selfMatch = _contains(group.name, keyword);
      final contactMatch = group.contacts.any(
        (p) => _contactMatches(p, keyword),
      );
      var childMatch = false;
      for (final child in group.children) {
        if (visit(child)) {
          childMatch = true;
        }
      }
      final hasMatch = selfMatch || contactMatch || childMatch;
      if (hasMatch) {
        ids.add(group.id);
      }
      return hasMatch;
    }

    for (final group in _contactTree) {
      visit(group);
    }
    return ids;
  }

  Set<String> _collectAllGroupIds(List<ContactGroup> groups) {
    final ids = <String>{};
    void collect(List<ContactGroup> items) {
      for (final item in items) {
        ids.add(item.id);
        if (item.children.isNotEmpty) {
          collect(item.children);
        }
      }
    }

    collect(groups);
    return ids;
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

  void _toggleGroup(String groupId) {
    setState(() {
      if (_expandedGroupIds.contains(groupId)) {
        _expandedGroupIds.remove(groupId);
      } else {
        _expandedGroupIds.add(groupId);
      }
    });
  }

  void _toggleContact(String contactId) {
    setState(() {
      if (_selectedIds.contains(contactId)) {
        _selectedIds.remove(contactId);
      } else {
        _selectedIds.add(contactId);
      }
    });
  }

  void _expandAll() {
    setState(() {
      _expandedGroupIds
        ..clear()
        ..addAll(_collectAllGroupIds(_contactTree));
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedGroupIds.clear();
    });
  }

  String _normalize(String value) => value.toLowerCase().trim();

  bool _contains(String text, String keyword) {
    if (keyword.isEmpty) {
      return true;
    }
    return text.toLowerCase().contains(keyword);
  }

  Widget _buildTreeMenuButton() {
    return PopupMenuButton<_TransferTreeMenuAction>(
      tooltip: '更多操作',
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
          case _TransferTreeMenuAction.expandAll:
            _expandAll();
          case _TransferTreeMenuAction.collapseAll:
            _collapseAll();
        }
      },
      itemBuilder: (context) => const <PopupMenuEntry<_TransferTreeMenuAction>>[
        PopupMenuItem<_TransferTreeMenuAction>(
          value: _TransferTreeMenuAction.expandAll,
          height: 40,
          child: Row(
            children: <Widget>[
              Icon(
                Icons.unfold_more_rounded,
                size: 18,
                color: Color(0xFF42566D),
              ),
              SizedBox(width: 10),
              Text('全部展开'),
            ],
          ),
        ),
        PopupMenuItem<_TransferTreeMenuAction>(
          value: _TransferTreeMenuAction.collapseAll,
          height: 40,
          child: Row(
            children: <Widget>[
              Icon(
                Icons.unfold_less_rounded,
                size: 18,
                color: Color(0xFF42566D),
              ),
              SizedBox(width: 10),
              Text('全部收起'),
            ],
          ),
        ),
      ],
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(right: 8),
        alignment: Alignment.center,
        child: const Icon(Icons.more_horiz_rounded, color: Colors.white),
      ),
    );
  }

  void _onConfirm() {
    if (_selectedIds.isEmpty) {
      AppCenterToast.show(context, widget.emptySelectionHint);
      return;
    }

    final content = widget.showContentField
        ? _contentController.text.trim()
        : '';
    if (widget.showContentField && content.isEmpty) {
      AppCenterToast.show(context, '请输入转派说明');
      return;
    }

    final selectedPeople = _allContacts
        .where((person) => _selectedIds.contains(person.id))
        .toList();
    final userIds = selectedPeople
        .map((person) => _parseUserId(person.id))
        .whereType<int>()
        .toList();
    final userNames = selectedPeople.map((person) => person.name).toList();
    final userTitles = selectedPeople.map((person) => person.title).toList();
    final userDepartments = selectedPeople
        .map((person) => _findDepartmentNameByContactId(person.id) ?? '--')
        .toList();
    final userPhones = selectedPeople.map((person) => person.phone).toList();

    if (userIds.isEmpty) {
      AppCenterToast.show(
        context,
        '\u9009\u62E9\u7684\u8054\u7CFB\u4EBA\u7F3A\u5C11\u5408\u6CD5ID',
      );
      return;
    }

    Navigator.of(context).pop<EventTransferSelection>(
      EventTransferSelection(
        userIds: userIds,
        userNames: userNames,
        userTitles: userTitles,
        userDepartments: userDepartments,
        userPhones: userPhones,
        content: content,
      ),
    );
  }

  String? _findDepartmentNameByContactId(String contactId) {
    ContactPerson? person;
    for (final item in _allContacts) {
      if (item.id == contactId) {
        person = item;
        break;
      }
    }
    final personDepartment = _normalizeDepartmentName(person?.department);
    if (personDepartment != null) {
      return personDepartment;
    }

    String? visit(List<ContactGroup> groups) {
      for (final group in groups) {
        if (group.contacts.any((person) => person.id == contactId)) {
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

  int? _parseUserId(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.startsWith('user_')) {
      return int.tryParse(value.substring(5));
    }
    return int.tryParse(value);
  }

  Set<String> _buildInitialSelectedContactIds(List<ContactPerson> contacts) {
    final selected = <String>{};
    for (final person in contacts) {
      final userId = _parseUserId(person.id);
      if (userId != null && _initialSelectedUserIds.contains(userId)) {
        selected.add(person.id);
      }
    }
    return selected;
  }
}

enum _TransferTreeMenuAction { expandAll, collapseAll }

String _safeFirstChar(String text, {String fallback = '?'}) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return fallback;
  }
  return normalized.substring(0, 1);
}

sealed class _VisibleRow {
  const _VisibleRow(this.depth);

  final int depth;
}

class _GroupRow extends _VisibleRow {
  const _GroupRow({
    required this.group,
    required this.isExpanded,
    required this.isMatched,
    required int depth,
  }) : super(depth);

  final ContactGroup group;
  final bool isExpanded;
  final bool isMatched;
}

class _ContactRow extends _VisibleRow {
  const _ContactRow({
    required this.person,
    required this.isMatched,
    required int depth,
  }) : super(depth);

  final ContactPerson person;
  final bool isMatched;
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.depth,
    required this.isExpanded,
    required this.isMatched,
    required this.hasChildren,
    required this.contactCount,
    required this.disableToggle,
    required this.onTap,
  });

  final ContactGroup group;
  final int depth;
  final bool isExpanded;
  final bool isMatched;
  final bool hasChildren;
  final int contactCount;
  final bool disableToggle;
  final VoidCallback onTap;

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
        onTap: hasChildren && !disableToggle ? onTap : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(leftPadding, 10, 12, 10),
          child: Row(
            children: <Widget>[
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
                  children: <Widget>[
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E3440),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.children.length}个下级组织 · $contactCount人',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF768294),
                      ),
                    ),
                  ],
                ),
              ),
              if (disableToggle)
                const Text(
                  '搜索中',
                  style: TextStyle(color: Color(0xFF8190A0), fontSize: 12),
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
    required this.person,
    required this.depth,
    required this.isMatched,
    required this.selected,
    required this.onTap,
  });

  final ContactPerson person;
  final int depth;
  final bool isMatched;
  final bool selected;
  final VoidCallback onTap;

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
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(leftPadding, 8, 8, 8),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFE8F0FC),
                child: Text(
                  _safeFirstChar(person.name),
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
                  children: <Widget>[
                    Text(
                      person.name,
                      style: const TextStyle(
                        color: Color(0xFF2D3442),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      person.title,
                      style: const TextStyle(
                        color: Color(0xFF778396),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: AppTheme.primaryBlue,
                side: const BorderSide(color: Color(0xFFB8C5D6), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
