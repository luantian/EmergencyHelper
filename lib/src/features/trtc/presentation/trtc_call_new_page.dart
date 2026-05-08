import 'dart:convert';

import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/event/presentation/event_transfer_picker_page.dart';
import 'package:emergency_helper/src/features/trtc/data/tuicall_session_service.dart';
import 'package:emergency_helper/src/features/trtc/presentation/trtc_call_route_extra.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_calls_uikit/tencent_calls_uikit.dart' as tui;

class TrtcCallNewPage extends StatefulWidget {
  const TrtcCallNewPage({super.key, this.routeExtra});

  final TrtcCallRouteExtra? routeExtra;

  @override
  State<TrtcCallNewPage> createState() => _TrtcCallNewPageState();
}

class _TrtcCallNewPageState extends State<TrtcCallNewPage> {
  final TUICallSessionService _sessionService = TUICallSessionService.instance;

  List<_Invitee> _invitees = const <_Invitee>[];
  final Map<String, String> _knownNames = <String, String>{};

  bool _loading = true;
  bool _submitting = false;
  bool _autoJoinHandled = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _invitees = _buildInviteesFromRoute(widget.routeExtra);
    _registerNameFromInvitees();
    _registerNamesFromRouteExtra();
    _sessionService.addCallNotificationListener(_onCallNotification);

