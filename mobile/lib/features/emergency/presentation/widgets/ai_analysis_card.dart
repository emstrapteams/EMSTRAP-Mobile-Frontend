import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/status_chip.dart';
import '../../models/emergency_request.dart';

/// Shows the backend's AI image analysis, always labelled as automated
/// guidance. Never presented as a diagnosis or a dispatch decision.
class AiAnalysisCard extends StatelessWidget {
  const AiAnalysisCard({
    super.key,
    required this.analysis,
    this.lowConfidence = false,
  });

  final AiAnalysis analysis;

  /// The backend's `warningRequired` (confidence below 60%).
  final bool lowConfidence;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  color: AppColors.brandBlue,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('AI photo check', style: text.titleMedium),
                ),
                const StatusChip(
                  label: 'AI-generated',
                  tone: StatusTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _row(context, 'Looks like', _humanise(analysis.predictedClass)),
            _row(context, 'Confidence', analysis.confidencePercent),
            if (analysis.severity != null)
              _row(
                context,
                'Suggested severity',
                _humanise(analysis.severity!),
              ),
            if (lowConfidence) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The AI is not confident about this photo.',
                style: text.bodyMedium?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Automated guidance only. It is not a medical assessment and does not decide whether help is sent.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );

  /// `non_emergency` / `HIGH` → `Non emergency` / `High`.
  static String _humanise(String raw) {
    final words = raw.replaceAll('_', ' ').trim().toLowerCase();
    return words.isEmpty
        ? raw
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }
}
