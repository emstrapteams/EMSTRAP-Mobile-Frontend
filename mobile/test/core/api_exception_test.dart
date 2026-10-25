import 'package:dio/dio.dart';
import 'package:emstrap_mobile/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final options = RequestOptions(path: '/x');
  DioException timeout(DioExceptionType type) =>
      DioException(requestOptions: options, type: type);

  group('ApiException.fromStatus', () {
    test('uses the backend message for client errors', () {
      final e = ApiException.fromStatus(401, {
        'success': false,
        'message': 'Please verify your email to login',
      });
      expect(e.kind, ApiErrorKind.unauthorized);
      expect(e.message, 'Please verify your email to login');
    });

    test('maps status codes to kinds', () {
      expect(ApiException.fromStatus(400, null).kind, ApiErrorKind.validation);
      expect(ApiException.fromStatus(403, null).kind, ApiErrorKind.forbidden);
      expect(ApiException.fromStatus(404, null).kind, ApiErrorKind.notFound);
      expect(ApiException.fromStatus(409, null).kind, ApiErrorKind.conflict);
      expect(ApiException.fromStatus(429, null).kind, ApiErrorKind.rateLimited);
      expect(ApiException.fromStatus(503, null).kind, ApiErrorKind.server);
    });

    test('never shows raw server error text for 5xx', () {
      final e = ApiException.fromStatus(500, {
        'message': 'Cast to ObjectId failed for value "x"',
      });
      expect(e.kind, ApiErrorKind.server);
      expect(e.message, isNot(contains('ObjectId')));
    });

    test('keeps the error body for callers that need it', () {
      final e = ApiException.fromStatus(503, {'secureImageUrl': 'https://img'});
      expect((e.responseData as Map)['secureImageUrl'], 'https://img');
    });
  });

  group('ApiException.fromDio', () {
    test('a connect timeout means the request was never sent', () {
      final e = ApiException.fromDio(
        timeout(DioExceptionType.connectionTimeout),
      );
      expect(e.kind, ApiErrorKind.timeout);
      expect(e.mayHaveReachedServer, isFalse);
    });

    test('a receive timeout may have reached the server', () {
      final e = ApiException.fromDio(timeout(DioExceptionType.receiveTimeout));
      expect(e.kind, ApiErrorKind.timeout);
      expect(e.mayHaveReachedServer, isTrue);
    });

    test('connection errors are treated as possibly delivered', () {
      final e = ApiException.fromDio(timeout(DioExceptionType.connectionError));
      expect(e.kind, ApiErrorKind.network);
      expect(e.mayHaveReachedServer, isTrue);
    });

    test('an HTTP error response means the outcome is known', () {
      final e = ApiException.fromDio(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 400,
            data: {'message': 'Bad'},
          ),
        ),
      );
      expect(e.kind, ApiErrorKind.validation);
      expect(e.mayHaveReachedServer, isFalse);
    });
  });
}
