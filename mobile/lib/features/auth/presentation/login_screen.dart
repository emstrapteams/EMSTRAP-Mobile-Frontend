import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/routing/auth_redirect.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_views.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../models/registration.dart';
import '../providers/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(email: _email.text, password: _password.text);
      // The router redirects to the role's home once the state changes.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final notice = auth is AuthSignedOut ? auth.notice : null;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandLogo(height: 64),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Log in',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Use your EMSTRAP account. The same account works on the web.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (notice != null && _error == null) ...[
                    InlineMessage(
                      message: notice,
                      tone: InlineMessageTone.info,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (_error != null) ...[
                    InlineMessage(message: _error!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.email,
                    enabled: !_submitting,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _password,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: AuthValidators.loginPassword,
                    enabled: !_submitting,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Log in',
                    loadingLabel: 'Logging in…',
                    isLoading: _submitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => context.go(AppRoutes.register),
                    child: const Text('Create an account'),
                  ),
                  const Divider(height: AppSpacing.xl),
                  AppButton(
                    label: 'Request an ambulance without logging in',
                    icon: Icons.emergency,
                    variant: AppButtonVariant.secondary,
                    onPressed: _submitting
                        ? null
                        : () => context.go(AppRoutes.newEmergency),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
