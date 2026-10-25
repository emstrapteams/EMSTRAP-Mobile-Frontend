import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/routing/auth_redirect.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_views.dart';
import '../../../shared/widgets/emergency_call_bar.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/active_emergency_store.dart';
import '../data/location_service.dart';
import '../providers/emergency_flow_controller.dart';
import '../providers/emergency_queries.dart';
import 'widgets/ai_analysis_card.dart';
import 'widgets/emergency_widgets.dart';

class EmergencyFlowScreen extends ConsumerWidget {
  const EmergencyFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(emergencyFlowControllerProvider);
    final controller = ref.read(emergencyFlowControllerProvider.notifier);

    ref.listen(emergencyFlowControllerProvider, (previous, next) {
      final created = next.created;
      if (next.step == FlowStep.submitted &&
          created != null &&
          previous?.step != FlowStep.submitted) {
        ref.invalidate(activeEmergencyIdProvider);
        ref.invalidate(myEmergenciesProvider);
        context.pushReplacement(AppRoutes.emergency(created.id));
      }
    });

    final body = switch (state.step) {
      FlowStep.locating => const _Locating(),
      FlowStep.needsLocation => _NeedsLocation(
        problem: state.locationProblem!,
        controller: controller,
      ),
      FlowStep.aiWarning => _AiWarning(state: state, controller: controller),
      FlowStep.photoUploadFailed => _PhotoUploadFailed(
        state: state,
        controller: controller,
      ),
      FlowStep.outcomeUnknown => _OutcomeUnknown(
        state: state,
        controller: controller,
      ),
      FlowStep.ready ||
      FlowStep.sending ||
      FlowStep.failed ||
      FlowStep.submitted => _Review(state: state, controller: controller),
    };

