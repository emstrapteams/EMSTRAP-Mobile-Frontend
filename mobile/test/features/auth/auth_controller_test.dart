import 'package:emstrap_mobile/core/network/api_exception.dart';
import 'package:emstrap_mobile/core/storage/secure_store.dart';
import 'package:emstrap_mobile/features/auth/models/user_role.dart';
import 'package:emstrap_mobile/features/auth/providers/auth_controller.dart';
import 'package:emstrap_mobile/features/emergency/data/emergency_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late InMemorySecureStore store;

  setUp(() {
    backend = FakeBackend();
    store = InMemorySecureStore();
  });

  test(
    'with no saved token, startup is signed out without calling the server',
    () async {
      final container = makeContainer(backend: backend, store: store);
      container.read(authControllerProvider);
      await waitUntil(
        () => container.read(authControllerProvider) is! AuthRestoring,
      );
      expect(container.read(authControllerProvider), isA<AuthSignedOut>());
      expect(backend.requests, isEmpty);
    },
  );

  test('login stores the token and the role comes from the server', () async {
    backend.reply(
      'POST',
      '/auth/login',
      200,
      loginResponse(role: 'ambulance_driver'),
    );
    final container = makeContainer(backend: backend, store: store);
    container.read(authControllerProvider);
    await waitUntil(
      () => container.read(authControllerProvider) is! AuthRestoring,
    );

    await container
        .read(authControllerProvider.notifier)
        .login(email: ' User@Emstrap.local ', password: 'pw');

    final state = container.read(authControllerProvider) as AuthSignedIn;
    expect(state.user.role, UserRole.ambulanceDriver);
    expect(store.values['auth_token'], 'jwt-token');
    expect(
      backend.lastBody('POST', '/auth/login')['email'],
      'user@emstrap.local',
    );
    // Credentials are never sent with an old token attached.
    expect(
      backend.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
  });

  test(
    'a rejected login surfaces the backend message and stays signed out',
    () async {
      backend.reply('POST', '/auth/login', 401, {
        'success': false,
        'message': 'Please verify your email to login',
      });
      final container = makeContainer(backend: backend, store: store);
      container.read(authControllerProvider);
      await waitUntil(
        () => container.read(authControllerProvider) is! AuthRestoring,
      );

      await expectLater(
        container
            .read(authControllerProvider.notifier)
            .login(email: 'a@b.in', password: 'pw'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Please verify your email to login',
          ),
        ),
      );
      expect(container.read(authControllerProvider), isA<AuthSignedOut>());
      expect(store.values, isEmpty);
    },
  );

  test(
    'a saved session is restored through /auth/me with the bearer token',
    () async {
      store.values['auth_token'] = 'saved';
      backend.reply('GET', '/auth/me', 200, meResponse(role: 'hospital_admin'));
      final container = makeContainer(backend: backend, store: store);
      container.read(authControllerProvider);
      await waitUntil(
        () => container.read(authControllerProvider) is! AuthRestoring,
      );

      final state = container.read(authControllerProvider) as AuthSignedIn;
      expect(state.user.role, UserRole.hospital);
      expect(backend.requests.single.headers['Authorization'], 'Bearer saved');
    },
  );

  test(
    'an expired saved token is cleared and the user is signed out',
    () async {
      store.values['auth_token'] = 'expired';
      backend.reply('GET', '/auth/me', 401, {
        'message': 'Invalid or expired token',
      });
      final container = makeContainer(backend: backend, store: store);
      container.read(authControllerProvider);
      await waitUntil(
        () => container.read(authControllerProvider) is! AuthRestoring,
      );

      expect(container.read(authControllerProvider), isA<AuthSignedOut>());
      expect(store.values.containsKey('auth_token'), isFalse);
    },
  );

  test(
    'if the server is unreachable on startup the token is kept for a retry',
    () async {
      store.values['auth_token'] = 'saved';
      backend.timeout('GET', '/auth/me');
      final container = makeContainer(backend: backend, store: store);
      container.read(authControllerProvider);
      await waitUntil(
        () => container.read(authControllerProvider) is! AuthRestoring,
      );

      expect(container.read(authControllerProvider), isA<AuthRestoreFailed>());
      expect(store.values['auth_token'], 'saved');

      backend.reply('GET', '/auth/me', 200, meResponse());
      await container.read(authControllerProvider.notifier).restore();
      expect(container.read(authControllerProvider), isA<AuthSignedIn>());
    },
  );

  test(
    'a 401 on any authenticated call signs the user out with a notice',
    () async {
      store.values['auth_token'] = 'saved';
      backend.reply('GET', '/auth/me', 200, meResponse());
      backend.reply('GET', '/api/emergency', 401, {
        'message': 'Invalid or expired token',
      });
      final container = makeContainer(backend: backend, store: store);
      container.read(authControllerProvider);
      await waitUntil(
        () => container.read(authControllerProvider) is! AuthRestoring,
      );

      await expectLater(
        container.read(emergencyRepositoryProvider).listMine(),
        throwsA(isA<ApiException>()),
      );
      await settle();

      final state = container.read(authControllerProvider);
      expect(state, isA<AuthSignedOut>());
      expect((state as AuthSignedOut).notice, contains('expired'));
      expect(store.values.containsKey('auth_token'), isFalse);
    },
  );

  test(
    'logout clears the token and the remembered emergency even if the server call fails',
    () async {
      store.values['auth_token'] = 'saved';
      store.values['active_emergency_id'] = 'e1';
      backend.reply('GET', '/auth/me', 200, meResponse());
      backend.timeout('POST', '/auth/logout');
      final container = makeContainer(backend: backend, store: store);
      container.read(authControllerProvider);
      await waitUntil(
        () => container.read(authControllerProvider) is! AuthRestoring,
      );

      await container.read(authControllerProvider.notifier).logout();

      expect(container.read(authControllerProvider), isA<AuthSignedOut>());
      expect(store.values, isEmpty);
    },
  );
}
