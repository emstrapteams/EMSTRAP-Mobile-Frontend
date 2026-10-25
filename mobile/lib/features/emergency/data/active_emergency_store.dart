import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_store.dart';

/// Remembers the id of the emergency the user is following, so it can be
/// reopened after the app restarts. Without a login this is the only way back
/// to an anonymous request. Only the id is stored; the status is always
/// fetched again from the server.
class ActiveEmergencyStore {
  ActiveEmergencyStore(this._store);

  static const _key = 'active_emergency_id';

  final SecureStore _store;

  Future<String?> read() => _store.read(_key);

  Future<void> save(String id) => _store.write(_key, id);

  Future<void> clear() => _store.delete(_key);

  Future<void> clearIfMatches(String id) async {
    if (await read() == id) await clear();
  }
}

final activeEmergencyStoreProvider = Provider<ActiveEmergencyStore>(
  (ref) => ActiveEmergencyStore(ref.watch(secureStoreProvider)),
);

/// The saved active emergency id, if any. Invalidate after save/clear.
final activeEmergencyIdProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(activeEmergencyStoreProvider).read(),
);
