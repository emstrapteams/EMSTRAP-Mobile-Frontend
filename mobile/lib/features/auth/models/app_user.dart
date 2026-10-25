import '../../../core/utils/json.dart';
import 'user_role.dart';

/// The signed-in account. Parsed from the login response's `user` object or
/// from `GET /auth/me`, which returns the document without a wrapper.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.rawRole,
    this.mobile,
    this.city,
    this.address,
    this.vehicleNumber,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;

  /// The role string exactly as the backend sent it, e.g. `police_hq`.
  final String rawRole;
  final String? mobile;
  final String? city;
  final String? address;
  final String? vehicleNumber;

  /// Identity and role are required: routing depends on them, so a response
  /// without them is rejected rather than guessed.
  factory AppUser.fromJson(Map<String, dynamic> json) {
    final rawRole = requireString(json, 'role');
    return AppUser(
      id: requireString(json, '_id'),
      name: optionalString(json, 'name') ?? '',
      email: optionalString(json, 'email') ?? '',
      role: UserRole.fromApi(rawRole),
      rawRole: rawRole,
      mobile: optionalString(json, 'mobile'),
      city: optionalString(json, 'city'),
      address: optionalString(json, 'address'),
      vehicleNumber: optionalString(json, 'vehicleNumber'),
    );
  }
}
