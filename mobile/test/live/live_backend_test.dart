/// End-to-end check of the app's data and state layers against a REAL local
/// EMSTRAP backend (no UI). Skipped unless LIVE_API_BASE_URL is set.
///
///   LIVE_API_BASE_URL=http://localhost:5050 \
///   LIVE_USER_EMAIL=... LIVE_USER_PASSWORD=... \
///   LIVE_DRIVER_EMAIL=... LIVE_DRIVER_PASSWORD=... \
///   flutter test test/live
///
/// Never point this at production: it creates and cancels real requests.
@Tags(['live'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:emstrap_mobile/core/config/app_config.dart';
import 'package:emstrap_mobile/core/network/api_client.dart';
import 'package:emstrap_mobile/core/network/api_exception.dart';
import 'package:emstrap_mobile/core/storage/secure_store.dart';
import 'package:emstrap_mobile/features/auth/models/user_role.dart';
import 'package:emstrap_mobile/features/auth/providers/auth_controller.dart';
import 'package:emstrap_mobile/features/emergency/data/emergency_repository.dart';
import 'package:emstrap_mobile/features/emergency/data/location_service.dart';
import 'package:emstrap_mobile/features/emergency/models/emergency_status.dart';
import 'package:emstrap_mobile/features/emergency/providers/emergency_flow_controller.dart';
import 'package:emstrap_mobile/features/emergency/providers/emergency_tracking_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../support/fakes.dart';

final env = Platform.environment;
final baseUrl = env['LIVE_API_BASE_URL'];

ProviderContainer liveContainer(
  InMemorySecureStore store,
  FakeLocationService location,
) => ProviderContainer(
  overrides: [
    appConfigProvider.overrideWithValue(AppConfig(apiBaseUrl: baseUrl!)),
    secureStoreProvider.overrideWithValue(store),
    locationServiceProvider.overrideWithValue(location),
  ],
);

/// A second client acting as the government ambulance driver.
Future<Dio> driverClient() async {
  final dio = Dio(BaseOptions(baseUrl: baseUrl!, validateStatus: (_) => true));
  final res = await dio.post<Map<String, dynamic>>(
    '/auth/login',
    data: {
      'email': env['LIVE_DRIVER_EMAIL'],
      'password': env['LIVE_DRIVER_PASSWORD'],
    },
  );
  dio.options.headers['Authorization'] = 'Bearer ${res.data!['token']}';
  return dio;
}

/// Emits `update_location` the way the web driver dashboard does.
class FakeDriverSocket {
  FakeDriverSocket(String url)
    : _socket = io.io(
        url,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build(),
      )..connect();

  final io.Socket _socket;

  Future<void> sendLocation(String requestId, double lat, double lng) async {
    await waitUntil(() => _socket.connected);
    _socket.emit('update_location', {
      'requestId': requestId,
      'lat': lat,
      'lng': lng,
    });
  }

  void dispose() => _socket.dispose();
}

void main() {
  if (baseUrl == null) {
    test('live backend tests', () {}, skip: 'LIVE_API_BASE_URL not set');
    return;
  }

  test(
    'anonymous user: request → driver accepts → arrives → user cancels, tracked live',
    () async {
      final store = InMemorySecureStore();
      final container = liveContainer(store, FakeLocationService());
      addTearDown(container.dispose);

      // Startup with no token → signed out, no server call needed.
      container.listen(authControllerProvider, (_, _) {});
      await waitUntil(
        () => container.read(authControllerProvider) is AuthSignedOut,
      );

      // 1. Create through the real flow controller.
      container.listen(emergencyFlowControllerProvider, (_, _) {});
      await waitUntil(
        () =>
            container.read(emergencyFlowControllerProvider).step ==
            FlowStep.ready,
      );
      await container.read(emergencyFlowControllerProvider.notifier).send();
      final flow = container.read(emergencyFlowControllerProvider);
      expect(flow.step, FlowStep.submitted, reason: '${flow.error}');
      final id = flow.created!.id;
      expect(flow.created!.status, EmergencyStatus.pending);
      expect(
        flow.created!.aiAnalysis,
        isNull,
        reason: 'AI is disabled locally; defaults must not show',
      );
      expect(store.values['active_emergency_id'], id);

      // 2. Track it over the real Socket.IO connection.
      final provider = emergencyTrackingControllerProvider(id);
      container.listen(provider, (_, _) {});
      await waitUntil(
        () =>
            container.read(provider).request != null &&
            container.read(provider).liveConnected,
      );

      // 3. The driver accepts → the socket event makes the app refetch.
      final driver = await driverClient();
      final accept = await driver.put<Map<String, dynamic>>(
        '/api/emergency/$id/accept',
      );
      expect(accept.statusCode, 200, reason: '${accept.data}');
      await waitUntil(
        () =>
            container.read(provider).request?.status ==
            EmergencyStatus.ambulanceAccepted,
      );
      expect(
        container.read(provider).request?.ambulance?.driverName,
        isNotNull,
      );

      // 4. Live ambulance position pushed by the driver's socket.
      final driverSocket = FakeDriverSocket(baseUrl!);
      addTearDown(driverSocket.dispose);
      await driverSocket.sendLocation(id, 28.62, 77.21);
      await waitUntil(() => container.read(provider).ambulanceLive != null);

      // 5. Driver marks arrival.
      final arrived = await driver.put<Map<String, dynamic>>(
        '/api/emergency/$id/mark-arrived',
      );
      expect(arrived.statusCode, 200);
      await waitUntil(
        () =>
            container.read(provider).request?.status ==
            EmergencyStatus.arrivedAtLocation,
      );

      // 6. The user cancels; the server state is shown and the id forgotten.
      final error = await container.read(provider.notifier).cancel();
      expect(error, isNull);
      expect(
        container.read(provider).request?.status,
        EmergencyStatus.cancelled,
      );
      expect(store.values.containsKey('active_emergency_id'), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'signed-in user: login, create, history, session restore, logout',
    () async {
      final store = InMemorySecureStore();
      final container = liveContainer(store, FakeLocationService());
      addTearDown(container.dispose);
      container.listen(authControllerProvider, (_, _) {});
      await waitUntil(
        () => container.read(authControllerProvider) is AuthSignedOut,
      );

      await container
          .read(authControllerProvider.notifier)
          .login(
            email: env['LIVE_USER_EMAIL']!,
            password: env['LIVE_USER_PASSWORD']!,
          );
      final auth = container.read(authControllerProvider) as AuthSignedIn;
      expect(auth.user.role, UserRole.user);
      expect(store.values['auth_token'], isNotEmpty);

      container.listen(emergencyFlowControllerProvider, (_, _) {});
      await waitUntil(
        () =>
            container.read(emergencyFlowControllerProvider).step ==
            FlowStep.ready,
      );
      await container.read(emergencyFlowControllerProvider.notifier).send();
      final id = container.read(emergencyFlowControllerProvider).created!.id;

      final history = await container
          .read(emergencyRepositoryProvider)
          .listMine();
      expect(history.first.id, id, reason: 'newest first, linked to this user');

      // Session restore in a fresh container using the stored token.
      final restored = liveContainer(store, FakeLocationService());
      addTearDown(restored.dispose);
      restored.listen(authControllerProvider, (_, _) {});
      await waitUntil(
        () => restored.read(authControllerProvider) is! AuthRestoring,
      );
      expect(restored.read(authControllerProvider), isA<AuthSignedIn>());

      await container.read(emergencyRepositoryProvider).cancel(id);
      await container.read(authControllerProvider.notifier).logout();
      expect(store.values.containsKey('auth_token'), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'wrong password and unverified-style errors come back as readable messages',
    () async {
      final container = liveContainer(
        InMemorySecureStore(),
        FakeLocationService(),
      );
      addTearDown(container.dispose);
      container.listen(authControllerProvider, (_, _) {});
      await waitUntil(
        () => container.read(authControllerProvider) is AuthSignedOut,
      );

      await expectLater(
        container
            .read(authControllerProvider.notifier)
            .login(email: env['LIVE_USER_EMAIL']!, password: 'Wrong1!pw'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Invalid credentials',
          ),
        ),
      );
    },
  );

  test(
    'photo precheck without Cloudinary fails cleanly (no request created)',
    () async {
      final container = liveContainer(
        InMemorySecureStore(),
        FakeLocationService(),
      );
      addTearDown(container.dispose);
      final repo = container.read(emergencyRepositoryProvider);
      const tinyJpeg =
          'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==';
      final location = FakeLocationService().result as LocationFix;
      await expectLater(
        repo.precheck(imageDataUrl: tinyJpeg, location: location.point),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.server,
          ),
        ),
      );
    },
  );
}