    final sending = state.step == FlowStep.sending;
    return PopScope(
      // Leaving mid-send would hide the outcome; the request still completes
      // and is saved, but the user should see it.
      canPop: !sending,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Request an ambulance'),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: sending
                ? null
                : () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.home),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: body,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: EmergencyCallBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Locating extends StatelessWidget {
  const _Locating();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.my_location, size: 56, color: AppColors.brandBlue),
          const SizedBox(height: AppSpacing.lg),
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Finding your location…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Ambulance crews need your location to reach you. It is only used for this request.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NeedsLocation extends ConsumerWidget {
  const _NeedsLocation({required this.problem, required this.controller});

  final LocationProblem problem;
  final EmergencyFlowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.read(locationServiceProvider);
    final (title, message, actionLabel, action) = switch (problem) {
      LocationProblem.serviceDisabled => (
        'Location is turned off',
        'Turn on location so ambulance crews can find you, then try again.',
        'Turn on location',
        location.openLocationSettings,
      ),
      LocationProblem.permissionDenied => (
        'Location permission needed',
        'EMSTRAP cannot send an ambulance without your location. Allow location access to continue.',
        'Allow location',
        null,
      ),
      LocationProblem.permissionDeniedForever => (
        'Location access is blocked',
        'Location access was denied for EMSTRAP. Allow it in the app settings, then try again.',
        'Open app settings',
        location.openAppSettings,
      ),
      LocationProblem.timeout => (
        "Couldn't get a GPS fix",
        'Move closer to a window or outdoors, then try again.',
        null,
        null,
      ),
      LocationProblem.unavailable => (
        "Couldn't get your location",
        'Something went wrong while reading your location. Please try again.',
        null,
        null,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        const Icon(
          Icons.location_off_outlined,
          size: 56,
          color: AppColors.emergencyRed,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        if (actionLabel != null && action != null) ...[
          AppButton(label: actionLabel, onPressed: () => action()),
          const SizedBox(height: AppSpacing.sm),
        ],
        AppButton(
          label: actionLabel != null && action == null
              ? actionLabel
              : 'Try again',
          icon: Icons.refresh,
          variant: action != null
              ? AppButtonVariant.secondary
              : AppButtonVariant.primary,
          onPressed: controller.locate,
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          "If you can't share your location, call an ambulance directly using the buttons below.",
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Review extends ConsumerWidget {
  const _Review({required this.state, required this.controller});

  final EmergencyFlowState state;
  final EmergencyFlowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fix = state.fix!;
    final sending =
        state.step == FlowStep.sending || state.step == FlowStep.submitted;
    final signedIn = ref.watch(authControllerProvider) is AuthSignedIn;
    final loadingLabel = switch (state.phase) {
      SendingPhase.uploadingPhoto => 'Uploading photo…',
      SendingPhase.confirming => 'Checking your request was received…',
      _ => 'Sending request…',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.step == FlowStep.failed && state.error != null) ...[
          InlineMessage(
            title: 'Your request was not sent',
            message: state.error!.message,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _LocationCard(fix: fix),
        const SizedBox(height: AppSpacing.md),
        _PhotoCard(state: state, controller: controller, enabled: !sending),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: state.step == FlowStep.failed
              ? 'Try sending again'
              : 'Send emergency request',
          icon: Icons.emergency,
          variant: AppButtonVariant.emergency,
          isLoading: sending,
          loadingLabel: loadingLabel,
          onPressed: controller.send,
        ),
        if (!signedIn) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            "You're not logged in. Your request is still sent; you'll follow it on this phone.",
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.fix});

  final LocationFix fix;

  @override
  Widget build(BuildContext context) {
    final p = fix.point;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.my_location, color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Your location',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
            ),
            Text(
              'Accurate to about ${formatDistance(fix.accuracyMeters)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (fix.isLastKnown) ...[
              const SizedBox(height: AppSpacing.sm),
              InlineMessage(
                tone: InlineMessageTone.warning,
                message:
                    'No fresh GPS fix, so this is your last known position from '
                    '${formatTime(fix.capturedAt)}. It may be out of date.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.state,
    required this.controller,
    required this.enabled,
  });

  final EmergencyFlowState state;
  final EmergencyFlowController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final photo = state.photo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Photo (optional)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'A photo helps responders understand the situation. Only take one if it is safe.',
            ),
            const SizedBox(height: AppSpacing.md),
            if (photo != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.memory(
                  photo.bytes,
                  height: 180,
                  fit: BoxFit.cover,
                  semanticLabel: 'Photo to attach to the request',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: enabled ? controller.removePhoto : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove photo'),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled
                          ? () => controller.pickPhoto(ImageSource.camera)
                          : null,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled
                          ? () => controller.pickPhoto(ImageSource.gallery)
                          : null,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
            if (state.photoMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              InlineMessage(
                message: state.photoMessage!,
                tone: InlineMessageTone.warning,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiWarning extends StatelessWidget {
  const _AiWarning({required this.state, required this.controller});

  final EmergencyFlowState state;
  final EmergencyFlowController controller;

  @override
  Widget build(BuildContext context) {
    final analysis = state.precheck?.aiAnalysis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Check your photo', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          "The automatic photo check isn't sure what this photo shows. "
          'If you need help, send your request anyway: the photo check does not decide whether help is sent.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (analysis != null) ...[
          AiAnalysisCard(analysis: analysis, lowConfidence: true),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppButton(
          label: 'Send request anyway',
          icon: Icons.emergency,
          variant: AppButtonVariant.emergency,
          onPressed: controller.sendDespiteAiWarning,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Change photo',
          variant: AppButtonVariant.secondary,
          onPressed: controller.removePhoto,
        ),
      ],
    );
  }
}

class _PhotoUploadFailed extends StatelessWidget {
  const _PhotoUploadFailed({required this.state, required this.controller});

  final EmergencyFlowState state;
  final EmergencyFlowController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineMessage(
          title: "Your photo couldn't be uploaded",
          message:
              '${state.error?.message ?? ''} Your request has not been sent yet. '
              'You can send it without the photo.',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Send without photo',
          icon: Icons.emergency,
          variant: AppButtonVariant.emergency,
          onPressed: controller.sendWithoutPhoto,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Try uploading again',
          variant: AppButtonVariant.secondary,
          onPressed: controller.send,
        ),
        TextButton(
          onPressed: controller.backToReview,
          child: const Text('Back'),
        ),
      ],
    );
  }
}

class _OutcomeUnknown extends StatelessWidget {
  const _OutcomeUnknown({required this.state, required this.controller});

  final EmergencyFlowState state;
  final EmergencyFlowController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InlineMessage(
          tone: InlineMessageTone.warning,
          title: "We couldn't confirm your request",
          message:
              'The connection dropped while sending. Your request may or may not have '
              'reached EMSTRAP. Sending again could create a second request.',
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'If help is urgent, call an ambulance directly using the buttons below.',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Send again',
          icon: Icons.emergency,
          variant: AppButtonVariant.emergency,
          onPressed: controller.sendAgain,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: controller.backToReview,
          child: const Text('Back'),
        ),
      ],
    );
  }
}
