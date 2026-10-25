/// Roles as the backend stores them. Several have legacy aliases that
/// `auth.middleware.js` and the web client treat as the same role.
enum UserRole {
  user('Personal'),
  ambulanceDriver('Ambulance driver'),
  privateDriver('Private ambulance driver'),
  hospital('Hospital'),
  police('Police'),
  admin('Administrator'),
  unknown('Unknown');

  const UserRole(this.label);

  final String label;

  static UserRole fromApi(String? value) => switch (value) {
    'user' => UserRole.user,
    'ambulance_driver' || 'ambulance' => UserRole.ambulanceDriver,
    'private_driver' => UserRole.privateDriver,
    'hospital' || 'hospital_admin' => UserRole.hospital,
    'police' || 'police_hq' => UserRole.police,
    'admin' => UserRole.admin,
    _ => UserRole.unknown,
  };
}
