import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/realtime_service.dart';
import '../data/active_emergency_store.dart';
import '../data/emergency_repository.dart';
import '../data/location_service.dart';
import '../data/photo_service.dart';
import '../models/emergency_request.dart';
import '../models/emergency_status.dart';

class TrackingState {
  const TrackingState({
    this.request,
    this.loadError,
    this.liveConnected = false,
    this.ambulanceLive,
    this.ambulanceLiveAt,
    this.sharingLocation = false,
    this.cancelling = false,
    this.uploadingEvidence = false,
  });

  final EmergencyRequest? request;
  final ApiException? loadError;

  /// Socket.IO is connected. When false, the screen says updates are paused
  /// and falls back to polling.
  final bool liveConnected;

  /// Latest ambulance position pushed over the socket, if any.
  final GeoPoint? ambulanceLive;
  final DateTime? ambulanceLiveAt;
  final bool sharingLocation;
  final bool cancelling;
  final bool uploadingEvidence;

  static const _keep = Object();

  TrackingState copyWith({
    Object? request = _keep,
    Object? loadError = _keep,
    bool? liveConnected,
    Object? ambulanceLive = _keep,
    Object? ambulanceLiveAt = _keep,
    bool? sharingLocation,
    bool? cancelling,
    bool? uploadingEvidence,
  }) {
    T pick<T>(Object? value, T current) =>
        identical(value, _keep) ? current : value as T;
    return TrackingState(
      request: pick(request, this.request),
      loadError: pick(loadError, this.loadError),
      liveConnected: liveConnected ?? this.liveConnected,
      ambulanceLive: pick(ambulanceLive, this.ambulanceLive),
      ambulanceLiveAt: pick(ambulanceLiveAt, this.ambulanceLiveAt),
      sharingLocation: sharingLocation ?? this.sharingLocation,
      cancelling: cancelling ?? this.cancelling,
      uploadingEvidence: uploadingEvidence ?? this.uploadingEvidence,
    );
  }
}

