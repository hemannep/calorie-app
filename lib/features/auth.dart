import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/auth_repository.dart';
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
      final repo = widget.repository ?? DemoAuthRepository();
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
        setState(
          () => error = e.toString().replaceFirst(
            RegExp(r'^(Bad state|FormatException):\s*'),
            '',
          ),
        );
      }
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
                      maxLength: 60,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: email,
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
                  const SizedBox(height: 20),
                  Panel(
                    child: Text(
                      'Demo access: any valid email and a dummy password of 6–128 characters. Passwords are never stored or verified. Firebase will replace this demo provider.',
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
