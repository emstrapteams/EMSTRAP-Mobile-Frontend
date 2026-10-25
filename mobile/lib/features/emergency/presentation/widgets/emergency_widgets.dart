import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/status_chip.dart';
import '../../models/emergency_request.dart';

/// The primary "request an ambulance" action. Large, red, labelled.
class EmergencyActionButton extends StatelessWidget {
  const EmergencyActionButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Request an ambulance',
      hint: 'Shares your location with nearby ambulance crews',
      // excludeSemantics also hides the InkWell's tap action, so the
      // action must be re-exposed here or screen readers can't activate it.
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: AppColors.emergencyRed,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        elevation: 3,
        shadowColor: AppColors.emergencyRed.withValues(alpha: 0.4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: const Padding(
            padding: EdgeInsets.symmetric(
              vertical: 28,
              horizontal: AppSpacing.lg,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emergency, color: Colors.white, size: 36),
                SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(
                    'Request ambulance',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmergencyStatusChip extends StatelessWidget {
  const EmergencyStatusChip({super.key, required this.request});

  final EmergencyRequest request;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: request.statusLabel,
    tone: request.status.tone,
    icon: request.status.icon,
  );
}

/// Banner linking back to an emergency that is still in progress.
class ActiveEmergencyBanner extends StatelessWidget {
  const ActiveEmergencyBanner({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.navy,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.radar, color: Colors.white),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'You have an emergency request in progress. Tap to follow it.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class EmergencyHistoryTile extends StatelessWidget {
  const EmergencyHistoryTile({
    super.key,
    required this.request,
    required this.onTap,
  });

  final EmergencyRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final created = request.createdAt;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      created == null
                          ? 'Emergency request'
                          : formatDateTime(created),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    EmergencyStatusChip(request: request),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

String formatDateTime(DateTime value) =>
    DateFormat('d MMM yyyy, h:mm a').format(value);

String formatTime(DateTime value) => DateFormat('h:mm:ss a').format(value);

String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
