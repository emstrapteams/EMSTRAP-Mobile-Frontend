import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/auth_redirect.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_views.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/emergency_call_bar.dart';
import '../../auth/providers/auth_controller.dart';
import '../../emergency/data/active_emergency_store.dart';
import '../../emergency/presentation/widgets/emergency_widgets.dart';
import '../../emergency/providers/emergency_queries.dart';

/// Home for people who need help: signed-out visitors and `user` accounts.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthSignedIn ? auth.user : null;
    final signedIn = user != null;
    // The id saved on this phone (covers anonymous requests), else any
    // in-progress request in the signed-in user's server-side history.
    final activeId =
        ref.watch(activeEmergencyIdProvider).valueOrNull ??
        (signedIn
            ? ref
                  .watch(myEmergenciesProvider)
                  .valueOrNull
                  ?.firstWhereOrNull((r) => !r.status.isTerminal)
                  ?.id
            : null);

    Future<void> refresh() async {
      ref.invalidate(activeEmergencyIdProvider);
      if (signedIn) ref.invalidate(myEmergenciesProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: const BrandLogo(height: 36),
        actions: [
          if (signedIn)
            IconButton(
              tooltip: 'Profile',
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => context.push(AppRoutes.profile),
            )
          else
            TextButton(
              onPressed: () => context.go(AppRoutes.login),
              child: const Text('Log in'),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (activeId != null) ...[
                ActiveEmergencyBanner(
                  onOpen: () => context.push(AppRoutes.emergency(activeId)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                signedIn
                    ? 'Hi ${user.name.split(' ').first}, need an ambulance?'
                    : 'Need an ambulance?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Your location is shared with nearby ambulance crews when you send a request.',
              ),
              const SizedBox(height: AppSpacing.lg),
              EmergencyActionButton(
                onPressed: () => context.push(AppRoutes.newEmergency),
              ),
              const SizedBox(height: AppSpacing.md),
              const EmergencyCallBar(),
              const SizedBox(height: AppSpacing.xl),
              if (signedIn) const _History() else const _SignInPrompt(),
            ],
          ),
        ),
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(myEmergenciesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your requests', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        history.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => InlineMessage(
            title: "Couldn't load your requests",
            message: 'Pull down to try again.',
            tone: InlineMessageTone.warning,
          ),
          data: (items) => items.isEmpty
              ? const EmptyView(
                  title: 'No requests yet',
                  message: 'Emergency requests you send will appear here.',
                  icon: Icons.history,
                )
              : Column(
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: EmergencyHistoryTile(
                          request: item,
                          onTap: () =>
                              context.push(AppRoutes.emergency(item.id)),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Have an EMSTRAP account?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Log in to keep a history of your requests. You never need to log in to get help.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Log in',
              onPressed: () => context.go(AppRoutes.login),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Create an account',
              variant: AppButtonVariant.secondary,
              onPressed: () => context.go(AppRoutes.register),
            ),
          ],
        ),
      ),
    );
  }
}
