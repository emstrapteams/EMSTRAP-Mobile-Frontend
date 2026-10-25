import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';

/// Set `extra: {skipAuth: true}` on requests that must not carry the token.
const skipAuth = 'skipAuth';

final appConfigProvider = Provider<AppConfig>(
  (_) => throw UnimplementedError('appConfigProvider is overridden in main()'),
);

/// Broadcasts "an authenticated request came back 401". The auth controller
/// listens and signs the user out; core never imports feature code.
class SessionEvents {
  final _expired = StreamController<void>.broadcast();

  Stream<void> get expired => _expired.stream;

  void notifyExpired() => _expired.add(null);

  void dispose() => _expired.close();
}

final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

final dioProvider = Provider<Dio>((ref) {
  final events = ref.watch(sessionEventsProvider);
  return buildDio(
    baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
    tokens: ref.watch(tokenStorageProvider),
    onSessionExpired: events.notifyExpired,
  );
});

Dio buildDio({
  required String baseUrl,
  required TokenStorage tokens,
  required void Function() onSessionExpired,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors.add(_AuthInterceptor(tokens, onSessionExpired));
  if (kDebugMode) dio.interceptors.add(_SafeLogInterceptor());
  return dio;
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._tokens, this._onSessionExpired);

  final TokenStorage _tokens;
  final void Function() _onSessionExpired;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[skipAuth] != true) {
      final token = await _tokens.read();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final sentToken = err.requestOptions.headers.containsKey('Authorization');
    // Only an authenticated request can prove the session expired. No retry
    // or refresh here: the backend has no refresh endpoint.
    if (err.response?.statusCode == 401 && sentToken) _onSessionExpired();
    handler.next(err);
  }
}

/// Logs method, path and status only. Never headers, bodies or query
/// strings: those carry tokens, credentials, locations and photos.
class _SafeLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['startedAt'] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, err.response?.statusCode, err.type.name);
    handler.next(err);
  }

  void _log(RequestOptions options, int? status, [String? error]) {
    final started = options.extra['startedAt'];
    final ms = started is DateTime
        ? DateTime.now().difference(started).inMilliseconds
        : null;
    debugPrint(
      '[api] ${options.method} ${options.uri.path} → ${status ?? error} (${ms}ms)',
    );
  }
}
