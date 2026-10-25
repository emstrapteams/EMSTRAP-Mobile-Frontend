import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/routing/auth_redirect.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/async_views.dart';
import '../models/registration.dart';
import '../models/user_role.dart';
import '../providers/auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _vehicle = TextEditingController();
  UserRole _role = UserRole.user;
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _email,
      _mobile,
      _password,
      _city,
      _address,
      _vehicle,
    ]) {
      c.dispose();
    }
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
          .register(
            Registration(
              name: _name.text,
              email: _email.text,
              password: _password.text,
              mobile: _mobile.text,
              city: _city.text,
              address: _address.text,
              role: _role,
              vehicleNumber: _vehicle.text,
            ),
          );
      if (mounted) {
        context.go(
          Uri(
            path: AppRoutes.checkEmail,
            queryParameters: {'email': _email.text.trim()},
          ).toString(),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.md);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        leading: BackButton(onPressed: () => context.go(AppRoutes.login)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[InlineMessage(message: _error!), gap],
                  Text(
                    'Account type',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<UserRole>(
                    segments: [
                      for (final role in Registration.selfRegisterRoles)
                        ButtonSegment(value: role, label: Text(role.label)),
                    ],
                    selected: {_role},
                    onSelectionChanged: _submitting
                        ? null
                        : (s) => setState(() => _role = s.first),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Hospital, police and private-driver accounts are created by an administrator.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  gap,
                  _field(
                    _name,
                    'Full name',
                    AutofillHints.name,
                    (v) => AuthValidators.required(v, 'name'),
                  ),
                  gap,
                  _field(
                    _email,
                    'Email',
                    AutofillHints.email,
                    AuthValidators.email,
                    keyboard: TextInputType.emailAddress,
                  ),
                  gap,
                  _field(
                    _mobile,
                    'Mobile number',
                    AutofillHints.telephoneNumberNational,
                    AuthValidators.mobile,
                    keyboard: TextInputType.phone,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                  ),
                  gap,
                  TextFormField(
                    controller: _password,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText:
                          '8+ characters: upper and lower case, a number, and one of @ \$ ! % * ? &',
                      helperMaxLines: 2,
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.newPassword,
                    enabled: !_submitting,
                  ),
                  gap,
                  _field(
                    _city,
                    'City',
                    AutofillHints.addressCity,
                    (v) => AuthValidators.required(v, 'city'),
                  ),
                  gap,
                  _field(
                    _address,
                    'Address',
                    AutofillHints.fullStreetAddress,
                    (v) => AuthValidators.required(v, 'address'),
                  ),
                  if (_role == UserRole.ambulanceDriver) ...[
                    gap,
                    _field(
                      _vehicle,
                      'Vehicle number (optional)',
                      null,
                      null,
                      capitalization: TextCapitalization.characters,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Create account',
                    loadingLabel: 'Creating account…',
                    isLoading: _submitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => context.go(AppRoutes.login),
                    child: const Text('I already have an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String? autofill,
    String? Function(String?)? validator, {
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: keyboard,
      inputFormatters: formatters,
      textCapitalization: capitalization,
      autofillHints: autofill == null ? null : [autofill],
      textInputAction: TextInputAction.next,
      validator: validator,
      enabled: !_submitting,
    );
  }
}
