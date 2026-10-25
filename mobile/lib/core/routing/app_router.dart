import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/check_email_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/profile_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/emergency/presentation/emergency_flow_screen.dart';
import '../../features/emergency/presentation/emergency_tracking_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/workspace/presentation/role_workspace_screen.dart';
import 'auth_redirect.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-runs redirects whenever the auth state changes (login, logout, expiry).
  final authState = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.onDispose(authState.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: authState,
    redirect: (context, state) =>
        authRedirect(authState.value, state.matchedLocation),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.checkEmail,
        builder: (_, state) =>
            CheckEmailScreen(email: state.uri.queryParameters['email']),
      ),
      GoRoute(
        path: AppRoutes.newEmergency,
        builder: (_, _) => const EmergencyFlowScreen(),
      ),
      GoRoute(
        path: '/emergency/:id',
        builder: (_, state) =>
            EmergencyTrackingScreen(requestId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.workspace,
        builder: (_, _) => const RoleWorkspaceScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);

  ref.listen(authControllerProvider, (previous, next) {
    authState.value = next;
    // Redirects only see the base location of pushed screens, so a screen
    // pushed by the previous identity (e.g. Profile) would survive a logout.
    // Reset the stack whenever the identity changes.
    if (previous != null && identityChanged(previous, next)) {
      router.go(
        next is AuthSignedOut && next.notice != null
            ? AppRoutes.login
            : AppRoutes.home,
      );
    }
  });
  return router;
});
