import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:emstrap_mobile/core/config/app_config.dart';
import 'package:emstrap_mobile/core/network/api_client.dart';
import 'package:emstrap_mobile/core/realtime/realtime_service.dart';
import 'package:emstrap_mobile/core/storage/secure_store.dart';
import 'package:emstrap_mobile/core/storage/token_storage.dart';
import 'package:emstrap_mobile/features/emergency/data/location_service.dart';
import 'package:emstrap_mobile/features/emergency/models/emergency_request.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeResponse {
  const FakeResponse(this.status, [this.body]);

  final int status;
  final Object? body;
}

typedef FakeHandler = FutureOr<FakeResponse> Function(RequestOptions options);

/// Scripted backend: handlers are keyed by "METHOD /path". Every request is
/// recorded so tests can assert what was (and was not) sent.
class FakeBackend implements HttpClientAdapter {
  final _handlers = <String, FakeHandler>{};
  final requests = <RequestOptions>[];

  void on(String method, String path, FakeHandler handler) =>
      _handlers['$method $path'] = handler;

  void reply(String method, String path, int status, [Object? body]) =>
      on(method, path, (_) => FakeResponse(status, body));

  /// Simulates a request that never got an answer (server may have run it).
  void timeout(String method, String path) => on(
    method,
    path,
    (o) => throw DioException(
      requestOptions: o,
      type: DioExceptionType.receiveTimeout,
    ),
  );

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path).length;

  Map<String, dynamic> lastBody(String method, String path) =>
      requests.lastWhere((r) => r.method == method && r.path == path).data
          as Map<String, dynamic>;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = _handlers['${options.method} ${options.path}'];
    if (handler == null) {
      throw StateError('No fake handler for ${options.method} ${options.path}');
    }
    final response = await handler(options);
    return ResponseBody.fromString(
      jsonEncode(response.body ?? {}),
      response.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class FakeLocationService extends LocationService {
  FakeLocationService({LocationResult? result, this.permission = true})
    : result =
          result ??
          LocationFix(
            point: const GeoPoint(28.6139, 77.209),
            accuracyMeters: 8,
            capturedAt: DateTime(2026, 10, 24, 12),
          );

  LocationResult result;
  bool permission;
  final positions = StreamController<GeoPoint>.broadcast();

  @override
  Future<LocationResult> currentFix() async => result;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Stream<GeoPoint> watch() => positions.stream;
}

class FakeRealtime implements RealtimeService {
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  final tracked = <String>{};
  final emitted = <(String, Map<String, Object?>)>[];
  bool connected = true;

  void push(String name, [Object? payload]) =>
      _events.add(RealtimeEvent(name, payload));

  void setConnected(bool value) {
    connected = value;
    _connection.add(value);
  }

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Stream<bool> get connection => _connection.stream;

  @override
  bool get isConnected => connected;

  @override
  void trackRequest(String requestId) => tracked.add(requestId);

  @override
  void untrackRequest(String requestId) => tracked.remove(requestId);

  @override
  void emitIfConnected(String event, Map<String, Object?> data) {
    if (connected) emitted.add((event, data));
  }

  @override
  void dispose() {}
}

/// A container wired like the app, but with the HTTP layer, storage, GPS and
/// socket replaced by fakes. The real Dio client and interceptors still run.
ProviderContainer makeContainer({
  required FakeBackend backend,
  InMemorySecureStore? store,
  FakeLocationService? location,
  FakeRealtime? realtime,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(apiBaseUrl: 'http://backend.test'),
      ),
      secureStoreProvider.overrideWithValue(store ?? InMemorySecureStore()),
      dioProvider.overrideWith((ref) {
        final dio = buildDio(
          baseUrl: 'http://backend.test',
          tokens: ref.watch(tokenStorageProvider),
          onSessionExpired: ref.watch(sessionEventsProvider).notifyExpired,
        );
        dio.httpClientAdapter = backend;
        return dio;
      }),
      locationServiceProvider.overrideWithValue(
        location ?? FakeLocationService(),
      ),
      realtimeServiceProvider.overrideWithValue(realtime ?? FakeRealtime()),
      ...overrides,
    ],
  );
  return container;
}

/// Lets queued microtasks and fake async replies run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// Polls until [condition] holds, so tests don't depend on timing.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

// ---- Payloads shaped like the real backend (captured 2026-10-24) ----------

Map<String, dynamic> loginResponse({
  String role = 'user',
  String token = 'jwt-token',
}) => {
  'success': true,
  'message': 'Login successful',
  'token': token,
  'user': {
    '_id': 'u1',
    'name': 'Test User',
    'email': 'user@emstrap.local',
    'role': role,
    'driverStatus': 'OFFLINE',
    'isOnTrip': false,
  },
  '_id': 'u1',
  'role': role,
};

Map<String, dynamic> meResponse({String role = 'user'}) => {
  '_id': 'u1',
  'name': 'Test User',
  'email': 'user@emstrap.local',
  'mobile': '9876500001',
  'city': 'Delhi',
  'role': role,
  'isEmailVerified': true,
};

/// An emergency as stored with AI disabled: note the schema-default
/// `aiAnalysis`, which must NOT be shown as an AI result.
Map<String, dynamic> emergencyJson({
  String id = 'e1',
  String status = 'PENDING',
  String? createdAt,
  Object? ambulance,
  bool duplicate = false,
  Map<String, dynamic>? aiAnalysis,
}) => {
  '_id': id,
  'status': status,
  'requestType': 'EMERGENCY',
  'location': {'latitude': 28.6139, 'longitude': 77.209},
  'imageUrl': '',
  'aiAnalysis':
      aiAnalysis ??
      {
        'predictedClass': '',
        'confidence': 0,
        'severity': 'LOW',
        'recommendedAmbulance': '',
      },
  'duplicateDetected': duplicate,
  'duplicateOf': null,
  'embedding': <double>[],
  'evidence': <Object>[],
  'ambulance': ambulance,
  'hospital': null,
  'createdAt': createdAt ?? DateTime.now().toUtc().toIso8601String(),
  'updatedAt': DateTime.now().toUtc().toIso8601String(),
};
