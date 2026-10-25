import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/emergency_repository.dart';
import '../models/emergency_request.dart';

/// The signed-in user's emergency history (`GET /api/emergency`).
final myEmergenciesProvider =
    FutureProvider.autoDispose<List<EmergencyRequest>>(
      (ref) => ref.watch(emergencyRepositoryProvider).listMine(),
    );