    Future<void>.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _sessionService.removeCallNotificationListener(_onCallNotification);
    super.dispose();
  }

  void _onCallNotification(String message) {
    debugPrint('[TRTC-Page] call notification: $message');
    _showMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('音视频通话'),
      ),
      backgroundColor: const Color(0xFFF3F6FA),
      body: AppLoadingOverlay(
        loading: _loading,
        message: '正在准备音视频能力...',
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                children: <Widget>[
                  _buildParticipantCard(),
                  const SizedBox(height: 10),
                  if (_errorText != null && _errorText!.trim().isNotEmpty)
                    _buildErrorCard(_errorText!),
                  if (_invitees.isEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    const Text(
                      '请先从通讯录选择至少一位成员',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF7A8798),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantCard() {
    final displayList = _invitees
        .map((e) => _ParticipantDisplay.fromInvitee(e, _knownNames))
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE4EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '通话成员',
                  style: TextStyle(
                    color: Color(0xFF1F2B3A),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${displayList.length}人',
                style: const TextStyle(
                  color: Color(0xFF7A8798),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton.icon(
                onPressed: _submitting ? null : _pickInvitees,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('选择'),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (displayList.isEmpty)
            const Text(
              '暂无成员，点击右上角“选择”',
              style: TextStyle(
                color: Color(0xFF7A8798),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            ...displayList.map(_buildDisplayTile),
        ],
      ),
    );
  }

  Widget _buildDisplayTile(_ParticipantDisplay display) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E5F6)),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
            child: Text(
              _safeFirstChar(display.displayName),
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  display.displayName,
                  style: const TextStyle(
                    color: Color(0xFF243342),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (display.title.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 1),
                  Text(
                    display.title,
                    style: const TextStyle(
                      color: Color(0xFF7A8798),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String errorText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF2C67A)),
      ),
      child: Text(
        errorText,
        style: const TextStyle(
          color: Color(0xFF8A5A14),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFDCE4EF))),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: (_submitting || _invitees.isEmpty)
                      ? null
                      : _startVideoCall,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.videocam_rounded),
                  label: Text(_submitting ? '处理中...' : '视频通话'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: (_submitting || _invitees.isEmpty)
                      ? null
                      : _startAudioCall,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    side: const BorderSide(color: AppTheme.primaryBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.call_rounded),
                  label: Text(_submitting ? '处理中...' : '语音通话'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startVideoCall() {
    _startCall(tui.CallMediaType.video);
  }

  void _startAudioCall() {
    _startCall(tui.CallMediaType.audio);
  }

  String _mediaTypeLabel(tui.CallMediaType mediaType) {
    return mediaType == tui.CallMediaType.video ? '视频' : '语音';
  }

  Future<void> _bootstrap() async {
    await _ensureCallSession();
    await _tryAutoJoinFromRoute();
  }

  Future<void> _ensureCallSession({bool forceRefreshSig = false}) async {
    final dependencies = context.read<AppDependencies>();
    final result = await _sessionService.ensureLoggedIn(
      dependencies: dependencies,
      roomIdHint: TUICallSessionService.generateRoomId(),
      forceRefreshSig: forceRefreshSig,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _errorText = result.success ? null : result.message;
    });
    if (!result.success && result.message.trim().isNotEmpty) {
      _showMessage(_friendlyError(result.message));
    }
  }

  Future<void> _tryAutoJoinFromRoute() async {
    if (_autoJoinHandled) {
      return;
    }
    _autoJoinHandled = true;

    final extra = widget.routeExtra;
    if (extra == null || !extra.autoJoinOnOpen) {
      return;
    }

    final callId = (extra.callId ?? '').trim();
    if (callId.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '通话邀请缺少 callId，无法一键入会';
      });
      return;
    }

    // Track incoming call for multi-device sync detection.
    _sessionService.markIncomingCall(callId);

    if (!mounted) {
      return;
    }
    final dependencies = context.read<AppDependencies>();
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final sessionReady = await _sessionService.ensureLoggedIn(
        dependencies: dependencies,
        roomIdHint: TUICallSessionService.generateRoomId(),
      );
      if (!sessionReady.success) {
        if (!mounted) {
          return;
        }
        final message =
            sessionReady.message.isEmpty
                ? '通话会话初始化失败'
                : _friendlyError(sessionReady.message);
        setState(() {
          _errorText = message;
        });
        _showMessage(message);
        return;
      }
      _sessionService.markLocalUserAnswered();
      await tui.TUICallKit.instance.join(callId);
    } catch (error) {
      Object resolvedError = error;
      if (_shouldRetryWithSigRefresh(error: error)) {
        if (!mounted) {
          return;
        }
        final refreshed = await _sessionService.ensureLoggedIn(
          dependencies: dependencies,
          roomIdHint: TUICallSessionService.generateRoomId(),
          forceRefreshSig: true,
        );
        if (refreshed.success) {
          try {
            _sessionService.markLocalUserAnswered();
            await tui.TUICallKit.instance.join(callId);
            return;
          } catch (retryError) {
            resolvedError = retryError;
          }
        }
      }

      if (!mounted) {
        return;
      }
      final message = _friendlyError('加入通话失败: $resolvedError');
      setState(() {
        _errorText = message;
      });
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _pickInvitees() async {
    final selectedIds = _invitees
        .map((item) => int.tryParse(item.userId))
        .whereType<int>()
        .toList(growable: false);

    final selection = await Navigator.of(context).push<EventTransferSelection>(
      MaterialPageRoute<EventTransferSelection>(
        builder: (_) => EventTransferPickerPage(
          eventId: 'trtc',
          checkPermission: false,
          titleText: '选择参会人员',
          confirmButtonText: '确认邀请',
          emptySelectionHint: '请至少选择一位成员',
          initialSelectedUserIds: selectedIds,
          showContentField: false,
        ),
      ),
    );

    if (!mounted || selection == null || selection.userIds.isEmpty) {
      return;
    }

    final picked = <_Invitee>[];
    for (var i = 0; i < selection.userIds.length; i++) {
      final userId = selection.userIds[i].toString();
      final name = i < selection.userNames.length
          ? selection.userNames[i].trim()
          : '';
      final title = i < selection.userTitles.length
          ? selection.userTitles[i].trim()
          : '';
      final department = i < selection.userDepartments.length
          ? selection.userDepartments[i].trim()
          : '';
      picked.add(
        _Invitee(
          userId: userId,
          name: name,
          title: title,
          department: department,
        ),
      );
    }

    setState(() {
      _invitees = _dedupInvitees(picked);
      _registerNameFromInvitees();
    });
  }

  Future<void> _startCall(tui.CallMediaType mediaType) async {
    if (_submitting) {
      return;
    }
    if (_invitees.isEmpty) {
      _showMessage('请先选择通话成员');
      return;
    }

    final mediaTypeText = _mediaTypeLabel(mediaType);
    setState(() {
      _submitting = true;
    });

    try {
      final dependencies = context.read<AppDependencies>();
      final sessionReady = await _sessionService.ensureLoggedIn(
        dependencies: dependencies,
        roomIdHint: TUICallSessionService.generateRoomId(),
      );
      if (!sessionReady.success) {
        _showMessage(sessionReady.message.isEmpty ? '通话会话初始化失败' : _friendlyError(sessionReady.message));
        return;
      }

      final selfUserId = (sessionReady.userId ?? '').trim();
      final targetIds = _invitees
          .map((item) => item.userId.trim())
          .where((item) => item.isNotEmpty && item != selfUserId)
          .toSet()
          .toList(growable: false);
      final callerName = (sessionReady.nickname ?? '').trim();
      final inviteeById = <String, _Invitee>{};
      for (final invitee in _invitees) {
        final id = invitee.userId.trim();
        if (id.isEmpty) {
          continue;
        }
        inviteeById[id] = invitee;
      }
      final targetNames = targetIds
          .map((id) => _resolveInviteeName(inviteeById[id]))
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
      if (targetIds.isEmpty) {
        _showMessage('目标成员不能仅为自己，请重新选择');
        return;
      }

      debugPrint(
        '[TRTC] startCall tapped mediaType=$mediaTypeText '
        'targets=${targetIds.join(",")}',
      );

      await _preloadUserInfo(targetIds);

      final callUserData = <String, dynamic>{
        'source': 'emergency_helper',
        'page': 'trtc_call',
        'type': 'call_invite',
        'mediaType': mediaType == tui.CallMediaType.video ? 'video' : 'audio',
        'callerId': selfUserId,
        'autoJoin': 1,
        'autoEnter': 1,
        'joinDirectly': 1,
        'calleeUserIds': targetIds.join(','),
        'sentAt': DateTime.now().toIso8601String(),
      };
      if (callerName.isNotEmpty) {
        callUserData['callerName'] = callerName;
      }
      if (targetNames.isNotEmpty) {
        callUserData['calleeNames'] = targetNames.join(',');
      }
      final callParams = tui.CallParams(userData: jsonEncode(callUserData));
      debugPrint('[TRTC] call userData=${callParams.userData}');

      var result = await tui.TUICallKit.instance.calls(
        targetIds,
        mediaType,
        callParams,
      );

      debugPrint(
        '[TRTC] calls result mediaType=$mediaTypeText '
        'success=${result.isSuccess} code=${result.errorCode} '
        'message=${result.errorMessage}',
      );

      if (!result.isSuccess &&
          _shouldRetryWithSigRefresh(
            errorCode: result.errorCode,
            errorMessage: result.errorMessage,
          )) {
        debugPrint(
          '[TRTC] calls retry with refreshed userSig '
          'code=${result.errorCode}, message=${result.errorMessage}',
        );
        final refreshed = await _sessionService.ensureLoggedIn(
          dependencies: dependencies,
          roomIdHint: TUICallSessionService.generateRoomId(),
          forceRefreshSig: true,
        );
        if (refreshed.success) {
          result = await tui.TUICallKit.instance.calls(
            targetIds,
            mediaType,
            callParams,
          );
          debugPrint(
            '[TRTC] calls retry result mediaType=$mediaTypeText '
            'success=${result.isSuccess} code=${result.errorCode} '
            'message=${result.errorMessage}',
          );
        } else {
          _showMessage(refreshed.message.isEmpty ? '通话会话初始化失败' : _friendlyError(refreshed.message));
          return;
        }
      }

      if (!result.isSuccess && mounted) {
        _showMessage(_friendlyError('发起$mediaTypeText通话失败: ${result.errorMessage ?? ""}'));
      }
    } catch (error) {
      if (mounted) {
        _showMessage(_friendlyError('发起$mediaTypeText通话失败: $error'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _preloadUserInfo(List<String> userIds) async {
    final contactListStore = tui.ContactListStore.create();
    for (final userId in userIds) {
      try {
        await contactListStore.addFriend(userID: userId);
      } catch (_) {
        // Ignore: may already be friends or auto-accept is disabled.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  void _registerName(String userId, String name) {
    final trimmedUserId = userId.trim();
    final trimmedName = name.trim();
    if (trimmedUserId.isEmpty || trimmedName.isEmpty) {
      return;
    }
    _knownNames[trimmedUserId] = trimmedName;
  }

  void _registerNameFromInvitees() {
    for (final invitee in _invitees) {
      _registerName(invitee.userId, invitee.name);
    }
  }

  String _resolveInviteeName(_Invitee? invitee) {
    if (invitee == null) {
      return '';
    }
    final id = invitee.userId.trim();
    if (id.isNotEmpty) {
      final known = _knownNames[id];
      if (known != null && known.trim().isNotEmpty) {
        return known.trim();
      }
    }
    final directName = invitee.name.trim();
    if (directName.isNotEmpty) {
      return directName;
    }
    return invitee.displayName;
  }

  void _registerNamesFromRouteExtra() {
    final extra = widget.routeExtra;
    if (extra == null) {
      return;
    }
    final userIds = extra.initialTargetUserIds;
    for (var i = 0; i < userIds.length; i++) {
      final userId = userIds[i].trim();
      if (userId.isEmpty) {
        continue;
      }
      final name = i < extra.calleeNames.length
          ? extra.calleeNames[i].trim()
          : '';
      if (name.isNotEmpty) {
        _knownNames[userId] = name;
      }
    }
  }

  List<_Invitee> _buildInviteesFromRoute(TrtcCallRouteExtra? extra) {
    if (extra == null) {
      return const <_Invitee>[];
    }

    final userIds = extra.initialTargetUserIds;
    if (userIds.isEmpty) {
      return const <_Invitee>[];
    }

    final result = <_Invitee>[];
    for (var i = 0; i < userIds.length; i++) {
      final userId = userIds[i].trim();
      if (userId.isEmpty) {
        continue;
      }
      final name = i < extra.calleeNames.length
          ? extra.calleeNames[i].trim()
          : (i == 0 ? extra.calleeName.trim() : '');
      final title = i < extra.calleeTitles.length
          ? extra.calleeTitles[i].trim()
          : (i == 0 ? (extra.calleeTitle ?? '').trim() : '');
      final department = i < extra.calleeDepartments.length
          ? extra.calleeDepartments[i].trim()
          : (i == 0 ? (extra.calleeDepartment ?? '').trim() : '');

      result.add(
        _Invitee(
          userId: userId,
          name: name,
          title: title,
          department: department,
        ),
      );
    }

    return _dedupInvitees(result);
  }

  List<_Invitee> _dedupInvitees(List<_Invitee> source) {
    final seen = <String>{};
    final result = <_Invitee>[];
    for (final item in source) {
      if (item.userId.isEmpty || !seen.add(item.userId)) {
        continue;
      }
      result.add(item);
    }
    return result;
  }

  bool _shouldRetryWithSigRefresh({
    int? errorCode,
    String? errorMessage,
    Object? error,
  }) {
    if (errorCode == -100018) {
      return true;
    }

    final normalized = '${errorMessage ?? ""} ${error ?? ""}'.toLowerCase();
    return normalized.contains('invalidusersig') ||
        normalized.contains('usersig') ||
        normalized.contains('user sig') ||
        normalized.contains('not login') ||
        normalized.contains('not logined') ||
        normalized.contains('login first') ||
        normalized.contains('signature') ||
        normalized.contains('sig') ||
        normalized.contains('签名') ||
        normalized.contains('未登录');
  }

  String _friendlyError(Object raw) {
    final text = raw.toString().toLowerCase();
    if (text.contains('network') ||
        text.contains('timeout') ||
        text.contains('connect')) {
      return '网络异常，请检查网络后重试';
    }
    if (text.contains('sig') ||
        text.contains('signature') ||
        text.contains('签名') ||
        text.contains('auth') ||
        text.contains('permission')) {
      return '登录已过期，请退出后重新登录';
    }
    if (text.contains('call') || text.contains('invite')) {
      return '呼叫失败，对方可能不在线';
    }
    if (text.contains('join') || text.contains('enter')) {
      return '加入通话失败，请重试';
    }
    return '操作失败，请稍后重试';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    AppCenterToast.show(context, message);
  }
}

class _Invitee {
  const _Invitee({
    required this.userId,
    required this.name,
    this.title = '',
    this.department = '',
  });

  final String userId;
  final String name;
  final String title;
  final String department;

  String get displayName {
    final value = name.trim();
    return value.isNotEmpty ? value : '未命名成员';
  }
}

class _ParticipantDisplay {
  const _ParticipantDisplay({
    required this.id,
    required this.displayName,
    this.title = '',
  });

  factory _ParticipantDisplay.fromInvitee(
    _Invitee invitee,
    Map<String, String> knownNames,
  ) {
    final id = invitee.userId.trim();
    final known = knownNames[id];
    final name = (known != null && known.isNotEmpty)
        ? known
        : invitee.displayName;
    return _ParticipantDisplay(id: id, displayName: name, title: invitee.title);
  }

  final String id;
  final String displayName;
  final String title;
}

String _safeFirstChar(String text, {String fallback = '?'}) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return fallback;
  }
  return normalized.substring(0, 1);
}
