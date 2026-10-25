import '../../features/auth/models/user_role.dart';
import '../../features/auth/providers/auth_controller.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const home = '/';
  static const login = '/login';
  static const register = '/register';
  static const checkEmail = '/register/check-email';
  static const newEmergency = '/emergency/new';
  static const profile = '/profile';

  /// Home for roles whose mobile tools aren't built yet.
  static const workspace = '/workspace';

  static String emergency(String id) => '/emergency/$id';
}

/// Decides where a navigation may go, given who is signed in.
///
/// This only shapes the UI: hiding a screen is not security. Every protected
/// action is still authorised by the backend.
String? authRedirect(AuthState auth, String location) {
  final isEmergencyRoute = location.startsWith('/emergency/');

  switch (auth) {
    case AuthRestoring() || AuthRestoreFailed():
      return location == AppRoutes.splash ? null : AppRoutes.splash;

    case AuthSignedOut():
      // Requesting and following an emergency never requires a login.
      const public = {
        AppRoutes.home,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.checkEmail,
      };
      if (public.contains(location) || isEmergencyRoute) return null;
      if (location == AppRoutes.splash) return AppRoutes.home;
      return AppRoutes.login;

    case AuthSignedIn(:final user) when user.role == UserRole.user:
      const allowed = {AppRoutes.home, AppRoutes.profile};
      if (allowed.contains(location) || isEmergencyRoute) return null;
      return AppRoutes.home;

    case AuthSignedIn():
      // Drivers, hospital, police and admin: their tools come in later
      // milestones. Until then they land on a role workspace.
      const allowed = {AppRoutes.workspace, AppRoutes.profile};
      return allowed.contains(location) ? null : AppRoutes.workspace;
  }
}

/// True when the signed-in account changed: signed in ↔ signed out, or a
/// different account. Restoring / retrying a session is not a change.
bool identityChanged(AuthState previous, AuthState next) {
  return switch ((previous, next)) {
    (AuthSignedIn(user: final a), AuthSignedIn(user: final b)) => a.id != b.id,
    (AuthSignedIn(), AuthSignedOut()) ||
    (AuthSignedOut(), AuthSignedIn()) => true,
    _ => false,
  };
}
