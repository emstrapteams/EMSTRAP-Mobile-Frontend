import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_call.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/json.dart';
import '../models/emergency_request.dart';
import '../models/precheck_result.dart';

/// `/api/emergency` endpoints used by the person requesting help. Creating,
/// viewing and cancelling work with or without a login (`optionalAuth`).
class EmergencyRepository {
  EmergencyRepository(this._dio);

  final Dio _dio;

  /// Photos travel as base64 data URLs inside JSON (the backend has no
  /// multipart route), so uploads get a longer timeout.
  static final _uploadOptions = Options(
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  );

  /// Uploads the photo and runs the AI check. No emergency is created, so
  /// retrying is safe.
  Future<PrecheckResult> precheck({
    required String imageDataUrl,
    required GeoPoint location,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        '/api/emergency/precheck',
        data: {
          'imageUrl': imageDataUrl,
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
        options: _uploadOptions,
      );
      final body = asJsonMap(response.data);
      return PrecheckResult(
        secureImageUrl: requireString(body, 'secureImageUrl'),
        aiAvailable: true,
        aiAnalysis: AiAnalysis.fromJson(body['aiAnalysis']),
        warningRequired: body['warningRequired'] == true,
      );
    } on DioException catch (e) {
      // 503 = AI disabled, but the photo was uploaded and its URL returned.
      final data = e.response?.data;
      if (e.response?.statusCode == 503 &&
          data is Map &&
          data['secureImageUrl'] is String) {
        return PrecheckResult(
          secureImageUrl: data['secureImageUrl'] as String,
          aiAvailable: false,
        );
      }
      throw ApiException.fromDio(e);
    } on FormatException {
      throw ApiException.badResponse();
    }
  }

  /// NOT idempotent. Never retried automatically: on a timeout the server
  /// may have created the request even though no response arrived.
  Future<EmergencyRequest> create({
    required GeoPoint location,
    String? imageUrl,
  }) {
    return apiCall(() async {
      final response = await _dio.post<Object?>(
        '/api/emergency',
        data: {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'imageUrl': ?imageUrl,
        },
      );
      return EmergencyRequest.fromJson(
        asJsonMap(asJsonMap(response.data)['data']),
      );
    });
  }

  Future<EmergencyRequest> fetch(String id) {
    return apiCall(() async {
      final response = await _dio.get<Object?>('/api/emergency/$id');
      return EmergencyRequest.fromJson(
        asJsonMap(asJsonMap(response.data)['data']),
      );
    });
  }

  /// The signed-in user's emergencies, newest first. Requires a login.
  Future<List<EmergencyRequest>> listMine() {
    return apiCall(() async {
      final response = await _dio.get<Object?>('/api/emergency');
      return asJsonList(
        asJsonMap(response.data)['data'],
      ).map(EmergencyRequest.fromJson).toList();
    });
  }

  Future<void> cancel(String id) {
    return apiCall(() => _dio.put<Object?>('/api/emergency/$id/user-cancel'));
  }

  Future<void> addEvidence(String id, String imageDataUrl) {
    return apiCall(
      () => _dio.post<Object?>(
        '/api/emergency/$id/evidence',
        data: {'imageUrl': imageDataUrl},
        options: _uploadOptions,
      ),
    );
  }
}

final emergencyRepositoryProvider = Provider<EmergencyRepository>(
  (ref) => EmergencyRepository(ref.watch(dioProvider)),
);
