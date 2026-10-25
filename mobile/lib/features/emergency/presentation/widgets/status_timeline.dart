import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../models/emergency_status.dart';

/// Vertical progress through the server-reported status. Steps are only
/// marked done when the backend has reached them; nothing is predicted.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.current});

  final EmergencyStatus current;

  @override
  Widget build(BuildContext context) {
    final steps = EmergencyStatus.progression;
    final currentIndex = steps.indexOf(current);

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            status: steps[i],
            state: i < currentIndex
                ? _StepState.done
                : i == currentIndex
                ? (current.isTerminal ? _StepState.done : _StepState.current)
                : _StepState.upcoming,
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

enum _StepState { done, current, upcoming }

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.status,
    required this.state,
    required this.isLast,
  });

  final EmergencyStatus status;
  final _StepState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StepState.done => AppColors.success,
      _StepState.current => AppColors.brandBlue,
      _StepState.upcoming => AppColors.border,
    };
    final icon = switch (state) {
      _StepState.done => Icons.check_circle,
      _StepState.current => Icons.radio_button_checked,
      _StepState.upcoming => Icons.radio_button_unchecked,
    };
    final stateLabel = switch (state) {
      _StepState.done => 'done',
      _StepState.current => 'current step',
      _StepState.upcoming => 'not yet',
    };

    return Semantics(
      label: '${status.label}, $stateLabel',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              children: [
                Icon(icon, color: color, size: 22),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: state == _StepState.done
                          ? AppColors.success
                          : AppColors.border,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  status.label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: state == _StepState.current
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: state == _StepState.upcoming
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
