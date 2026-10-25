import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Runs a request and converts every failure into an [ApiException], so
/// repositories never leak Dio or parsing errors to the UI.
Future<T> apiCall<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  } on FormatException {
    throw ApiException.badResponse();
  } on TypeError {
    // A field had an unexpected type while parsing the response.
    throw ApiException.badResponse();
  }
}
