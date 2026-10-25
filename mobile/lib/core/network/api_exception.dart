import 'package:dio/dio.dart';

enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  validation,
  notFound,
  conflict,
  rateLimited,
  server,
  badResponse,
  cancelled,
}

/// The single error type the UI sees. [message] is always safe to show.
class ApiException implements Exception {
  const ApiException(
    this.kind,
    this.message, {
    this.statusCode,
    this.mayHaveReachedServer = false,
    this.responseData,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  /// True when the request could have been processed even though no response
  /// arrived (timeouts, dropped connections). Non-idempotent requests such as
  /// creating an emergency must not be blindly resent in that case.
  final bool mayHaveReachedServer;

  /// Raw error body, for the few endpoints that return useful data with an
  /// error status (e.g. precheck's 503 still carries `secureImageUrl`).
  final Object? responseData;

  static const _genericServerMessage =
      'Something went wrong on the EMSTRAP server. Please try again.';

  factory ApiException.badResponse() => const ApiException(
    ApiErrorKind.badResponse,
    'The server sent an unexpected response. Please try again.',
  );

  factory ApiException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return const ApiException(
          ApiErrorKind.timeout,
          'Could not reach the EMSTRAP server in time. Check your connection.',
        );
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          ApiErrorKind.timeout,
          'The EMSTRAP server is taking too long to respond.',
          mayHaveReachedServer: true,
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
      case DioExceptionType.badCertificate:
        // Dio can't tell "never connected" from "dropped mid-request", so
        // assume the worst for anything that might have been sent.
        return const ApiException(
          ApiErrorKind.network,
          'No connection to the EMSTRAP server. Check your internet connection.',
          mayHaveReachedServer: true,
        );
      case DioExceptionType.cancel:
        return const ApiException(
          ApiErrorKind.cancelled,
          'The request was cancelled.',
        );
      case DioExceptionType.badResponse:
        return ApiException.fromStatus(
          e.response?.statusCode ?? 0,
          e.response?.data,
        );
    }
  }

  factory ApiException.fromStatus(int status, Object? data) {
    final serverMessage = _serverMessage(data);
    ApiException build(ApiErrorKind kind, String fallback) => ApiException(
      kind,
      serverMessage ?? fallback,
      statusCode: status,
      responseData: data,
    );

    if (status == 400 || status == 422) {
      return build(
        ApiErrorKind.validation,
        'Please check the details and try again.',
      );
    }
    if (status == 401) {
      return build(ApiErrorKind.unauthorized, 'Please log in to continue.');
    }
    if (status == 403) {
      return build(ApiErrorKind.forbidden, 'You do not have access to this.');
    }
    if (status == 404) {
      return build(
        ApiErrorKind.notFound,
        'We could not find what you were looking for.',
      );
    }
    if (status == 409) {
      return build(ApiErrorKind.conflict, 'This was already handled.');
    }
    if (status == 429) {
      return build(
        ApiErrorKind.rateLimited,
        'Too many attempts. Please wait a moment.',
      );
    }
    // 5xx bodies often carry raw exception text, so never show them.
    return ApiException(
      ApiErrorKind.server,
      _genericServerMessage,
      statusCode: status,
      responseData: data,
    );
  }

  static String? _serverMessage(Object? data) {
    if (data is Map && data['message'] is String) {
      final message = (data['message'] as String).trim();
      if (message.isNotEmpty) return message;
    }
    return null;
  }

  @override
  String toString() => 'ApiException($kind, status: $statusCode)';
}
