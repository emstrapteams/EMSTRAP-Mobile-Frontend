import 'package:emstrap_mobile/app.dart';
import 'package:emstrap_mobile/core/network/api_exception.dart';
import 'package:emstrap_mobile/core/routing/auth_redirect.dart';
import 'package:emstrap_mobile/core/storage/secure_store.dart';
import 'package:emstrap_mobile/features/auth/models/app_user.dart';
import 'package:emstrap_mobile/features/auth/providers/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

AuthSignedIn signedIn(String id) =>
    AuthSignedIn(AppUser.fromJson({'_id': id, 'role': 'user'}));

/// Advances both fake time (widget zone: Dio, timers) and real time (I/O)
/// until [condition] holds.
Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(condition(), isTrue, reason: 'condition not met while pumping');
}

/// Pumps the whole app (real router, real redirects) on a fake backend.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  FakeBackend backend, {
  InMemorySecureStore? store,
}) async {
  final container = makeContainer(backend: backend, store: store);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const EmstrapApp()),
  );
  await pumpUntil(
    tester,
    () => container.read(authControllerProvider) is! AuthRestoring,
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('identityChanged', () {
    test('login, logout and switching accounts are identity changes', () {
      expect(identityChanged(const AuthSignedOut(), signedIn('a')), isTrue);
      expect(identityChanged(signedIn('a'), const AuthSignedOut()), isTrue);
      expect(identityChanged(signedIn('a'), signedIn('b')), isTrue);
    });

    test('restoring a session or retrying is not', () {
      expect(identityChanged(const AuthRestoring(), signedIn('a')), isFalse);
      expect(
        identityChanged(const AuthRestoring(), const AuthSignedOut()),
        isFalse,
      );
      expect(
        identityChanged(
          const AuthRestoreFailed(ApiException(ApiErrorKind.network, 'x')),
          const AuthRestoring(),
        ),
        isFalse,
      );
      expect(identityChanged(signedIn('a'), signedIn('a')), isFalse);
    });
  });

  // Regression: found on the emulator. Profile is pushed over Home; after
  // logout the redirect only saw "/" and the app showed a blank Profile.
  testWidgets('logging out from the pushed Profile screen lands on home', (
    tester,
  ) async {
    final store = InMemorySecureStore()..values['auth_token'] = 'jwt';
    final backend = FakeBackend()
      ..reply('GET', '/auth/me', 200, meResponse())
      ..reply('GET', '/api/emergency', 200, {'success': true, 'data': []})
      ..reply('POST', '/auth/logout', 200, {
        'message': 'Logged out successfully',
      });
    await pumpApp(tester, backend, store: store);
    expect(find.text('Hi Test, need an ambulance?'), findsOneWidget);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await pumpUntil(tester, () => store.values.isEmpty);
    await tester.pumpAndSettle();

    expect(find.text('Need an ambulance?'), findsOneWidget);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('a signed-in user with an in-progress request sees the banner', (
    tester,
  ) async {
    final store = InMemorySecureStore()..values['auth_token'] = 'jwt';
    final backend = FakeBackend()
      ..reply('GET', '/auth/me', 200, meResponse())
      ..reply('GET', '/api/emergency', 200, {
        'success': true,
        'data': [emergencyJson(id: 'live1', status: 'AMBULANCE_ACCEPTED')],
      });
    await pumpApp(tester, backend, store: store);
    // Not saved on this phone, but in progress on the server.
    expect(find.textContaining('in progress'), findsOneWidget);
  });

  // Regression: found with uiautomator. excludeSemantics hid the tap action,
  // so TalkBack users couldn't trigger the main emergency button.
  testWidgets('the emergency button is activatable by screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, FakeBackend());

    final node = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Request an ambulance')),
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    handle.dispose();
  });
}
