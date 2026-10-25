import 'package:emstrap_mobile/features/auth/models/app_user.dart';
import 'package:emstrap_mobile/features/auth/models/registration.dart';
import 'package:emstrap_mobile/features/auth/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserRole.fromApi', () {
    test('maps backend roles including legacy aliases', () {
      expect(UserRole.fromApi('user'), UserRole.user);
      expect(UserRole.fromApi('ambulance_driver'), UserRole.ambulanceDriver);
      expect(UserRole.fromApi('ambulance'), UserRole.ambulanceDriver);
      expect(UserRole.fromApi('private_driver'), UserRole.privateDriver);
      expect(UserRole.fromApi('hospital_admin'), UserRole.hospital);
      expect(UserRole.fromApi('police_hq'), UserRole.police);
      expect(UserRole.fromApi('admin'), UserRole.admin);
    });

    test('unknown roles are not guessed', () {
      expect(UserRole.fromApi('superuser'), UserRole.unknown);
      expect(UserRole.fromApi(null), UserRole.unknown);
    });
  });

  group('AppUser.fromJson', () {
    test('parses the /auth/me document', () {
      final user = AppUser.fromJson({
        '_id': '6adc',
        'name': 'Test User',
        'email': 'user@emstrap.local',
        'mobile': '9876500001',
        'role': 'police_hq',
      });
      expect(user.role, UserRole.police);
      expect(user.rawRole, 'police_hq');
      expect(user.mobile, '9876500001');
    });

    test('rejects a response without id or role', () {
      expect(() => AppUser.fromJson({'role': 'user'}), throwsFormatException);
      expect(() => AppUser.fromJson({'_id': 'x'}), throwsFormatException);
    });
  });

  group('AuthValidators mirror auth.controller.js', () {
    test('mobile must be a 10-digit Indian number', () {
      expect(AuthValidators.mobile('9876500001'), isNull);
      expect(AuthValidators.mobile('5876500001'), isNotNull);
      expect(AuthValidators.mobile('98765'), isNotNull);
    });

    test('password rule matches the backend, including its character set', () {
      expect(AuthValidators.newPassword('Strong1!'), isNull);
      expect(AuthValidators.newPassword('weak'), isNotNull);
      expect(AuthValidators.newPassword('NoSpecial1'), isNotNull);
      // The backend only allows @\$!%*?& as special characters.
      expect(AuthValidators.newPassword('Strong1#'), isNotNull);
    });
  });

  group('Registration.toJson', () {
    test('only sends a vehicle number for drivers', () {
      const base = Registration(
        name: ' Asha ',
        email: 'ASHA@x.in',
        password: 'Strong1!',
        mobile: '9876500001',
        city: 'Delhi',
        address: 'A-1',
        role: UserRole.user,
        vehicleNumber: 'dl01',
      );
      final json = base.toJson();
      expect(json['role'], 'user');
      expect(json['email'], 'asha@x.in');
      expect(json['name'], 'Asha');
      expect(json.containsKey('vehicleNumber'), isFalse);

      final driver = Registration(
        name: 'D',
        email: 'd@x.in',
        password: 'Strong1!',
        mobile: '9876500001',
        city: 'Delhi',
        address: 'A-1',
        role: UserRole.ambulanceDriver,
        vehicleNumber: 'dl01ab1234',
      ).toJson();
      expect(driver['role'], 'ambulance_driver');
      expect(driver['vehicleNumber'], 'DL01AB1234');
    });
  });
}
