import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/emergency_numbers.dart';
import '../../core/theme/app_tokens.dart';

/// Direct-dial fallback that stays available on every emergency screen,
/// whatever state the app or the backend is in.
class EmergencyCallBar extends StatelessWidget {
  const EmergencyCallBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          "Can't wait? Call directly",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: _CallButton(
                number: EmergencyNumbers.ambulance,
                label: 'Ambulance',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _CallButton(
                number: EmergencyNumbers.allEmergencies,
                label: 'Emergency',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => dialNumber(context, number),
      icon: const Icon(Icons.call, color: AppColors.emergencyRed),
      label: Text('$number · $label', semanticsLabel: 'Call $number, $label'),
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.textPrimary),
    );
  }
}

/// Opens the phone dialer. It never places the call itself.
Future<void> dialNumber(BuildContext context, String number) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await launchUrl(Uri(scheme: 'tel', path: number));
  if (!opened) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not open the dialer. Please call $number.'),
      ),
    );
  }
}
