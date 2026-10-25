import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/emergency_call_bar.dart';
import '../providers/auth_controller.dart';

/// Shown while the saved session is checked, or when that check failed.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final failure = auth is AuthRestoreFailed ? auth : null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              const BrandLogo(height: 96),
              const SizedBox(height: AppSpacing.xl),
              if (failure == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Connecting to EMSTRAP…',
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Text(
                  "Can't reach EMSTRAP",
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(failure.error.message, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Try again',
                  icon: Icons.refresh,
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).restore(),
                ),
              ],
              const Spacer(),
              const EmergencyCallBar(),
            ],
          ),
        ),
      ),
    );
  }
}
