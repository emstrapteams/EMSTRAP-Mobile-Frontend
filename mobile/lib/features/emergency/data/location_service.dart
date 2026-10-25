import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/emergency_request.dart';

enum LocationProblem {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unavailable,
}

sealed class LocationResult {
  const LocationResult();
}

class LocationFix extends LocationResult {
  const LocationFix({
    required this.point,
    required this.accuracyMeters,
    required this.capturedAt,
    this.isLastKnown = false,
  });

  final GeoPoint point;
  final double accuracyMeters;
  final DateTime capturedAt;

  /// True when no fresh fix arrived in time and the device's last known
  /// position was used instead. The UI says so.
  final bool isLastKnown;
}

class LocationFailure extends LocationResult {
  const LocationFailure(this.problem);

  final LocationProblem problem;
}

/// Device GPS. Foreground only: there is no background location in this app.
/// Unlike the web client, there is no IP-geolocation fallback: it is far too
/// coarse for dispatch and would send the user's IP to a third party.
class LocationService {
  static const _timeLimit = Duration(seconds: 20);

  Future<LocationResult> currentFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationFailure(LocationProblem.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationFailure(LocationProblem.permissionDeniedForever);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      return const LocationFailure(LocationProblem.permissionDenied);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _timeLimit,
        ),
      );
      return _toFix(position);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      return last == null
          ? const LocationFailure(LocationProblem.timeout)
          : _toFix(last, isLastKnown: true);
    } on Exception {
      return const LocationFailure(LocationProblem.unavailable);
    }
  }

  Future<bool> hasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Position updates while the app is open, at most every 10 m of movement.
  Stream<GeoPoint> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  ).map((p) => GeoPoint(p.latitude, p.longitude));

  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  LocationFix _toFix(Position p, {bool isLastKnown = false}) => LocationFix(
    point: GeoPoint(p.latitude, p.longitude),
    accuracyMeters: p.accuracy,
    capturedAt: p.timestamp.toLocal(),
    isLastKnown: isLastKnown,
  );
}

final locationServiceProvider = Provider<LocationService>(
  (_) => LocationService(),
);
