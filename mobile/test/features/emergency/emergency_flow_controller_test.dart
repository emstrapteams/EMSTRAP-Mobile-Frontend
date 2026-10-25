import 'dart:typed_data';

import 'package:emstrap_mobile/core/network/api_exception.dart';
import 'package:emstrap_mobile/core/storage/secure_store.dart';
import 'package:emstrap_mobile/features/auth/providers/auth_controller.dart';
import 'package:emstrap_mobile/features/emergency/data/location_service.dart';
import 'package:emstrap_mobile/features/emergency/data/photo_service.dart';
import 'package:emstrap_mobile/features/emergency/providers/emergency_flow_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/fakes.dart';

class FakePhotoService extends PhotoService {
  @override
  Future<CapturedPhoto?> pick(ImageSource source) async =>
      CapturedPhoto(Uint8List.fromList([1, 2, 3]), 'image/jpeg');
}

const precheckPath = '/api/emergency/precheck';
const createPath = '/api/emergency';

void main() {
  late FakeBackend backend;
  late InMemorySecureStore store;

  setUp(() {
    backend = FakeBackend();
    store = InMemorySecureStore();
  });

  /// Builds the flow and waits for the location step to finish.
  Future<(ProviderContainer, EmergencyFlowController)> startFlow({
    FakeLocationService? location,
    bool signedIn = false,
  }) async {
    if (signedIn) {
      store.values['auth_token'] = 'jwt';
      backend.reply('GET', '/auth/me', 200, meResponse());
    }
    final container = makeContainer(
      backend: backend,
      store: store,
      location: location,
      overrides: [photoServiceProvider.overrideWithValue(FakePhotoService())],
    );
    container.listen(authControllerProvider, (_, _) {});
    container.listen(emergencyFlowControllerProvider, (_, _) {});
    await waitUntil(
      () =>
          container.read(emergencyFlowControllerProvider).step !=
              FlowStep.locating &&
          container.read(authControllerProvider) is! AuthRestoring,
    );
    return (
      container,
      container.read(emergencyFlowControllerProvider.notifier),
    );
  }

  EmergencyFlowState stateOf(ProviderContainer c) =>
      c.read(emergencyFlowControllerProvider);

  test('gets the location first and then waits for the user', () async {
    final (c, _) = await startFlow();
    expect(stateOf(c).step, FlowStep.ready);
    expect(stateOf(c).fix?.point.latitude, 28.6139);
    expect(backend.requests.where((r) => r.path.startsWith('/api')), isEmpty);
  });

  test('a denied location permission stops the flow with a reason', () async {
    final (c, _) = await startFlow(
      location: FakeLocationService(
        result: const LocationFailure(LocationProblem.permissionDeniedForever),
      ),
    );
    expect(stateOf(c).step, FlowStep.needsLocation);
    expect(stateOf(c).locationProblem, LocationProblem.permissionDeniedForever);
  });

  test('sends coordinates and remembers the created request', () async {
    backend.reply('POST', createPath, 201, {
      'success': true,
      'data': emergencyJson(id: 'new1'),
    });
    final (c, flow) = await startFlow();

    await flow.send();

    expect(stateOf(c).step, FlowStep.submitted);
    expect(stateOf(c).created?.id, 'new1');
    expect(backend.lastBody('POST', createPath), {
      'latitude': 28.6139,
      'longitude': 77.209,
    });
    expect(store.values['active_emergency_id'], 'new1');
  });

  test('rapid repeated taps create exactly one request', () async {
    backend.on('POST', createPath, (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return FakeResponse(201, {'success': true, 'data': emergencyJson()});
    });
    final (c, flow) = await startFlow();

    await Future.wait([flow.send(), flow.send(), flow.send()]);

    expect(backend.count('POST', createPath), 1);
    expect(stateOf(c).step, FlowStep.submitted);
  });

  test('with AI disabled (503) the uploaded photo is still attached', () async {
    backend.reply('POST', precheckPath, 503, {
      'success': false,
      'message': 'AI service is currently disabled.',
      'secureImageUrl': 'https://res.cloudinary.com/x/precheck.jpg',
    });
    backend.reply('POST', createPath, 201, {
      'success': true,
      'data': emergencyJson(),
    });
    final (c, flow) = await startFlow();
    await flow.pickPhoto(ImageSource.camera);

    await flow.send();

    expect(stateOf(c).step, FlowStep.submitted);
    expect(stateOf(c).precheck?.aiAvailable, isFalse);
    expect(
      backend.lastBody('POST', createPath)['imageUrl'],
      'https://res.cloudinary.com/x/precheck.jpg',
    );
    expect(
      (backend.lastBody('POST', precheckPath)['imageUrl'] as String),
      startsWith('data:image/jpeg;base64,'),
    );
  });

  test('a low-confidence AI result asks the user before sending', () async {
    backend.reply('POST', precheckPath, 200, {
      'success': true,
      'secureImageUrl': 'https://res.cloudinary.com/x/p.jpg',
      'warningRequired': true,
      'priority': 120,
      'aiAnalysis': {
        'predictedClass': 'non_emergency',
        'confidence': 0.4,
        'severity': 'LOW',
      },
    });
    backend.reply('POST', createPath, 201, {
      'success': true,
      'data': emergencyJson(),
    });
    final (c, flow) = await startFlow();
    await flow.pickPhoto(ImageSource.camera);

    await flow.send();
    expect(stateOf(c).step, FlowStep.aiWarning);
    expect(backend.count('POST', createPath), 0);

    await flow.sendDespiteAiWarning();
    expect(stateOf(c).step, FlowStep.submitted);
    // The photo is not uploaded a second time.
    expect(backend.count('POST', precheckPath), 1);
  });

  test('a failed photo upload never blocks sending without it', () async {
    backend.reply('POST', precheckPath, 500, {
      'success': false,
      'message': 'Image upload failed',
    });
    backend.reply('POST', createPath, 201, {
      'success': true,
      'data': emergencyJson(),
    });
    final (c, flow) = await startFlow();
    await flow.pickPhoto(ImageSource.camera);

    await flow.send();
    expect(stateOf(c).step, FlowStep.photoUploadFailed);
    expect(backend.count('POST', createPath), 0);

    await flow.sendWithoutPhoto();
    expect(stateOf(c).step, FlowStep.submitted);
    expect(
      backend.lastBody('POST', createPath).containsKey('imageUrl'),
      isFalse,
    );
  });

  test('a server rejection is a definite failure, not "unknown"', () async {
    backend.reply('POST', createPath, 500, {
      'success': false,
      'message': 'internal stack trace',
    });
    final (c, flow) = await startFlow();

    await flow.send();

    expect(stateOf(c).step, FlowStep.failed);
    expect(stateOf(c).error?.kind, ApiErrorKind.server);
    expect(store.values.containsKey('active_emergency_id'), isFalse);
  });

  test('a timeout is never resent automatically (anonymous user)', () async {
    backend.timeout('POST', createPath);
    final (c, flow) = await startFlow();

    await flow.send();

    expect(stateOf(c).step, FlowStep.outcomeUnknown);
    expect(backend.count('POST', createPath), 1);

    // Only an explicit user decision sends it again.
    backend.reply('POST', createPath, 201, {
      'success': true,
      'data': emergencyJson(id: 'second'),
    });
    await flow.sendAgain();
    expect(backend.count('POST', createPath), 2);
    expect(stateOf(c).created?.id, 'second');
  });

  test(
    'after a timeout a signed-in user is reconciled with their history',
    () async {
      backend.timeout('POST', createPath);
      backend.reply('GET', '/api/emergency', 200, {
        'success': true,
        'data': [
          emergencyJson(id: 'old-done', status: 'COMPLETED'),
          emergencyJson(id: 'just-created'),
        ],
      });
      final (c, flow) = await startFlow(signedIn: true);

      await flow.send();

      expect(stateOf(c).step, FlowStep.submitted);
      expect(stateOf(c).created?.id, 'just-created');
      expect(backend.count('POST', createPath), 1);
      expect(store.values['active_emergency_id'], 'just-created');
    },
  );

  test('reconciliation ignores requests older than the window', () async {
    backend.timeout('POST', createPath);
    final old = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 2))
        .toIso8601String();
    backend.reply('GET', '/api/emergency', 200, {
      'success': true,
      'data': [emergencyJson(id: 'stale', createdAt: old)],
    });
    final (c, flow) = await startFlow(signedIn: true);

    await flow.send();

    expect(stateOf(c).step, FlowStep.outcomeUnknown);
  });
}