/// Follows one emergency. REST is the source of truth: socket events only
/// trigger a refetch (except live ambulance positions, which are shown as
/// they arrive). While the socket is down the record is polled instead.
class EmergencyTrackingController
    extends AutoDisposeFamilyNotifier<TrackingState, String> {
  static const pollInterval = Duration(seconds: 30);

  late String _id;
  late RealtimeService _realtime;
  late EmergencyRepository _repo;
  late ActiveEmergencyStore _store;
  late LocationService _location;
  late PhotoService _photos;

  final _subscriptions = <StreamSubscription<Object?>>[];
  StreamSubscription<GeoPoint>? _locationSub;
  Timer? _pollTimer;
  Timer? _debounce;
  int _fetchSeq = 0;
  bool _disposed = false;
  bool _sharingStoppedByUser = false;
  bool _startingShare = false;

  @override
  TrackingState build(String id) {
    _id = id;
    _realtime = ref.read(realtimeServiceProvider);
    _repo = ref.read(emergencyRepositoryProvider);
    _store = ref.read(activeEmergencyStoreProvider);
    _location = ref.read(locationServiceProvider);
    _photos = ref.read(photoServiceProvider);

    _subscriptions
      ..add(_realtime.events.listen(_onEvent))
      ..add(_realtime.connection.listen(_onConnection));
    _realtime.trackRequest(id);

    ref.onDispose(() {
      _disposed = true;
      for (final s in _subscriptions) {
        s.cancel();
      }
      _pollTimer?.cancel();
      _debounce?.cancel();
      _locationSub?.cancel();
      _realtime.untrackRequest(id);
    });

    Future.microtask(refresh);
    return TrackingState(liveConnected: _realtime.isConnected);
  }

  void _set(TrackingState next) {
    if (!_disposed) state = next;
  }

  Future<void> refresh() async {
    // Responses can arrive out of order; only the newest one is applied.
    final seq = ++_fetchSeq;
    try {
      final request = await _repo.fetch(_id);
      if (seq != _fetchSeq || _disposed) return;
      _set(state.copyWith(request: request, loadError: null));
      await _afterUpdate(request);
    } on ApiException catch (e) {
      if (seq != _fetchSeq) return;
      _set(state.copyWith(loadError: e));
      if (e.kind == ApiErrorKind.notFound) await _store.clearIfMatches(_id);
    }
  }

  void _onEvent(RealtimeEvent event) {
    final payload = event.payload;
    final eventRequestId = payload is Map
        ? payload['requestId']?.toString()
        : null;
    if (eventRequestId != null && eventRequestId != _id) return;

    if (event.name == EmergencySocketEvents.ambulanceLocation) {
      final point = GeoPoint.fromJson(payload);
      if (point != null) {
        _set(
          state.copyWith(ambulanceLive: point, ambulanceLiveAt: DateTime.now()),
        );
      }
      return;
    }
    // Several events (e.g. ambulance_assigned) carry no request id. This
    // socket only tracks this request, so any of them means "refetch".
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  void _onConnection(bool connected) {
    _set(state.copyWith(liveConnected: connected));
    // Catch up on anything missed while disconnected.
    if (connected) refresh();
    _updatePolling();
  }

  void _updatePolling() {
    final terminal = state.request?.status.isTerminal ?? false;
    final needsPolling = !state.liveConnected && !terminal;
    if (needsPolling) {
      _pollTimer ??= Timer.periodic(pollInterval, (_) => refresh());
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _afterUpdate(EmergencyRequest request) async {
    _updatePolling();
    if (request.status.isTerminal) {
      await _store.clearIfMatches(_id);
      _stopSharing();
      return;
    }
    // Like the web app, share the patient's position while the ambulance is
    // on its way, and stop once it has arrived.
    if (request.status == EmergencyStatus.ambulanceAccepted &&
        !_sharingStoppedByUser) {
      await _startSharing();
    } else if (request.status != EmergencyStatus.ambulanceAccepted) {
      _stopSharing();
    }
  }

  /// Only starts if location permission was already granted (it was asked
  /// for, in context, when the request was created). Never prompts here.
  Future<void> _startSharing() async {
    if (_locationSub != null || _startingShare || _disposed) return;
    _startingShare = true;
    final bool allowed;
    try {
      allowed = await _location.hasPermission();
    } finally {
      _startingShare = false;
    }
    // Re-check after the await: the status or the user's choice may have changed.
    final stillOnTheWay =
        state.request?.status == EmergencyStatus.ambulanceAccepted;
    if (!allowed || _disposed || _sharingStoppedByUser || !stillOnTheWay) {
      return;
    }
    _locationSub = _location.watch().listen(
      (p) => _realtime.emitIfConnected('update_user_location', {
        'requestId': _id,
        'latitude': p.latitude,
        'longitude': p.longitude,
      }),
      onError: (_) => _stopSharing(),
    );
    _set(state.copyWith(sharingLocation: true));
  }

  void _stopSharing() {
    _locationSub?.cancel();
    _locationSub = null;
    if (state.sharingLocation) _set(state.copyWith(sharingLocation: false));
  }

  void stopSharingLocation() {
    _sharingStoppedByUser = true;
    _stopSharing();
  }

  /// Returns an error message, or null on success.
  Future<String?> cancel() async {
    if (state.cancelling) return null;
    _set(state.copyWith(cancelling: true));
    try {
      await _repo.cancel(_id);
      await refresh();
      return null;
    } on ApiException catch (e) {
      // e.g. "Emergency already closed." — refresh to show the real state.
      await refresh();
      return e.message;
    } finally {
      _set(state.copyWith(cancelling: false));
    }
  }

  /// Returns null on success or cancel, otherwise a message to show.
  Future<String?> addEvidence(ImageSource source) async {
    if (state.uploadingEvidence) return null;
    final CapturedPhoto? photo;
    try {
      photo = await _photos.pick(source);
    } on PhotoTooLargeException {
      return 'That photo is too large. Please take a new one.';
    } on Exception {
      return "Couldn't open the camera or gallery.";
    }
    if (photo == null) return null;

    _set(state.copyWith(uploadingEvidence: true));
    try {
      await _repo.addEvidence(_id, photo.toDataUrl());
      await refresh();
      return null;
    } on ApiException catch (e) {
      return "The photo couldn't be uploaded. ${e.message}";
    } finally {
      _set(state.copyWith(uploadingEvidence: false));
    }
  }
}

final emergencyTrackingControllerProvider = NotifierProvider.autoDispose
    .family<EmergencyTrackingController, TrackingState, String>(
      EmergencyTrackingController.new,
    );
