import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:atomic_x_core/atomicxcore.dart' show CallMediaType;
import 'package:emergency_helper/src/features/about/presentation/about_page.dart';
import 'package:emergency_helper/src/features/account/presentation/change_password_page.dart';
import 'package:emergency_helper/src/features/auth/presentation/login_page.dart';
import 'package:emergency_helper/src/features/event/presentation/event_detail_page.dart';
import 'package:emergency_helper/src/features/event/presentation/event_feedback_page.dart';
import 'package:emergency_helper/src/features/event/presentation/event_list_page.dart';
import 'package:emergency_helper/src/features/event/presentation/event_report_page.dart';
import 'package:emergency_helper/src/features/event/presentation/event_timeline_page.dart';
import 'package:emergency_helper/src/features/event/presentation/event_transfer_picker_page.dart';
import 'package:emergency_helper/src/features/home/data/notify_message_service.dart';
import 'package:emergency_helper/src/features/home/presentation/home_page.dart';
import 'package:emergency_helper/src/features/home/presentation/message_detail_page.dart';
import 'package:emergency_helper/src/features/key_point/presentation/key_point_page.dart';
import 'package:emergency_helper/src/features/push/presentation/business_debug_page.dart';
import 'package:emergency_helper/src/features/push/presentation/push_debug_page.dart';
import 'package:emergency_helper/src/features/risk/presentation/risk_detail_page.dart';
import 'package:emergency_helper/src/features/risk/presentation/risk_feedback_page.dart';
import 'package:emergency_helper/src/features/risk/presentation/risk_list_page.dart';
import 'package:emergency_helper/src/features/risk/presentation/risk_report_page.dart';
import 'package:emergency_helper/src/features/risk/presentation/risk_transfer_picker_page.dart';
import 'package:emergency_helper/src/features/splash/presentation/splash_page.dart';
import 'package:emergency_helper/src/features/statistics/presentation/statistics_page.dart';
import 'package:emergency_helper/src/features/trtc/presentation/in_call_page.dart';
import 'package:emergency_helper/src/features/trtc/presentation/incoming_call_page.dart';
import 'package:emergency_helper/src/features/trtc/presentation/trtc_call_new_page.dart';
import 'package:emergency_helper/src/features/trtc/presentation/trtc_call_route_extra.dart';
import 'package:emergency_helper/src/features/weather/presentation/weather_info_page.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

class AppRouter {
  const AppRouter._();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static GoRouter buildRouter() {
    return GoRouter(
      navigatorKey: navigatorKey,
      observers: <NavigatorObserver>[],
      routes: <GoRoute>[
        GoRoute(
          path: RoutePaths.splash,
          builder: (context, state) => const SplashPage(),
        ),
        GoRoute(
          path: RoutePaths.login,
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: RoutePaths.home,
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: RoutePaths.eventReport,
          builder: (context, state) => const EventReportPage(),
        ),
        GoRoute(
          path: RoutePaths.eventList,
          builder: (context, state) => const EventListPage(),
        ),
        GoRoute(
          path: RoutePaths.eventDetail,
          builder: (context, state) {
            final eventId = state.pathParameters['eventId'] ?? '';
            return EventDetailPage(eventId: Uri.decodeComponent(eventId));
          },
        ),
        GoRoute(
          path: RoutePaths.eventFeedback,
          builder: (context, state) {
            final eventId = state.pathParameters['eventId'] ?? '';
            return EventFeedbackPage(eventId: Uri.decodeComponent(eventId));
          },
        ),
        GoRoute(
          path: RoutePaths.eventTransferPicker,
          builder: (context, state) {
            final eventId = state.pathParameters['eventId'] ?? '';
            return EventTransferPickerPage(
              eventId: Uri.decodeComponent(eventId),
            );
          },
        ),
        GoRoute(
          path: RoutePaths.eventTimeline,
          builder: (context, state) {
            final eventId = state.pathParameters['eventId'] ?? '';
            return EventTimelinePage(eventId: Uri.decodeComponent(eventId));
          },
        ),
        GoRoute(
          path: RoutePaths.riskReport,
          builder: (context, state) => const RiskReportPage(),
        ),
        GoRoute(
          path: RoutePaths.riskList,
          builder: (context, state) => const RiskListPage(),
        ),
        GoRoute(
          path: RoutePaths.riskDetail,
          builder: (context, state) {
            final riskId = state.pathParameters['riskId'] ?? '';
            return RiskDetailPage(riskId: Uri.decodeComponent(riskId));
          },
        ),
        GoRoute(
          path: RoutePaths.riskFeedback,
          builder: (context, state) {
            final riskId = state.pathParameters['riskId'] ?? '';
            return RiskFeedbackPage(riskId: Uri.decodeComponent(riskId));
          },
        ),
        GoRoute(
          path: RoutePaths.riskTransferPicker,
          builder: (context, state) {
            final riskId = state.pathParameters['riskId'] ?? '';
            return RiskTransferPickerPage(riskId: Uri.decodeComponent(riskId));
          },
        ),
        GoRoute(
          path: RoutePaths.keyPoint,
          builder: (context, state) => const KeyPointPage(),
        ),
        GoRoute(
          path: RoutePaths.weatherInfo,
          builder: (context, state) => const WeatherInfoPage(),
        ),
        GoRoute(
          path: RoutePaths.statistics,
          builder: (context, state) {
            final rawTab = (state.uri.queryParameters['tab'] ?? '')
                .trim()
                .toLowerCase();
            final initialTab =
                rawTab == 'risk' ||
                    rawTab == 'derived-risk' ||
                    rawTab == 'derived_risk' ||
                    rawTab == 'secondary-risk' ||
                    rawTab == 'secondary_risk'
                ? StatisticsTabKind.derivedRisk
                : StatisticsTabKind.event;
            return StatisticsPage(initialTab: initialTab);
          },
        ),
        GoRoute(
          path: RoutePaths.changePassword,
          builder: (context, state) => const ChangePasswordPage(),
        ),
        GoRoute(
          path: RoutePaths.about,
          builder: (context, state) => const AboutPage(),
        ),
        GoRoute(
          path: RoutePaths.messageDetail,
          builder: (context, state) {
            final rawId = state.pathParameters['messageId'] ?? '';
            final messageId = int.tryParse(Uri.decodeComponent(rawId)) ?? 0;
            final extra = state.extra;
            NotifyMessageItem? initialItem;
            Future<void> Function()? onReadChanged;
            if (extra is MessageDetailRouteExtra) {
              initialItem = extra.initialItem;
              onReadChanged = extra.onReadChanged;
            } else if (extra is NotifyMessageItem) {
              initialItem = extra;
            }
            return MessageDetailPage(
              messageId: messageId,
              initialItem: initialItem,
              onReadChanged: onReadChanged,
            );
          },
        ),
        GoRoute(
          path: RoutePaths.pushDebug,
          builder: (context, state) => const PushDebugPage(),
        ),
        GoRoute(
          path: RoutePaths.businessDebug,
          builder: (context, state) => const BusinessDebugPage(),
        ),
        GoRoute(
          path: RoutePaths.trtcCallNew,
          builder: (context, state) {
            return TrtcCallNewPage(routeExtra: _resolveTrtcRouteExtra(state));
          },
        ),
        GoRoute(
          path: RoutePaths.trtcCall,
          builder: (context, state) {
            // Legacy route is temporarily mapped to new TUICallKit page.
            return TrtcCallNewPage(routeExtra: _resolveTrtcRouteExtra(state));
          },
        ),
        GoRoute(
          path: RoutePaths.trtcIncomingCall,
          builder: (context, state) {
            final params = state.uri.queryParameters;
            return IncomingCallPage(
              callId: params['callId'] ?? '',
              callerId: params['callerId'] ?? '',
              callerName: params['callerName'] ?? '未知来电',
              mediaType: params['mediaType'] == 'video'
                  ? CallMediaType.video
                  : CallMediaType.audio,
            );
          },
        ),
        GoRoute(
          path: RoutePaths.trtcInCall,
          builder: (context, state) {
            final params = state.uri.queryParameters;
            return InCallPage(
              callId: params['callId'] ?? '',
              mediaType: params['mediaType'] == 'video'
                  ? CallMediaType.video
                  : CallMediaType.audio,
            );
          },
        ),
      ],
    );
  }
}

