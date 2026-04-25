import 'package:emergency_helper/src/app.dart';
import 'package:emergency_helper/src/core/auth/app_feature_permission.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppDependencies> _pumpApp(WidgetTester tester) async {
  final dependencies = AppDependencies.create();
  await dependencies.authLocalStore.clear();
  AppFeaturePermissionResolver.instance.clearCache();

  addTearDown(() async {
    await dependencies.authLocalStore.clear();
    AppFeaturePermissionResolver.instance.clearCache();
    dependencies.dispose();
  });

  await tester.pumpWidget(EmergencyHelperApp(dependencies: dependencies));
  return dependencies;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 12),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final maxTicks = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (var i = 0; i <= maxTicks; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(step);
  }
  throw TestFailure('Timed out waiting for finder: $finder');
}

Future<void> _pumpUntilAny(
  WidgetTester tester,
  List<Finder> finders, {
  Duration timeout = const Duration(seconds: 12),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final maxTicks = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (var i = 0; i <= maxTicks; i++) {
    final found = finders.any((finder) => finder.evaluate().isNotEmpty);
    if (found) {
      return;
    }
    await tester.pump(step);
  }
  throw TestFailure('Timed out waiting for any finder: $finders');
}

Future<void> _ensureHome(WidgetTester tester) async {
  final loginButton = find.byKey(const Key('login-submit-button'));
  final homeNav = find.byKey(const Key('main-bottom-nav'));

  await _pumpUntilAny(tester, <Finder>[loginButton, homeNav]);

  if (homeNav.evaluate().isNotEmpty) {
    return;
  }

  expect(loginButton, findsOneWidget);
  await tester.tap(loginButton);
  await tester.pump();
  await _pumpUntil(tester, homeNav);
}

void main() {
  testWidgets('app boots to login or home', (WidgetTester tester) async {
    await _pumpApp(tester);

    final loginButton = find.byKey(const Key('login-submit-button'));
    final homeNav = find.byKey(const Key('main-bottom-nav'));
    await _pumpUntilAny(tester, <Finder>[loginButton, homeNav]);

    final onLogin = loginButton.evaluate().isNotEmpty;
    final onHome = homeNav.evaluate().isNotEmpty;
    expect(onLogin || onHome, isTrue);
  });

  testWidgets('can open weather info from workbench', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);
    await _ensureHome(tester);

    final weatherEntry = find.byKey(const Key('open-weather-info-button'));
    expect(weatherEntry, findsOneWidget);
    await tester.tap(weatherEntry);
    await tester.pump();

    await _pumpUntil(tester, find.text('天气信息'));
    expect(find.text('天气信息'), findsOneWidget);
  });

  testWidgets('can open change password from mine tab', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);
    await _ensureHome(tester);

    await tester.tap(find.text('我的'));
    await tester.pump();

    final changePasswordEntry = find.byKey(
      const Key('open-change-password-button'),
    );
    await _pumpUntil(tester, changePasswordEntry);
    await tester.tap(changePasswordEntry);
    await tester.pump();

    await _pumpUntil(tester, find.byKey(const Key('change-password-submit')));
    expect(find.byKey(const Key('change-password-submit')), findsOneWidget);
  });
}
