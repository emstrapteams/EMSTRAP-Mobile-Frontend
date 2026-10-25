import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/routing/auth_redirect.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_views.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/emergency_call_bar.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/active_emergency_store.dart';
import '../models/emergency_request.dart';
import '../models/emergency_status.dart';
import '../providers/emergency_queries.dart';
import '../providers/emergency_tracking_controller.dart';
import 'widgets/ai_analysis_card.dart';
import 'widgets/emergency_widgets.dart';
import 'widgets/status_timeline.dart';

class EmergencyTrackingScreen extends ConsumerStatefulWidget {
  const EmergencyTrackingScreen({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<EmergencyTrackingScreen> createState() =>
      _EmergencyTrackingScreenState();
}

class _EmergencyTrackingScreenState
    extends ConsumerState<EmergencyTrackingScreen> {
  late final AppLifecycleListener _lifecycle;

  EmergencyTrackingController get _controller =>
      ref.read(emergencyTrackingControllerProvider(widget.requestId).notifier);

  @override
  void initState() {
    super.initState();
    // The socket may have been suspended in the background; catch up on return.
    _lifecycle = AppLifecycleListener(onResume: () => _controller.refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _showMessage(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancel() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel this request?',
      message:
          'Any ambulance crew handling it will be told it is no longer needed.',
      confirmLabel: 'Cancel request',
      cancelLabel: 'Keep request',
      destructive: true,
    );
    if (!confirmed) return;
    _showMessage(await _controller.cancel());
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final error = await _controller.addEvidence(source);
    _showMessage(error ?? 'Photo added to your request.');
  }

  void _goHome() {
    ref.invalidate(activeEmergencyIdProvider);
    ref.invalidate(myEmergenciesProvider);
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      emergencyTrackingControllerProvider(widget.requestId),
    );
    final request = state.request;

    final Widget body;
    if (request == null && state.loadError != null) {
      final error = state.loadError!;
      body = ErrorView(
        title: error.kind == ApiErrorKind.notFound
            ? 'Request not found'
            : "Couldn't load your request",
        message: error.message,
        onRetry: error.kind == ApiErrorKind.notFound
            ? null
            : _controller.refresh,
      );
    } else if (request == null) {
      body = const LoadingView(message: 'Loading your request…');
    } else {
      body = RefreshIndicator(
        onRefresh: _controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: _content(context, state, request),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your emergency request'),
        leading: IconButton(
          tooltip: 'Home',
          icon: const Icon(Icons.home_outlined),
          onPressed: _goHome,
        ),
      ),
      body: SafeArea(child: body),
    );
  }

  List<Widget> _content(
    BuildContext context,
    TrackingState state,
    EmergencyRequest request,
  ) {
    const gap = SizedBox(height: AppSpacing.md);
    final terminal = request.status.isTerminal;
    final signedIn = ref.watch(authControllerProvider) is AuthSignedIn;

    return [
      if (!terminal) ...[_LiveIndicator(connected: state.liveConnected), gap],
      if (state.loadError != null) ...[
        const InlineMessage(
          tone: InlineMessageTone.warning,
          message:
              "Couldn't refresh just now. Showing the last update; pull down to try again.",
        ),
        gap,
      ],
      if (request.duplicateDetected && !terminal) ...[
        const InlineMessage(
          tone: InlineMessageTone.warning,
          title: 'Marked as a possible duplicate',
          message:
              'EMSTRAP thinks this matches a recent report, so it was not sent to ambulance crews. '
              'If this is a different emergency, call an ambulance directly.',
        ),
        gap,
      ],
      _StatusCard(request: request),
      gap,
      if (request.status != EmergencyStatus.cancelled &&
          request.status != EmergencyStatus.unknown) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: StatusTimeline(current: request.status),
          ),
        ),
        gap,
      ],
      if (request.ambulance != null) ...[
        _AmbulanceCard(request: request, state: state),
        gap,
      ],
      if (request.hospital != null) ...[
        _HospitalCard(hospital: request.hospital!),
        gap,
      ],
      if (state.sharingLocation) ...[
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.share_location,
              color: AppColors.brandBlue,
            ),
            title: const Text('Sharing your live location'),
            subtitle: const Text(
              'With the ambulance crew, until they reach you.',
            ),
            trailing: TextButton(
              onPressed: _controller.stopSharingLocation,
              child: const Text('Stop'),
            ),
          ),
        ),
        gap,
      ],
      if (request.aiAnalysis != null) ...[
        AiAnalysisCard(analysis: request.aiAnalysis!),
        gap,
      ],
      if (!terminal) ...[
        AppButton(
          label: request.evidenceCount > 0
              ? 'Add another photo (${request.evidenceCount} added)'
              : 'Add a photo',
          icon: Icons.add_a_photo_outlined,
          variant: AppButtonVariant.secondary,
          isLoading: state.uploadingEvidence,
          loadingLabel: 'Uploading photo…',
          onPressed: _addPhoto,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Cancel request',
          icon: Icons.cancel_outlined,
          variant: AppButtonVariant.secondary,
          isLoading: state.cancelling,
          loadingLabel: 'Cancelling…',
          onPressed: _cancel,
        ),
        if (!signedIn) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            "You're not logged in, so this request is only saved on this phone.",
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ] else
        AppButton(label: 'Back to home', onPressed: _goHome),
      const SizedBox(height: AppSpacing.lg),
      const EmergencyCallBar(),
    ];
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    if (connected) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(
          label: 'Live updates on',
          tone: StatusTone.success,
          icon: Icons.wifi_tethering,
        ),
      );
    }
    return const InlineMessage(
      tone: InlineMessageTone.warning,
      title: 'Live updates paused',
      message: 'Reconnecting… Meanwhile we check for updates every 30 seconds.',
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.request});

  final EmergencyRequest request;

  @override
  Widget build(BuildContext context) {
    final description = switch (request.status) {
      EmergencyStatus.pending =>
        'EMSTRAP has received your request. Waiting for an ambulance crew to accept it.',
      EmergencyStatus.ambulanceAccepted =>
        'An ambulance crew has accepted your request and is on the way.',
      EmergencyStatus.arrivedAtLocation =>
        'The ambulance crew has reached your location.',
      EmergencyStatus.enRouteToHospital =>
        'You are on the way to the hospital.',
      EmergencyStatus.completed => 'This emergency has been completed.',
      EmergencyStatus.cancelled => 'This request was cancelled.',
      EmergencyStatus.unknown =>
        'EMSTRAP reported a status this app version does not recognise.',
    };
    final created = request.createdAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmergencyStatusChip(request: request),
            const SizedBox(height: AppSpacing.md),
            Text(description, style: Theme.of(context).textTheme.titleMedium),
            if (created != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _SentAt(
                created: created,
                showElapsed: request.status == EmergencyStatus.pending,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Sent at 10:42 · 3 min ago". The backend has no expiry, so the app shows
/// elapsed time instead of inventing a timeout.
class _SentAt extends StatefulWidget {
  const _SentAt({required this.created, required this.showElapsed});

  final DateTime created;
  final bool showElapsed;

  @override
  State<_SentAt> createState() => _SentAtState();
}

class _SentAtState extends State<_SentAt> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.showElapsed) {
      _ticker = Timer.periodic(
        const Duration(seconds: 30),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = DateTime.now().difference(widget.created).inMinutes;
    final elapsed = minutes < 1 ? 'just now' : '$minutes min ago';
    return Text(
      'Sent ${formatDateTime(widget.created)}${widget.showElapsed ? ' · $elapsed' : ''}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _AmbulanceCard extends StatelessWidget {
  const _AmbulanceCard({required this.request, required this.state});

  final EmergencyRequest request;
  final TrackingState state;

  @override
  Widget build(BuildContext context) {
    final ambulance = request.ambulance!;
    final ambulancePosition = state.ambulanceLive ?? ambulance.location;
    final patient = request.location;
    final distance = (ambulancePosition != null && patient != null)
        ? ambulancePosition.distanceTo(patient)
        : null;
    final showDistance =
        distance != null && request.status == EmergencyStatus.ambulanceAccepted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, color: AppColors.brandBlue),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Your ambulance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (ambulance.driverName != null)
              Text('Driver: ${ambulance.driverName}'),
            if (ambulance.vehicleNumber != null)
              Text('Vehicle: ${ambulance.vehicleNumber}'),
            if (showDistance) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'About ${formatDistance(distance)} away in a straight line'
                '${state.ambulanceLiveAt != null ? ' · updated ${formatTime(state.ambulanceLiveAt!)}' : ' · last reported position'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (ambulance.mobile != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Call the driver',
                icon: Icons.call,
                onPressed: () => dialNumber(context, ambulance.mobile!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HospitalCard extends StatelessWidget {
  const _HospitalCard({required this.hospital});

  final HospitalSummary hospital;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(
          Icons.local_hospital,
          color: AppColors.emergencyRed,
        ),
        title: Text(hospital.name ?? 'Hospital assigned'),
        subtitle: hospital.fullAddress == null
            ? null
            : Text(hospital.fullAddress!),
        trailing: hospital.mobile == null
            ? null
            : IconButton(
                tooltip: 'Call the hospital',
                icon: const Icon(Icons.call),
                onPressed: () => dialNumber(context, hospital.mobile!),
              ),
      ),
    );
  }
}
