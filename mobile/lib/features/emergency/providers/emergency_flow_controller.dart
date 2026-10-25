import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/active_emergency_store.dart';
import '../data/emergency_repository.dart';
import '../data/location_service.dart';
import '../data/photo_service.dart';
import '../models/emergency_request.dart';
import '../models/precheck_result.dart';

enum FlowStep {
  locating,
  needsLocation,

  /// Location acquired; the user can add a photo and send.
  ready,
  sending,

  /// The AI check is unsure about the photo; the user decides whether to send.
  aiWarning,
  photoUploadFailed,

  /// The request may or may not have been created (timeout / dropped
  /// connection) and could not be confirmed. Never resent automatically.
  outcomeUnknown,
  failed,
  submitted,
}

enum SendingPhase { uploadingPhoto, creatingRequest, confirming }

typedef _Deps = ({
  EmergencyRepository repo,
  ActiveEmergencyStore store,
  bool signedIn,
});

class EmergencyFlowState {
  const EmergencyFlowState({
    required this.step,
    this.fix,
    this.locationProblem,
    this.photo,
    this.photoMessage,
    this.precheck,
    this.phase,
    this.error,
    this.created,
  });

  final FlowStep step;
  final LocationFix? fix;
  final LocationProblem? locationProblem;
  final CapturedPhoto? photo;
  final String? photoMessage;

  /// Set once the photo has been uploaded, so a retry never re-uploads it.
  final PrecheckResult? precheck;
  final SendingPhase? phase;
  final ApiException? error;
  final EmergencyRequest? created;

  static const _keep = Object();

  EmergencyFlowState copyWith({
    FlowStep? step,
    Object? fix = _keep,
    Object? locationProblem = _keep,
    Object? photo = _keep,
    Object? photoMessage = _keep,
    Object? precheck = _keep,
    Object? phase = _keep,
    Object? error = _keep,
    Object? created = _keep,
  }) {
    T pick<T>(Object? value, T current) =>
        identical(value, _keep) ? current : value as T;
    return EmergencyFlowState(
      step: step ?? this.step,
      fix: pick(fix, this.fix),
      locationProblem: pick(locationProblem, this.locationProblem),
      photo: pick(photo, this.photo),
      photoMessage: pick(photoMessage, this.photoMessage),
      precheck: pick(precheck, this.precheck),
      phase: pick(phase, this.phase),
      error: pick(error, this.error),
      created: pick(created, this.created),
    );
  }
}

/// Drives "request an ambulance": location → optional photo (+ AI check) →
/// create → hand over to tracking. Success is only reported once the backend
/// has returned the created request.
class EmergencyFlowController extends AutoDisposeNotifier<EmergencyFlowState> {
  /// Synchronous guard: a second tap arriving before the first request
  /// finishes is ignored, even before the UI has rebuilt.
  bool _busy = false;
  bool _disposed = false;

  /// Device and server clocks can disagree; this window decides which of the
  /// user's recent requests counts as "the one we just sent".
  static const reconcileWindow = Duration(minutes: 5);

  @override
  EmergencyFlowState build() {
    ref.onDispose(() => _disposed = true);
    Future.microtask(locate);
    return const EmergencyFlowState(step: FlowStep.locating);
  }

  void _set(EmergencyFlowState next) {
    if (!_disposed) state = next;
  }

  Future<void> locate() async {
    final location = ref.read(locationServiceProvider);
    _set(state.copyWith(step: FlowStep.locating, locationProblem: null));
    final result = await location.currentFix();
    _set(switch (result) {
      LocationFix() => state.copyWith(step: FlowStep.ready, fix: result),
      LocationFailure(:final problem) => state.copyWith(
        step: FlowStep.needsLocation,
        locationProblem: problem,
      ),
    });
  }

  Future<void> pickPhoto(ImageSource source) async {
    if (_busy) return;
    final photos = ref.read(photoServiceProvider);
    try {
      final photo = await photos.pick(source);
      if (photo == null) return;
      _set(state.copyWith(photo: photo, precheck: null, photoMessage: null));
    } on PhotoTooLargeException {
      _set(
        state.copyWith(
          photoMessage: 'That photo is too large. Please take a new one.',
        ),
      );
    } on Exception {
      _set(
        state.copyWith(
          photoMessage:
              "Couldn't open the camera or gallery. You can send without a photo.",
        ),
      );
    }
  }

