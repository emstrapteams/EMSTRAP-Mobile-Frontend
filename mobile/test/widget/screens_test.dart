import 'package:emstrap_mobile/core/routing/auth_redirect.dart';
import 'package:emstrap_mobile/core/theme/app_theme.dart';
import 'package:emstrap_mobile/features/auth/presentation/login_screen.dart';
import 'package:emstrap_mobile/features/auth/providers/auth_controller.dart';
import 'package:emstrap_mobile/features/emergency/presentation/emergency_flow_screen.dart';
import 'package:emstrap_mobile/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';

/// Pumps [initial] inside a small router so navigation calls work.
Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  FakeBackend backend,
  String initial,
) async {
  final container = makeContainer(backend: backend);
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, _) => const Text('register'),
      ),
      GoRoute(
        path: AppRoutes.newEmergency,
        builder: (_, _) => const EmergencyFlowScreen(),
      ),
      GoRoute(
        path: '/emergency/:id',
        builder: (_, s) => Text('tracking ${s.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  // Let the auth controller finish restoring (no saved token → signed out).
  await tester.runAsync(
    () => waitUntil(
      () => container.read(authControllerProvider) is AuthSignedOut,
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('login form validates before calling the server', (tester) async {
    final backend = FakeBackend();
    await pumpScreen(tester, backend, AppRoutes.login);

    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pump();

    expect(find.text('Enter your email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(backend.requests, isEmpty);
  });

  testWidgets('login shows the backend message inline', (tester) async {
    final backend = FakeBackend()
      ..reply('POST', '/auth/login', 401, {
        'success': false,
        'message': 'Please verify your email to login',
      });
    await pumpScreen(tester, backend, AppRoutes.login);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'a@b.in',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'pw',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.runAsync(() => settle());
    await tester.pumpAndSettle();

    expect(find.text('Please verify your email to login'), findsOneWidget);
  });

  testWidgets('signed-out home offers help without requiring a login', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester, FakeBackend(), AppRoutes.home);

    expect(find.bySemanticsLabel('Request an ambulance'), findsOneWidget);
    expect(find.textContaining('108'), findsWidgets);
    expect(find.text('Log in'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('Request an ambulance'));
    await tester.pumpAndSettle();
    expect(
      find.text('Request an ambulance'),
      findsOneWidget,
    ); // flow screen title
    semantics.dispose();
  });

  testWidgets(
    'emergency flow: shows location, sends once, then opens tracking',
    (tester) async {
      final backend = FakeBackend()
        ..on('POST', '/api/emergency', (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return FakeResponse(201, {
            'success': true,
            'data': emergencyJson(id: 'abc123'),
          });
        });
      await pumpScreen(tester, backend, AppRoutes.newEmergency);

      expect(find.text('Your location'), findsOneWidget);
      expect(find.text('28.61390, 77.20900'), findsOneWidget);

      final send = find.widgetWithText(FilledButton, 'Send emergency request');
      await tester.tap(send);
      await tester.pump();
      // Disabled with a progress label while the request is in flight.
      expect(find.text('Sending request…'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Sending request…'),
        warnIfMissed: false,
      );

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      expect(backend.count('POST', '/api/emergency'), 1);
      expect(find.text('tracking abc123'), findsOneWidget);
    },
  );
}
