import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../providers/auth_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'You can still request an ambulance without logging in.',
      confirmLabel: 'Log out',
      cancelLabel: 'Stay logged in',
    );
    if (!confirmed || !mounted) return;
    setState(() => _loggingOut = true);
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return const Scaffold(body: SizedBox.shrink());
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Card(
              child: Column(
                children: [
                  _row(Icons.person_outline, 'Name', user.name),
                  _row(Icons.email_outlined, 'Email', user.email),
                  _row(Icons.badge_outlined, 'Account type', user.role.label),
                  if (user.mobile != null)
                    _row(Icons.phone_outlined, 'Mobile', user.mobile!),
                  if (user.city != null)
                    _row(Icons.location_city_outlined, 'City', user.city!),
                  if (user.vehicleNumber != null)
                    _row(
                      Icons.local_shipping_outlined,
                      'Vehicle',
                      user.vehicleNumber!,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Log out',
              icon: Icons.logout,
              loadingLabel: 'Logging out…',
              isLoading: _loggingOut,
              variant: AppButtonVariant.secondary,
              onPressed: _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => ListTile(
    leading: Icon(icon),
    title: Text(label, style: Theme.of(context).textTheme.bodySmall),
    subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
  );
}
