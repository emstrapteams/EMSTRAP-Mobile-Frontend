import 'package:emstrap_mobile/core/storage/secure_store.dart';
import 'package:emstrap_mobile/features/emergency/models/emergency_status.dart';
import 'package:emstrap_mobile/features/emergency/models/emergency_request.dart';
import 'package:emstrap_mobile/features/emergency/providers/emergency_tracking_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late InMemorySecureStore store;
  late FakeRealtime realtime;
  late FakeLocationService location;
  var currentStatus = 'PENDING';

  setUp(() {
    backend = FakeBackend();
    store = InMemorySecureStore()..values['active_emergency_id'] = 'e1';
    realtime = FakeRealtime();
    location = FakeLocationService();
    currentStatus = 'PENDING';
    backend.on(
      'GET',
      '/api/emergency/e1',
      (_) => FakeResponse(200, {
        'success': true,
        'data': emergencyJson(
          status: currentStatus,
          ambulance: currentStatus == 'PENDING'
              ? null
              : {'_id': 'a1', 'name': 'Test Driver'},
        ),
      }),
    );
  });

  Future<ProviderContainer> track() async {
    final c = makeContainer(
      backend: backend,
      store: store,
      realtime: realtime,
      location: location,
    );
    c.listen(emergencyTrackingControllerProvider('e1'), (_, _) {});
    await waitUntil(() {
      final s = c.read(emergencyTrackingControllerProvider('e1'));
      return s.request != null || s.loadError != null;
    });
    await settle();
    return c;
  }

  TrackingState stateOf(ProviderContainer c) =>
      c.read(emergencyTrackingControllerProvider('e1'));

  test('loads the request and joins its socket room', () async {
    final c = await track();
    expect(stateOf(c).request?.status, EmergencyStatus.pending);
    expect(realtime.tracked, {'e1'});
  });

  test(
    'socket events only trigger a refetch; REST decides the status',
    () async {
      final c = await track();
      final before = backend.count('GET', '/api/emergency/e1');

      currentStatus = 'AMBULANCE_ACCEPTED';
      realtime.push('ambulance_assigned', {
        'driverName': 'Test Driver',
        'eta': 'Calculating...',
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(backend.count('GET', '/api/emergency/e1'), before + 1);
      expect(stateOf(c).request?.status, EmergencyStatus.ambulanceAccepted);
      expect(stateOf(c).request?.ambulance?.driverName, 'Test Driver');
    },
  );

  test('live ambulance positions are applied without a refetch', () async {
    final c = await track();
    final before = backend.count('GET', '/api/emergency/e1');

    realtime.push('ambulance_location', {
      'requestId': 'e1',
      'lat': 28.62,
      'lng': 77.21,
    });
    await settle();

    expect(stateOf(c).ambulanceLive, isA<GeoPoint>());
    expect(backend.count('GET', '/api/emergency/e1'), before);
  });

  test('events for another request are ignored', () async {
    final c = await track();
    final before = backend.count('GET', '/api/emergency/e1');
    realtime.push('ambulance_location', {
      'requestId': 'other',
      'lat': 1,
      'lng': 1,
    });
    realtime.push('emergency_cancelled', {'requestId': 'other'});
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(stateOf(c).ambulanceLive, isNull);
    expect(backend.count('GET', '/api/emergency/e1'), before);
  });

  test(
    'shares the patient location only while the ambulance is on the way',
    () async {
      final c = await track();
      expect(stateOf(c).sharingLocation, isFalse);

      currentStatus = 'AMBULANCE_ACCEPTED';
      await c
          .read(emergencyTrackingControllerProvider('e1').notifier)
          .refresh();
      await settle();
      expect(stateOf(c).sharingLocation, isTrue);

      location.positions.add(const GeoPoint(28.6, 77.2));
      await settle();
      expect(realtime.emitted.single.$1, 'update_user_location');
      expect(realtime.emitted.single.$2, {
        'requestId': 'e1',
        'latitude': 28.6,
        'longitude': 77.2,
      });

      currentStatus = 'ARRIVED_AT_LOCATION';
      await c
          .read(emergencyTrackingControllerProvider('e1').notifier)
          .refresh();
      expect(stateOf(c).sharingLocation, isFalse);
    },
  );

  test(
    'never starts sharing without an existing location permission',
    () async {
      location.permission = false;
      currentStatus = 'AMBULANCE_ACCEPTED';
      final c = await track();
      expect(stateOf(c).sharingLocation, isFalse);
    },
  );

  test('a finished request is forgotten locally', () async {
    currentStatus = 'COMPLETED';
    await track();
    expect(store.values.containsKey('active_emergency_id'), isFalse);
  });

  test('cancel asks the server, then shows the server state', () async {
    backend.on('PUT', '/api/emergency/e1/user-cancel', (_) {
      currentStatus = 'CANCELLED';
      return const FakeResponse(200, {'success': true});
    });
    final c = await track();

    final error = await c
        .read(emergencyTrackingControllerProvider('e1').notifier)
        .cancel();

    expect(error, isNull);
    expect(stateOf(c).request?.status, EmergencyStatus.cancelled);
    expect(store.values.containsKey('active_emergency_id'), isFalse);
  });

  test('a rejected cancel reports the backend message', () async {
    backend.reply('PUT', '/api/emergency/e1/user-cancel', 400, {
      'success': false,
      'message': 'Emergency already closed.',
    });
    final c = await track();
    final error = await c
        .read(emergencyTrackingControllerProvider('e1').notifier)
        .cancel();
    expect(error, 'Emergency already closed.');
  });

  test(
    'when the socket drops, a reconnect triggers a catch-up refetch',
    () async {
      final c = await track();
      realtime.setConnected(false);
      await settle();
      expect(stateOf(c).liveConnected, isFalse);

      final before = backend.count('GET', '/api/emergency/e1');
      realtime.setConnected(true);
      await settle();
      expect(stateOf(c).liveConnected, isTrue);
      expect(backend.count('GET', '/api/emergency/e1'), before + 1);
    },
  );
}