  void removePhoto() {
    if (_busy) return;
    _set(
      state.copyWith(
        step: FlowStep.ready,
        photo: null,
        precheck: null,
        photoMessage: null,
        error: null,
      ),
    );
  }

  void backToReview() {
    if (_busy) return;
    _set(state.copyWith(step: FlowStep.ready, error: null));
  }

  /// The main "Send" action from the review step.
  Future<void> send() => _guarded((deps) async {
    final fix = state.fix;
    if (fix == null) return;
    final photo = state.photo;

    if (photo != null && state.precheck == null) {
      _set(
        state.copyWith(
          step: FlowStep.sending,
          phase: SendingPhase.uploadingPhoto,
          error: null,
        ),
      );
      final PrecheckResult precheck;
      try {
        precheck = await deps.repo.precheck(
          imageDataUrl: photo.toDataUrl(),
          location: fix.point,
        );
      } on ApiException catch (e) {
        _set(state.copyWith(step: FlowStep.photoUploadFailed, error: e));
        return;
      }
      _set(state.copyWith(precheck: precheck));
      if (precheck.aiAvailable && precheck.warningRequired) {
        _set(state.copyWith(step: FlowStep.aiWarning));
        return;
      }
    }
    await _create(deps, fix, state.precheck?.secureImageUrl);
  });

  /// The user saw the AI warning and chose to send anyway.
  Future<void> sendDespiteAiWarning() => _guarded((deps) async {
    final fix = state.fix;
    if (fix == null) return;
    await _create(deps, fix, state.precheck?.secureImageUrl);
  });

  Future<void> sendWithoutPhoto() => _guarded((deps) async {
    final fix = state.fix;
    if (fix == null) return;
    _set(state.copyWith(photo: null, precheck: null));
    await _create(deps, fix, null);
  });

  /// Explicit user decision after [FlowStep.outcomeUnknown]; may duplicate.
  Future<void> sendAgain() => _guarded((deps) async {
    final fix = state.fix;
    if (fix == null) return;
    await _create(deps, fix, state.precheck?.secureImageUrl);
  });

  /// Runs one send action at a time. Dependencies are read up front because
  /// the screen (and this provider) may be closed while a request is in flight;
  /// the request still completes and is saved as the active emergency.
  Future<void> _guarded(Future<void> Function(_Deps deps) action) async {
    if (_busy) return;
    _busy = true;
    final deps = (
      repo: ref.read(emergencyRepositoryProvider),
      store: ref.read(activeEmergencyStoreProvider),
      signedIn: ref.read(authControllerProvider) is AuthSignedIn,
    );
    try {
      await action(deps);
    } finally {
      _busy = false;
    }
  }

  Future<void> _create(_Deps deps, LocationFix fix, String? imageUrl) async {
    final (:repo, :store, :signedIn) = deps;
    final startedAt = DateTime.now();

    _set(
      state.copyWith(
        step: FlowStep.sending,
        phase: SendingPhase.creatingRequest,
        error: null,
      ),
    );
    try {
      final created = await repo.create(
        location: fix.point,
        imageUrl: imageUrl,
      );
      await store.save(created.id);
      _set(state.copyWith(step: FlowStep.submitted, created: created));
    } on ApiException catch (e) {
      if (!e.mayHaveReachedServer) {
        _set(state.copyWith(step: FlowStep.failed, error: e));
        return;
      }
      // Anonymous requests can't be looked up, so only signed-in users can
      // be reconciled.
      if (signedIn) {
        _set(state.copyWith(phase: SendingPhase.confirming));
        final found = await _findJustCreated(repo, startedAt);
        if (found != null) {
          await store.save(found.id);
          _set(state.copyWith(step: FlowStep.submitted, created: found));
          return;
        }
      }
      _set(state.copyWith(step: FlowStep.outcomeUnknown, error: e));
    }
  }

  Future<EmergencyRequest?> _findJustCreated(
    EmergencyRepository repo,
    DateTime startedAt,
  ) async {
    try {
      final since = startedAt.subtract(reconcileWindow);
      final mine = await repo.listMine();
      return mine.firstWhereOrNull(
        (r) => !r.status.isTerminal && (r.createdAt?.isAfter(since) ?? false),
      );
    } on ApiException {
      return null;
    }
  }
}

final emergencyFlowControllerProvider =
    NotifierProvider.autoDispose<EmergencyFlowController, EmergencyFlowState>(
      EmergencyFlowController.new,
    );
