import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/auth_redirect.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';

/// After registration the backend emails a verification link (to the web
/// app). Login is refused until the address is verified.
class CheckEmailScreen extends StatelessWidget {
  const CheckEmailScreen({super.key, this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(
                Icons.mark_email_read_outlined,
                size: 72,
                color: AppColors.brandBlue,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Verify your email',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'We sent a verification link to ${email ?? 'your email address'}. '
                'Open it, then come back and log in. The link expires in 24 hours.',
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              AppButton(
                label: 'Go to log in',
                onPressed: () => context.go(AppRoutes.login),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
