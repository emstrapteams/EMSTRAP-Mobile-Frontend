import 'package:flutter/material.dart';

/// Brand palette taken from the EMSTRAP logo: deep blue wordmark, red
/// emergency light. Red is reserved for emergency actions and states.
abstract final class AppColors {
  static const navy = Color(0xFF0B2545);
  static const brandBlue = Color(0xFF1B5FAA);
  static const emergencyRed = Color(0xFFC62828);
  static const emergencyRedDark = Color(0xFF8E1B1B);

  static const surface = Color(0xFFF5F7FA);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFDCE3EC);
  static const textPrimary = Color(0xFF0F1B2D);
  static const textSecondary = Color(0xFF4D5C72);

  // Status tones: text colours chosen for ≥4.5:1 contrast on their tint.
  static const info = Color(0xFF1B5FAA);
  static const success = Color(0xFF1E6B2A);
  static const warning = Color(0xFF8A5100);
  static const danger = Color(0xFFB71C1C);
  static const neutral = Color(0xFF4D5C72);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;

  /// Horizontal page padding used by every screen.
  static const page = EdgeInsets.symmetric(horizontal: md);
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}
