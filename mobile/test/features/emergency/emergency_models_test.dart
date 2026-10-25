import 'package:emstrap_mobile/features/emergency/models/emergency_request.dart';
import 'package:emstrap_mobile/features/emergency/models/emergency_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  test('parses a request created with AI disabled', () {
    final r = EmergencyRequest.fromJson(emergencyJson());
    expect(r.id, 'e1');
    expect(r.status, EmergencyStatus.pending);
    expect(r.location?.latitude, 28.6139);
    expect(r.imageUrl, isNull);
    // Schema defaults ("", 0, "LOW") are not an AI result.
    expect(r.aiAnalysis, isNull);
    expect(r.ambulance, isNull);
  });

  test('parses a real AI result', () {
    final r = EmergencyRequest.fromJson(
      emergencyJson(
        aiAnalysis: {
          'predictedClass': 'accident',
          'confidence': 0.87,
          'severity': 'HIGH',
        },
      ),
    );
    expect(r.aiAnalysis?.predictedClass, 'accident');
    expect(r.aiAnalysis?.confidencePercent, '87%');
  });

  test('handles populated and unpopulated ambulance references', () {
    final populated = EmergencyRequest.fromJson(
      emergencyJson(
        status: 'AMBULANCE_ACCEPTED',
        ambulance: {
          '_id': 'a1',
          'name': 'Test Driver',
          'mobile': '9876500002',
          'vehicleNumber': 'DL01AB1234',
          'currentLocation': {'latitude': 28.62, 'longitude': 77.21},
        },
      ),
    );
    expect(populated.ambulance?.driverName, 'Test Driver');
    expect(populated.ambulance?.location?.latitude, 28.62);

    final idOnly = EmergencyRequest.fromJson(emergencyJson(ambulance: 'a1'));
    expect(idOnly.ambulance?.id, 'a1');
    expect(idOnly.ambulance?.driverName, isNull);
  });

  test('an unknown status is kept verbatim, never mapped to a guess', () {
    final r = EmergencyRequest.fromJson(
      emergencyJson(status: 'HOSPITAL_ASSIGNED'),
    );
    expect(r.status, EmergencyStatus.unknown);
    expect(r.statusLabel, 'Status: HOSPITAL_ASSIGNED');
    expect(r.status.isTerminal, isFalse);
  });

  test('a response without id or status is rejected', () {
    expect(
      () => EmergencyRequest.fromJson({'status': 'PENDING'}),
      throwsFormatException,
    );
    expect(
      () => EmergencyRequest.fromJson({'_id': 'x'}),
      throwsFormatException,
    );
  });

  test('GeoPoint reads REST and socket shapes and drops 0,0 placeholders', () {
    expect(
      GeoPoint.fromJson({'latitude': 1.5, 'longitude': 2.5})?.longitude,
      2.5,
    );
    expect(
      GeoPoint.fromJson({'lat': 1.5, 'lng': 2.5, 'requestId': 'e1'})?.latitude,
      1.5,
    );
    expect(GeoPoint.fromJson({'latitude': 0, 'longitude': 0}), isNull);
  });

  test('straight-line distance is roughly right', () {
    const a = GeoPoint(28.6139, 77.2090);
    const b = GeoPoint(28.6239, 77.2090);
    expect(a.distanceTo(b), closeTo(1112, 5));
  });
}
