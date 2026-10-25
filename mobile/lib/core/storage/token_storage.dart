import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_store.dart';

/// Holds the backend JWT. Kept in memory after the first read so the
/// request interceptor doesn't hit the Keystore on every call.
class TokenStorage {
  TokenStorage(this._store);

  static const _key = 'auth_token';

  final SecureStore _store;
  String? _cached;
  bool _loaded = false;

  Future<String?> read() async {
    if (!_loaded) {
      _cached = await _store.read(_key);
      _loaded = true;
    }
    return _cached;
  }

  Future<void> write(String token) async {
    await _store.write(_key, token);
    _cached = token;
    _loaded = true;
  }

  Future<void> clear() async {
    await _store.delete(_key);
    _cached = null;
    _loaded = true;
  }
}

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(ref.watch(secureStoreProvider)),
);
