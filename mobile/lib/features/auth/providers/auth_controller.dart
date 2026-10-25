import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../../emergency/data/active_emergency_store.dart';
import '../data/auth_repository.dart';
import '../models/app_user.dart';
import '../models/registration.dart';

sealed class AuthState {
  const AuthState();
}

/// Restoring the saved session on startup.
class AuthRestoring extends AuthState {
  const AuthRestoring();
}

/// The saved session could not be checked (offline, server down). The token
/// is kept so a retry can still succeed.
class AuthRestoreFailed extends AuthState {
  const AuthRestoreFailed(this.error);

  final ApiException error;
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.notice});

  /// Shown on the login screen, e.g. after the session expired.
  final String? notice;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);

  final AppUser user;
}

/// The single source of truth for "who is signed in". The role always comes
/// from the backend (login response or `/auth/me`), never from local storage.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final sub = ref
        .watch(sessionEventsProvider)
        .expired
        .listen((_) => _onSessionExpired());
    ref.onDispose(sub.cancel);
    Future.microtask(restore);
    return const AuthRestoring();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> restore() async {
    state = const AuthRestoring();
    try {
      final user = await _repo.restoreSession();
      state = user == null ? const AuthSignedOut() : AuthSignedIn(user);
    } on ApiException catch (e) {
      state = AuthRestoreFailed(e);
    }
  }

  /// Throws [ApiException] so the login form can show the server's message
  /// (e.g. "Please verify your email to login").
  Future<void> login({required String email, required String password}) async {
    final user = await _repo.login(email: email, password: password);
    state = AuthSignedIn(user);
  }

  Future<void> register(Registration registration) =>
      _repo.register(registration);

  Future<void> logout() async {
    await _repo.logout();
    await ref.read(activeEmergencyStoreProvider).clear();
    state = const AuthSignedOut();
  }

  void _onSessionExpired() {
    if (state is! AuthSignedIn) return;
    unawaited(ref.read(tokenStorageProvider).clear());
    state = const AuthSignedOut(
      notice: 'Your session has expired. Please log in again.',
    );
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
