import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/auth_redirect.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/async_views.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../auth/models/user_role.dart';
import '../../auth/providers/auth_controller.dart';

/// Landing screen for drivers, hospital, police and admin accounts. Their
/// mobile tools are later milestones, so this says so plainly instead of
/// showing placeholder data.
class RoleWorkspaceScreen extends ConsumerWidget {
  const RoleWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return const Scaffold(body: SizedBox.shrink());
    final user = auth.user;
    final known = user.role != UserRole.unknown;

    return Scaffold(
      appBar: AppBar(
        title: const BrandLogo(height: 36),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              'Hi ${user.name}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Signed in as ${known ? user.role.label : user.rawRole}'),
            const SizedBox(height: AppSpacing.lg),
            InlineMessage(
              tone: InlineMessageTone.info,
              title: known
                  ? '${user.role.label} tools are coming to the app'
                  : 'Account type not supported yet',
              message: known
                  ? 'This part of the mobile app is still being built. Until then, '
                        'please use the EMSTRAP web dashboard for your work.'
                  : 'This account type ("${user.rawRole}") is not supported in the mobile app yet.',
            ),
          ],
        ),
      ),
    );
  }
}
