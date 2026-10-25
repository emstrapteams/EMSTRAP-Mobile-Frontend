import 'package:emstrap_mobile/core/network/api_exception.dart';
import 'package:emstrap_mobile/core/routing/auth_redirect.dart';
import 'package:emstrap_mobile/features/auth/models/app_user.dart';
import 'package:emstrap_mobile/features/auth/providers/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

AuthSignedIn signedInAs(String role) => AuthSignedIn(
  AppUser.fromJson({'_id': 'u1', 'role': role, 'name': 'N', 'email': 'e@x.in'}),
);

void main() {
  group('while the session is being restored', () {
    test('everything waits on the splash screen', () {
      expect(
        authRedirect(const AuthRestoring(), AppRoutes.home),
        AppRoutes.splash,
      );
      expect(authRedirect(const AuthRestoring(), AppRoutes.splash), isNull);
      const failed = AuthRestoreFailed(
        ApiException(ApiErrorKind.network, 'offline'),
      );
      expect(authRedirect(failed, AppRoutes.newEmergency), AppRoutes.splash);
    });
  });

  group('signed out', () {
    const out = AuthSignedOut();

    test('can request and follow an emergency without logging in', () {
      expect(authRedirect(out, AppRoutes.home), isNull);
      expect(authRedirect(out, AppRoutes.newEmergency), isNull);
      expect(authRedirect(out, AppRoutes.emergency('abc')), isNull);
    });

    test('is sent to login for account-only screens', () {
      expect(authRedirect(out, AppRoutes.profile), AppRoutes.login);
      expect(authRedirect(out, AppRoutes.workspace), AppRoutes.login);
    });

    test('leaves the splash screen for home', () {
      expect(authRedirect(out, AppRoutes.splash), AppRoutes.home);
    });
  });

  group('signed in as user', () {
    final user = signedInAs('user');

    test('login and register bounce to home', () {
      expect(authRedirect(user, AppRoutes.login), AppRoutes.home);
      expect(authRedirect(user, AppRoutes.register), AppRoutes.home);
    });

    test('can use the emergency flow and profile', () {
      expect(authRedirect(user, AppRoutes.newEmergency), isNull);
      expect(authRedirect(user, AppRoutes.emergency('abc')), isNull);
      expect(authRedirect(user, AppRoutes.profile), isNull);
    });

    test('cannot open the staff workspace', () {
      expect(authRedirect(user, AppRoutes.workspace), AppRoutes.home);
    });
  });

  group('signed in as staff', () {
    for (final role in [
      'ambulance_driver',
      'ambulance',
      'private_driver',
      'hospital_admin',
      'police_hq',
      'admin',
      'something_new',
    ]) {
      test('$role lands on the workspace, not the patient flow', () {
        final staff = signedInAs(role);
        expect(authRedirect(staff, AppRoutes.home), AppRoutes.workspace);
        expect(
          authRedirect(staff, AppRoutes.newEmergency),
          AppRoutes.workspace,
        );
        expect(authRedirect(staff, AppRoutes.workspace), isNull);
        expect(authRedirect(staff, AppRoutes.profile), isNull);
      });
    }
  });
}
