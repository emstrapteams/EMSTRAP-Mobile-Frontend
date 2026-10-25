import 'package:flutter/material.dart';

import '../../../shared/widgets/status_chip.dart';

/// `EmergencyRequest.status` enum from `emergencyRequest.model.js`.
enum EmergencyStatus {
  pending(
    'PENDING',
    'Waiting for an ambulance',
    StatusTone.warning,
    Icons.hourglass_top_rounded,
  ),
  ambulanceAccepted(
    'AMBULANCE_ACCEPTED',
    'Ambulance on the way',
    StatusTone.info,
    Icons.local_shipping_rounded,
  ),
  arrivedAtLocation(
    'ARRIVED_AT_LOCATION',
    'Ambulance has arrived',
    StatusTone.info,
    Icons.place_rounded,
  ),
  enRouteToHospital(
    'EN_ROUTE_TO_HOSPITAL',
    'On the way to hospital',
    StatusTone.info,
    Icons.local_hospital_rounded,
  ),
  completed(
    'COMPLETED',
    'Completed',
    StatusTone.success,
    Icons.check_circle_rounded,
  ),
  cancelled('CANCELLED', 'Cancelled', StatusTone.neutral, Icons.cancel_rounded),

  /// A value this app version doesn't know. Shown as-is, never guessed.
  unknown('', 'Unknown status', StatusTone.neutral, Icons.help_outline_rounded);

  const EmergencyStatus(this.apiValue, this.label, this.tone, this.icon);

  final String apiValue;
  final String label;
  final StatusTone tone;
  final IconData icon;

  static EmergencyStatus fromApi(String value) =>
      EmergencyStatus.values.firstWhere(
        (s) => s.apiValue == value,
        orElse: () => EmergencyStatus.unknown,
      );

  bool get isTerminal => this == completed || this == cancelled;

  /// The forward path shown in the status timeline.
  static const progression = [
    pending,
    ambulanceAccepted,
    arrivedAtLocation,
    enRouteToHospital,
    completed,
  ];
}
