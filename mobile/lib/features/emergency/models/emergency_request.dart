import 'dart:math' as math;

import '../../../core/utils/json.dart';
import 'emergency_status.dart';

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Accepts `{latitude, longitude}` (REST) and `{lat, lng}` (socket events).
  static GeoPoint? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = asJsonMap(value);
    final lat = optionalDouble(json, 'latitude') ?? optionalDouble(json, 'lat');
    final lng =
        optionalDouble(json, 'longitude') ?? optionalDouble(json, 'lng');
    if (lat == null || lng == null) return null;
    // The backend fills missing booking coordinates with 0,0.
    if (lat == 0 && lng == 0) return null;
    return GeoPoint(lat, lng);
  }

  /// Straight-line distance in metres (haversine). Not a route distance.
  double distanceTo(GeoPoint other) {
    const earthRadius = 6371000.0;
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(other.latitude - latitude);
    final dLng = rad(other.longitude - longitude);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(latitude)) *
            math.cos(rad(other.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

/// AI-generated image analysis. Only built when the backend actually ran the
/// classifier: with AI disabled, Mongo still stores schema defaults
/// (`predictedClass: ""`, `severity: "LOW"`), which must not be shown as a result.
class AiAnalysis {
  const AiAnalysis({
    required this.predictedClass,
    required this.confidence,
    this.severity,
    this.recommendedAmbulance,
  });

  final String predictedClass;

  /// 0..1
  final double confidence;
  final String? severity;
  final String? recommendedAmbulance;

  static AiAnalysis? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = asJsonMap(value);
    final predictedClass = optionalString(json, 'predictedClass');
    if (predictedClass == null) return null;
    return AiAnalysis(
      predictedClass: predictedClass,
      confidence: optionalDouble(json, 'confidence') ?? 0,
      severity: optionalString(json, 'severity'),
      recommendedAmbulance: optionalString(json, 'recommendedAmbulance'),
    );
  }

  String get confidencePercent => '${(confidence * 100).round()}%';
}

/// The assigned government ambulance. `ambulance` is an id until populated.
class AssignedAmbulance {
  const AssignedAmbulance({
    required this.id,
    this.driverName,
    this.mobile,
    this.vehicleNumber,
    this.location,
  });

  final String id;
  final String? driverName;
  final String? mobile;
  final String? vehicleNumber;
  final GeoPoint? location;

  static AssignedAmbulance? fromJson(Object? value) {
    final id = refId(value);
    if (id == null) return null;
    if (value is! Map) return AssignedAmbulance(id: id);
    final json = asJsonMap(value);
    return AssignedAmbulance(
      id: id,
      driverName: optionalString(json, 'name'),
      mobile: optionalString(json, 'mobile'),
      vehicleNumber: optionalString(json, 'vehicleNumber'),
      location: GeoPoint.fromJson(json['currentLocation']),
    );
  }
}

class HospitalSummary {
  const HospitalSummary({
    required this.id,
    this.name,
    this.address,
    this.city,
    this.mobile,
  });

  final String id;
  final String? name;
  final String? address;
  final String? city;
  final String? mobile;

  static HospitalSummary? fromJson(Object? value) {
    final id = refId(value);
    if (id == null) return null;
    if (value is! Map) return HospitalSummary(id: id);
    final json = asJsonMap(value);
    return HospitalSummary(
      id: id,
      name: optionalString(json, 'name'),
      address: optionalString(json, 'address'),
      city: optionalString(json, 'city'),
      mobile: optionalString(json, 'mobile'),
    );
  }

  String? get fullAddress {
    final parts = [address, city].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// `EmergencyRequest` as returned by `/api/emergency` endpoints and the
/// `emergency_updated` socket event.
class EmergencyRequest {
  const EmergencyRequest({
    required this.id,
    required this.status,
    required this.rawStatus,
    this.createdAt,
    this.updatedAt,
    this.location,
    this.imageUrl,
    this.aiAnalysis,
    this.duplicateDetected = false,
    this.duplicateOfId,
    this.ambulance,
    this.hospital,
    this.evidenceCount = 0,
  });

  final String id;
  final EmergencyStatus status;

  /// Exact backend value, shown when [status] is unknown.
  final String rawStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final GeoPoint? location;
  final String? imageUrl;
  final AiAnalysis? aiAnalysis;

  /// The backend flagged this as a duplicate and did NOT send it to ambulances.
  final bool duplicateDetected;
  final String? duplicateOfId;
  final AssignedAmbulance? ambulance;
  final HospitalSummary? hospital;
  final int evidenceCount;

  factory EmergencyRequest.fromJson(Map<String, dynamic> json) {
    final rawStatus = requireString(json, 'status');
    final evidence = json['evidence'];
    return EmergencyRequest(
      id: requireString(json, '_id'),
      status: EmergencyStatus.fromApi(rawStatus),
      rawStatus: rawStatus,
      createdAt: optionalDate(json, 'createdAt'),
      updatedAt: optionalDate(json, 'updatedAt'),
      location: GeoPoint.fromJson(json['location']),
      imageUrl: optionalString(json, 'imageUrl'),
      aiAnalysis: AiAnalysis.fromJson(json['aiAnalysis']),
      duplicateDetected: json['duplicateDetected'] == true,
      duplicateOfId: refId(json['duplicateOf']),
      ambulance: AssignedAmbulance.fromJson(json['ambulance']),
      hospital: HospitalSummary.fromJson(json['hospital']),
      evidenceCount: evidence is List ? evidence.length : 0,
    );
  }

  String get statusLabel =>
      status == EmergencyStatus.unknown ? 'Status: $rawStatus' : status.label;
}
