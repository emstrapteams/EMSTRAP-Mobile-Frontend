import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_call.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/utils/json.dart';
import '../models/app_user.dart';
import '../models/registration.dart';

/// Auth endpoints (`/auth/*`). The backend sets an HttpOnly cookie for the
/// web app and also returns the JWT in the body. The app uses the body token
/// as a Bearer header, which `auth.middleware.js` accepts.
class AuthRepository {
  AuthRepository(this._dio, this._tokens);

  final Dio _dio;
  final TokenStorage _tokens;

  Future<AppUser> login({required String email, required String password}) {
    return apiCall(() async {
      final response = await _dio.post<Object?>(
        '/auth/login',
        data: {'email': email.trim().toLowerCase(), 'password': password},
        options: Options(extra: {skipAuth: true}),
      );
      final body = asJsonMap(response.data);
      final token = requireString(body, 'token');
      final user = AppUser.fromJson(asJsonMap(body['user'] ?? body));
      await _tokens.write(token);
      return user;
    });
  }

  /// Returns the current user, or null when there is no valid session. Other
  /// errors (offline, server down) are rethrown so the caller can offer a
  /// retry instead of silently logging the user out.
  Future<AppUser?> restoreSession() async {
    if (await _tokens.read() == null) return null;
    try {
      return await apiCall(() async {
        final response = await _dio.get<Object?>('/auth/me');
        final body = asJsonMap(response.data);
        return AppUser.fromJson(asJsonMap(body['user'] ?? body));
      });
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized) {
        await _tokens.clear();
        return null;
      }
      rethrow;
    }
  }

  Future<void> register(Registration registration) {
    return apiCall(() async {
      await _dio.post<Object?>(
        '/auth/register',
        data: registration.toJson(),
        options: Options(extra: {skipAuth: true}),
      );
    });
  }

  /// Clears the local session even if the server call fails: the JWT can't
  /// be revoked server-side anyway (the backend only clears its cookie).
  Future<void> logout() async {
    try {
      await _dio.post<Object?>('/auth/logout');
    } on DioException {
      // Best effort.
    } finally {
      await _tokens.clear();
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      AuthRepository(ref.watch(dioProvider), ref.watch(tokenStorageProvider)),
);
