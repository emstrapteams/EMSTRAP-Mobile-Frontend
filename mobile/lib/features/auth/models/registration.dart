import 'user_role.dart';

/// Body for `POST /auth/register`. Only `user` and `ambulance_driver` may
/// self-register; other roles are created by an administrator.
class Registration {
  const Registration({
    required this.name,
    required this.email,
    required this.password,
    required this.mobile,
    required this.city,
    required this.address,
    required this.role,
    this.vehicleNumber,
  });

  static const selfRegisterRoles = [UserRole.user, UserRole.ambulanceDriver];

  final String name;
  final String email;
  final String password;
  final String mobile;
  final String city;
  final String address;
  final UserRole role;
  final String? vehicleNumber;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'email': email.trim().toLowerCase(),
    'password': password,
    'mobile': mobile.trim(),
    'city': city.trim(),
    'address': address.trim(),
    'role': role == UserRole.ambulanceDriver ? 'ambulance_driver' : 'user',
    if (role == UserRole.ambulanceDriver &&
        vehicleNumber != null &&
        vehicleNumber!.trim().isNotEmpty)
      'vehicleNumber': vehicleNumber!.trim().toUpperCase(),
  };
}

/// Same rules as `auth.controller.js`, checked early so the user isn't kept
/// waiting for a round trip. The backend still enforces them.
abstract final class AuthValidators {
  static final _mobile = RegExp(r'^[6-9]\d{9}$');
  static final _password = RegExp(
    r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
  );
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email address';
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? loginPassword(String? value) =>
      (value == null || value.isEmpty) ? 'Enter your password' : null;

  static String? newPassword(String? value) {
    if (value == null || value.isEmpty) return 'Choose a password';
    if (!_password.hasMatch(value)) {
      return 'At least 8 characters with an uppercase letter, a lowercase '
          'letter, a number and one of @ \$ ! % * ? &';
    }
    return null;
  }

  static String? mobile(String? value) {
    if (!_mobile.hasMatch(value?.trim() ?? '')) {
      return 'Enter a valid 10-digit Indian mobile number';
    }
    return null;
  }

  static String? required(String? value, String field) =>
      (value == null || value.trim().isEmpty) ? 'Enter your $field' : null;
}
