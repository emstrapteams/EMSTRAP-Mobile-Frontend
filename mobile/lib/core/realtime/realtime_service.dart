import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../network/api_client.dart';

/// One event received from the backend's Socket.IO server.
class RealtimeEvent {
  const RealtimeEvent(this.name, this.payload);

  final String name;
  final Object? payload;
}

/// Server → client events for a tracked emergency (room `request_<id>`).
/// Verified against the local backend on 2026-10-24.
abstract final class EmergencySocketEvents {
  static const ambulanceAssigned = 'ambulance_assigned';
  static const emergencyUpdated = 'emergency_updated';
  static const driverArrived = 'driver_arrived';
  static const hospitalAssigned = 'hospital_assigned';
  static const ambulanceLocation = 'ambulance_location';
  static const tripCompleted = 'trip_completed';
  static const emergencyCancelled = 'emergency_cancelled';

  static const all = [
    ambulanceAssigned,
    emergencyUpdated,
    driverArrived,
    hospitalAssigned,
    ambulanceLocation,
    tripCompleted,
    emergencyCancelled,
  ];
}

/// Owns the app's single Socket.IO connection.
///
/// The connection opens lazily when the first request is tracked and closes
/// when nothing is tracked. Rooms are re-joined on every (re)connect, because
/// the server forgets room membership when a socket drops. Events are only
/// signals: listeners refetch the record over REST, which stays authoritative.
class RealtimeService {
  RealtimeService(this._baseUrl);

  final String _baseUrl;
  io.Socket? _socket;
  final Set<String> _trackedRequests = {};
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  bool _connected = false;

  Stream<RealtimeEvent> get events => _events.stream;

  /// Emits `true` on every (re)connect and `false` on every disconnect.
  Stream<bool> get connection => _connection.stream;

  bool get isConnected => _connected;

  void trackRequest(String requestId) {
    _trackedRequests.add(requestId);
    final socket = _ensureSocket();
    if (socket.connected) _joinRequestRoom(socket, requestId);
  }

  /// The server has no "leave" event; disconnecting is the only way to leave
  /// a room, so the socket closes once nothing is tracked.
  void untrackRequest(String requestId) {
    _trackedRequests.remove(requestId);
    if (_trackedRequests.isEmpty) _closeSocket();
  }

  /// Sends an event only when connected; location updates are not queued
  /// because stale positions are worse than none.
  void emitIfConnected(String event, Map<String, Object?> data) {
    final socket = _socket;
    if (socket != null && socket.connected) socket.emit(event, data);
  }

  io.Socket _ensureSocket() {
    final existing = _socket;
    if (existing != null) return existing;

    final socket = io.io(
      _baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .build(),
    );
    socket.onConnect((_) {
      _setConnected(true);
      for (final id in _trackedRequests) {
        _joinRequestRoom(socket, id);
      }
    });
    socket.onDisconnect((_) => _setConnected(false));
    socket.onConnectError((_) => _setConnected(false));
    for (final name in EmergencySocketEvents.all) {
      socket.on(name, (data) => _events.add(RealtimeEvent(name, data)));
    }
    socket.connect();
    return _socket = socket;
  }

  void _joinRequestRoom(io.Socket socket, String requestId) {
    socket.emit('track_request', {'requestId': requestId});
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (kDebugMode) {
      debugPrint('[socket] ${value ? 'connected' : 'disconnected'}');
    }
    _connection.add(value);
  }

  void _closeSocket() {
    _socket?.dispose();
    _socket = null;
    _setConnected(false);
  }

  void dispose() {
    _closeSocket();
    _events.close();
    _connection.close();
  }
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService(ref.watch(appConfigProvider).apiBaseUrl);
  ref.onDispose(service.dispose);
  return service;
});