TrtcCallRouteExtra? _resolveTrtcRouteExtra(GoRouterState state) {
  final extra = state.extra;
  if (extra is TrtcCallRouteExtra) {
    return extra;
  }
  final query = state.uri.queryParameters;

  String? pickText(List<String> keys) {
    for (final key in keys) {
      final value = query[key];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  List<String> parseList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <String>[];
    }
    final seen = <String>{};
    return raw
        .split(RegExp('[,\\uFF0C\\s]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where(seen.add)
        .toList(growable: false);
  }

  bool parseBool(String? raw, {bool fallback = false}) {
    if (raw == null || raw.trim().isEmpty) {
      return fallback;
    }
    final normalized = raw.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'y' ||
        normalized == 'on';
  }

  final roomId = int.tryParse(
    (pickText(<String>['roomId', 'room_id', 'rtcRoomId', 'trtcRoomId']) ?? ''),
  );
  final callId = pickText(<String>['callId', 'call_id', 'rtcCallId']);
  final calleeUserIds = parseList(
    pickText(<String>[
      'calleeUserIds',
      'targetUserIds',
      'participantIds',
      'inviteeIds',
      'userIds',
    ]),
  );
  final calleeNames = parseList(
    pickText(<String>['calleeNames', 'targetUserNames', 'participantNames']),
  );
  final callerId = pickText(<String>[
    'callerId',
    'fromUserId',
    'sponsorUserId',
  ]);
  final callerName = pickText(<String>[
    'callerName',
    'fromUserName',
    'sponsorUserName',
  ]);
  final resolvedCalleeUserIds = calleeUserIds.isNotEmpty
      ? calleeUserIds
      : <String>[if (callerId != null && callerId.isNotEmpty) callerId];
  final resolvedCalleeNames = calleeNames.isNotEmpty
      ? calleeNames
      : <String>[if (callerName != null && callerName.isNotEmpty) callerName];
  final fallbackUserId = resolvedCalleeUserIds.isNotEmpty
      ? resolvedCalleeUserIds.first
      : '';
  final fallbackName = resolvedCalleeNames.isNotEmpty
      ? resolvedCalleeNames.first
      : '\u672A\u547D\u540D\u6210\u5458';
  final shouldBuildExtra =
      query.isNotEmpty &&
      (roomId != null ||
          callId != null ||
          resolvedCalleeUserIds.isNotEmpty ||
          callerId != null);
  if (!shouldBuildExtra) {
    return null;
  }
  return TrtcCallRouteExtra(
    calleeUserId: fallbackUserId,
    calleeName: fallbackName,
    calleeUserIds: resolvedCalleeUserIds,
    calleeNames: resolvedCalleeNames,
    initialRoomId: roomId != null && roomId > 0 ? roomId : null,
    callId: callId,
    autoJoinOnOpen: parseBool(
      pickText(<String>['autoJoin', 'autoEnter', 'joinDirectly']),
      fallback: callId != null && callId.isNotEmpty,
    ),
  );
}
