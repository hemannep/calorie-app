import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/app_state.dart';
import '../core/auth_repository.dart';
import '../core/firebase_auth_repository.dart';
import '../core/ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated, this.repository});
  final ValueChanged<AppState> onAuthenticated;
  final AuthRepository? repository;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>(),
      name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool registering = false, busy = false, obscure = true;
  String? error;
  AuthRepository get repository =>
      widget.repository ?? FirebaseAuthRepository.instance;
  AccountAuthRepository? get accountRepository =>
      repository is AccountAuthRepository
      ? repository as AccountAuthRepository
      : null;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = repository;
      final state = registering
          ? await repo.register(name.text, email.text, password.text)
          : await repo.signIn(email.text, password.text);
      if (mounted) {
        widget.onAuthenticated(state);
      } else {
        state.dispose();
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = authErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> social(Future<AppState?> Function() signIn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await signIn();
      if (next != null) {
        if (mounted) {
          widget.onAuthenticated(next);
        } else {
          next.dispose();
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (!DemoAuthRepository.validEmail(email.text.trim())) {
      setState(() => error = 'Enter your email address first.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await accountRepository!.resetPassword(email.text);
      if (mounted) {
        setState(
          () => error = 'If an account exists, a password reset email will arrive shortly. Check your spam folder too.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Brand(size: 38),
                  const SizedBox(height: 36),
                  Text(
                    registering
                        ? 'Make room for balance.'
                        : 'Welcome to your day.',
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A little clarity, one meal at a time.',
                    style: TextStyle(color: context.kayleoMuted),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Sign in'),
                        selected: !registering,
                        onSelected: busy
                            ? null
                            : (_) => setState(() {
                                registering = false;
                                error = null;
                              }),
                      ),
                      ChoiceChip(
                        label: const Text('Create account'),
                        selected: registering,
                        onSelected: busy
                            ? null
                            : (_) => setState(() {
                                registering = true;
                                error = null;
                              }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (registering) ...[
                    TextFormField(
                      controller: name,
                      enabled: !busy,
                      maxLength: 60,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: email,
                    enabled: !busy,
                    maxLength: 254,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      counterText: '',
                    ),
                    validator: (v) => DemoAuthRepository.validEmail(v!.trim())
                        ? null
                        : 'Enter a valid email',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: password,
                    enabled: !busy,
                    autofillHints: [
                      registering
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    maxLength: 128,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      counterText: '',
                      suffixIcon: IconButton(
                        tooltip: obscure ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        v!.length < 6 ? 'Use at least 6 characters' : null,
                  ),
                  if (registering) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: confirm,
                      enabled: !busy,
                      maxLength: 128,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        counterText: '',
                      ),
                      validator: (v) =>
                          v == password.text ? null : 'Passwords must match',
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(
                        busy
                            ? 'Please wait…'
                            : registering
                            ? 'Create my account'
                            : 'Sign in',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (accountRepository != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => social(accountRepository!.signInWithGoogle),
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('Continue with Google'),
                      ),
                    ),
                    if (!registering)
                      TextButton(
                        onPressed: busy ? null : resetPassword,
                        child: const Text('Forgot password?'),
                      ),
                  ],
                  if (!kIsWeb &&
                      const bool.fromEnvironment(
                        'KAYLEO_APPLE_SIGN_IN_ENABLED',
                        defaultValue: false,
                      ) &&
                      (defaultTargetPlatform == TargetPlatform.iOS ||
                          defaultTargetPlatform == TargetPlatform.macOS) &&
                      repository is AppleAuthRepository) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => social(
                                (repository as AppleAuthRepository)
                                    .signInWithApple,
                              ),
                        icon: const Icon(Icons.apple),
                        label: const Text('Sign in with Apple'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Panel(
                    child: Text(
                      'Your account is secured by Firebase. Your diary stays available offline, with account data backed up to Firestore. Meal photos stay on this device.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.kayleoMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
