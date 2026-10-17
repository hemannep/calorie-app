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
  bool registering = false, busy = false, obscure = true, confirmObscure = true;
  bool showingVerification = false;
  bool switchingMode = false, instantPagePosition = false;
  double pageOpacity = 1;
  Offset pageOffset = Offset.zero;
  Offset? swipeStart;
  AppState? pendingVerificationState;
  String? error;
  AuthRepository get repository =>
      widget.repository ?? FirebaseAuthRepository.instance;
  AccountAuthRepository? get accountRepository =>
      repository is AccountAuthRepository
      ? repository as AccountAuthRepository
      : null;
  EmailVerificationRepository? get verificationRepository =>
      repository is EmailVerificationRepository
      ? repository as EmailVerificationRepository
      : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          verificationRepository?.requiresEmailVerification != true) {
        return;
      }
      setState(() => showingVerification = true);
    });
  }

  @override
  void dispose() {
    pendingVerificationState?.dispose();
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
        if (verificationRepository?.requiresEmailVerification == true) {
          setState(() {
            pendingVerificationState = state;
            showingVerification = true;
            busy = false;
          });
        } else {
          widget.onAuthenticated(state);
        }
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

  Future<void> resetPassword() async => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _PasswordResetSheet(
      initialEmail: email.text.trim(),
      sendReset: accountRepository!.resetPassword,
    ),
  );

  Future<void> refreshVerification() async {
    final verification = verificationRepository;
    if (busy || verification == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final verified = await verification.refreshEmailVerification();
      if (!mounted) return;
      if (!verified) {
        setState(
          () => error =
              'Not verified yet. Open the link in your email, then try again.',
        );
        return;
      }
      final next =
          pendingVerificationState ?? await verification.activateVerifiedUser();
      if (!mounted) {
        next?.dispose();
        return;
      }
      if (next == null) {
        setState(() => error = 'Sign in again to finish verification.');
        return;
      }
      pendingVerificationState = null;
      widget.onAuthenticated(next);
    } catch (e) {
      if (mounted) setState(() => error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resendVerification() async {
    final verification = verificationRepository;
    if (busy || verification == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await verification.resendEmailVerification();
      if (mounted) {
        setState(() => error = 'A fresh verification email is on its way.');
      }
    } catch (e) {
      if (mounted) setState(() => error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changeVerificationEmail() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await repository.signOut();
      pendingVerificationState?.dispose();
      pendingVerificationState = null;
      if (mounted) {
        setState(() {
          showingVerification = false;
          registering = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> switchMode(bool value) async {
    if (busy || switchingMode || registering == value) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final direction = value ? 1.0 : -1.0;
    if (!reduceMotion) {
      setState(() {
        switchingMode = true;
        pageOpacity = 0;
        pageOffset = Offset(-direction * .11, 0);
      });
      await Future<void>.delayed(const Duration(milliseconds: 145));
      if (!mounted) return;
    }
    form.currentState?.reset();
    setState(() {
      registering = value;
      error = null;
      obscure = true;
      confirmObscure = true;
      instantPagePosition = !reduceMotion;
      pageOffset = reduceMotion ? Offset.zero : Offset(direction * .11, 0);
      pageOpacity = reduceMotion ? 1 : 0;
    });
    if (reduceMotion) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      instantPagePosition = false;
      pageOffset = Offset.zero;
      pageOpacity = 1;
    });
    await Future<void>.delayed(const Duration(milliseconds: 210));
    if (mounted) setState(() => switchingMode = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        return Stack(
          children: [
            const Positioned.fill(child: _AuthBackdrop()),
            SafeArea(
              child: Row(
                children: [
                  if (wide)
                    Expanded(
                      flex: 11,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(64, 52, 32, 52),
                        child: const _AuthStory(),
                      ),
                    ),
                  Expanded(
                    flex: wide ? 10 : 1,
                    child: Center(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 56 : KayleoSpacing.xl,
                          vertical: KayleoSpacing.xl,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!wide) ...[
                                const Align(
                                  alignment: Alignment.center,
                                  child: Brand(size: 34),
                                ),
                                const SizedBox(height: KayleoSpacing.xl),
                              ],
                              AnimatedSize(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: AnimatedSwitcher(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 260),
                                  child: showingVerification
                                      ? _verificationCard(context)
                                      : _authCard(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _verificationCard(BuildContext context) => Container(
    key: const ValueKey('verification-card'),
    padding: const EdgeInsets.all(KayleoSpacing.xl),
    decoration: _cardDecoration(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: context.kayleoSurfaces.soft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            Icons.mark_email_unread_outlined,
            color: context.kayleoPrimary,
            size: 26,
          ),
        ),
        const SizedBox(height: KayleoSpacing.xl),
        Text(
          'Verify your email.',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.1),
        ),
        const SizedBox(height: KayleoSpacing.sm),
        Text(
          'We sent a secure verification link to',
          style: TextStyle(color: context.kayleoMuted, height: 1.5),
        ),
        const SizedBox(height: 3),
        Text(
          verificationRepository?.verificationEmail ?? email.text.trim(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: KayleoSpacing.xl),
        for (final (number, text) in [
          ('1', 'Open the email from Kayleo'),
          ('2', 'Tap the verification link'),
          ('3', 'Return here to continue'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: KayleoSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.kayleoSurfaces.soft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    number,
                    style: TextStyle(
                      color: context.kayleoPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: KayleoSpacing.md),
                Expanded(
                  child: Text(text, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        const SizedBox(height: KayleoSpacing.md),
        if (error != null) _AuthMessage(message: error!),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('verification-refresh'),
            onPressed: busy ? null : refreshVerification,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(busy ? 'Checking…' : 'I’ve verified my email'),
          ),
        ),
        const SizedBox(height: KayleoSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: TextButton(
                key: const Key('verification-resend'),
                onPressed: busy ? null : resendVerification,
                child: const Text('Resend email'),
              ),
            ),
            SizedBox(
              height: 18,
              child: VerticalDivider(color: context.kayleoSurfaces.border),
            ),
            Flexible(
              child: TextButton(
                onPressed: busy ? null : changeVerificationEmail,
                child: const Text('Use another email'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _authCard(BuildContext context) => Container(
    key: const ValueKey('auth-card'),
    padding: const EdgeInsets.all(KayleoSpacing.xl),
    decoration: _cardDecoration(context),
    clipBehavior: Clip.antiAlias,
    child: AnimatedSlide(
      key: const Key('auth-page-slide'),
      duration: instantPagePosition
          ? Duration.zero
          : const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      offset: pageOffset,
      child: AnimatedOpacity(
        key: const Key('auth-page-opacity'),
        duration: instantPagePosition
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        opacity: pageOpacity,
        child: Listener(
          key: const Key('auth-swipe-area'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) => swipeStart = event.position,
          onPointerCancel: (_) => swipeStart = null,
          onPointerMove: (event) {
            final start = swipeStart;
            if (start == null) return;
            final delta = event.position - start;
            if (delta.dx.abs() < 72 || delta.dx.abs() < delta.dy.abs() * 1.4) {
              return;
            }
            swipeStart = null;
            switchMode(delta.dx < 0);
          },
          onPointerUp: (_) => swipeStart = null,
          child: AutofillGroup(
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    registering ? 'Create your space.' : 'Welcome back.',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const SizedBox(height: KayleoSpacing.sm),
                  Text(
                    registering
                        ? 'A simple place for your everyday nutrition.'
                        : 'Continue your day in balance.',
                    style: TextStyle(color: context.kayleoMuted, height: 1.5),
                  ),
                  const SizedBox(height: KayleoSpacing.xl),
                  _AuthModeSwitch(
                    registering: registering,
                    enabled: !busy && !switchingMode,
                    onChanged: switchMode,
                  ),
                  const SizedBox(height: KayleoSpacing.xl),
                  _credentialFields(),
                  if (!registering && accountRepository != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy ? null : resetPassword,
                        child: const Text('Forgot password?'),
                      ),
                    )
                  else
                    const SizedBox(height: KayleoSpacing.xl),
                  if (error != null) _AuthMessage(message: error!),
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
                  if (accountRepository != null || _showApple) ...[
                    const SizedBox(height: KayleoSpacing.lg),
                    const _OrDivider(),
                    const SizedBox(height: KayleoSpacing.lg),
                  ],
                  if (accountRepository != null)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => social(accountRepository!.signInWithGoogle),
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
                        label: const Text('Continue with Google'),
                      ),
                    ),
                  if (_showApple) ...[
                    if (accountRepository != null)
                      const SizedBox(height: KayleoSpacing.md),
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
                  const SizedBox(height: KayleoSpacing.xl),
                  Center(
                    child: Text(
                      'Private by design · Meal photos stay on your device',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
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

  BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
    color: context.kayleoSurfaces.card.withValues(alpha: .94),
    borderRadius: BorderRadius.circular(KayleoRadius.large),
    border: Border.all(
      color: Theme.of(context).brightness == Brightness.light
          ? Colors.white.withValues(alpha: .75)
          : context.kayleoSurfaces.border,
    ),
    boxShadow: Theme.of(context).brightness == Brightness.light
        ? const [
            BoxShadow(
              color: Color(0x0D163E2D),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ]
        : null,
  );

  Widget _credentialFields() => Column(
    children: [
      if (registering) ...[
        TextFormField(
          controller: name,
          enabled: !busy,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'How should we call you?',
            counterText: '',
          ),
          validator: (v) => v!.trim().isEmpty ? 'Enter your name' : null,
        ),
        const SizedBox(height: KayleoSpacing.lg),
      ],
      TextFormField(
        controller: email,
        enabled: !busy,
        maxLength: 254,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(
          labelText: 'Email address',
          hintText: 'you@example.com',
          counterText: '',
        ),
        validator: (v) => DemoAuthRepository.validEmail(v!.trim())
            ? null
            : 'Enter a valid email',
      ),
      const SizedBox(height: KayleoSpacing.lg),
      TextFormField(
        controller: password,
        enabled: !busy,
        autofillHints: [
          registering ? AutofillHints.newPassword : AutofillHints.password,
        ],
        maxLength: 128,
        obscureText: obscure,
        textInputAction: registering
            ? TextInputAction.next
            : TextInputAction.done,
        onFieldSubmitted: registering || busy ? null : (_) => submit(),
        decoration: InputDecoration(
          labelText: 'Password',
          hintText: registering ? 'At least 6 characters' : null,
          counterText: '',
          suffixIcon: IconButton(
            tooltip: obscure ? 'Show password' : 'Hide password',
            onPressed: busy ? null : () => setState(() => obscure = !obscure),
            icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
        validator: (v) => v!.length < 6 ? 'Use at least 6 characters' : null,
      ),
      if (registering) ...[
        const SizedBox(height: KayleoSpacing.lg),
        TextFormField(
          controller: confirm,
          enabled: !busy,
          maxLength: 128,
          obscureText: confirmObscure,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: busy ? null : (_) => submit(),
          decoration: InputDecoration(
            labelText: 'Confirm password',
            counterText: '',
            suffixIcon: IconButton(
              tooltip: confirmObscure
                  ? 'Show confirmed password'
                  : 'Hide confirmed password',
              onPressed: busy
                  ? null
                  : () => setState(() => confirmObscure = !confirmObscure),
              icon: Icon(
                confirmObscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: (v) => v == password.text ? null : 'Passwords must match',
        ),
      ],
    ],
  );

  bool get _showApple =>
      !kIsWeb &&
      const bool.fromEnvironment(
        'KAYLEO_APPLE_SIGN_IN_ENABLED',
        defaultValue: false,
      ) &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) &&
      repository is AppleAuthRepository;
}

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({
    required this.initialEmail,
    required this.sendReset,
  });
  final String initialEmail;
  final Future<void> Function(String email) sendReset;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  final form = GlobalKey<FormState>();
  late final TextEditingController email;
  bool busy = false, sent = false;
  String? error;

  @override
  void initState() {
    super.initState();
    email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.sendReset(email.text.trim());
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (mounted) setState(() => error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.only(
      left: KayleoSpacing.xl,
      right: KayleoSpacing.xl,
      top: KayleoSpacing.md,
      bottom: MediaQuery.viewInsetsOf(context).bottom + KayleoSpacing.xl,
    ),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            child: sent ? _success(context) : _request(context),
          ),
        ),
      ),
    ),
  );

  Widget _request(BuildContext context) => Form(
    key: form,
    child: Column(
      key: const ValueKey('reset-request'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: context.kayleoSurfaces.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        const SizedBox(height: KayleoSpacing.xl),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: context.kayleoSurfaces.soft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.lock_reset_rounded, color: context.kayleoPrimary),
        ),
        const SizedBox(height: KayleoSpacing.lg),
        Text(
          'Reset your password.',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.7),
        ),
        const SizedBox(height: KayleoSpacing.sm),
        Text(
          'Enter your account email and we’ll send a secure reset link.',
          style: TextStyle(color: context.kayleoMuted, height: 1.55),
        ),
        const SizedBox(height: KayleoSpacing.xl),
        TextFormField(
          key: const Key('reset-email'),
          controller: email,
          autofocus: widget.initialEmail.isEmpty,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'you@example.com',
          ),
          validator: (value) => DemoAuthRepository.validEmail(value!.trim())
              ? null
              : 'Enter a valid email',
          onFieldSubmitted: busy ? null : (_) => send(),
        ),
        if (error != null) ...[
          const SizedBox(height: KayleoSpacing.lg),
          _AuthMessage(message: error!),
        ],
        const SizedBox(height: KayleoSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('send-reset-email'),
            onPressed: busy ? null : send,
            child: Text(busy ? 'Sending…' : 'Send reset link'),
          ),
        ),
        const SizedBox(height: KayleoSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Back to sign in'),
          ),
        ),
      ],
    ),
  );

  Widget _success(BuildContext context) => Column(
    key: const ValueKey('reset-sent'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: KayleoSpacing.md),
      Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(color: lime, shape: BoxShape.circle),
        child: const Icon(Icons.mark_email_read_outlined, color: forest),
      ),
      const SizedBox(height: KayleoSpacing.xl),
      Text(
        'Check your email.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.7),
      ),
      const SizedBox(height: KayleoSpacing.sm),
      Text(
        'If an account exists for ${email.text.trim()}, a secure password reset link is on its way. Check spam if it doesn’t arrive.',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.kayleoMuted, height: 1.55),
      ),
      const SizedBox(height: KayleoSpacing.xl),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to sign in'),
        ),
      ),
      const SizedBox(height: KayleoSpacing.lg),
    ],
  );
}

class _AuthModeSwitch extends StatelessWidget {
  const _AuthModeSwitch({
    required this.registering,
    required this.enabled,
    required this.onChanged,
  });
  final bool registering, enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Account action',
    child: Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.kayleoSurfaces.border),
        ),
      ),
      child: Row(
        children: [
          _item(context, 'Sign in', !registering, () => onChanged(false)),
          _item(context, 'Create account', registering, () => onChanged(true)),
        ],
      ),
    ),
  );

  Widget _item(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback action,
  ) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: enabled ? action : null,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          alignment: Alignment.center,
          padding: const EdgeInsets.only(top: 10, bottom: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected ? context.kayleoPrimary : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? context.kayleoText : context.kayleoMuted,
            ),
          ),
        ),
      ),
    ),
  );
}

class _AuthMessage extends StatelessWidget {
  const _AuthMessage({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final informational =
        message.startsWith('If an account exists') ||
        message.startsWith('A fresh verification');
    final color = informational
        ? context.kayleoPrimary
        : Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: KayleoSpacing.lg),
      padding: const EdgeInsets.all(KayleoSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(KayleoRadius.small),
      ),
      child: Row(
        children: [
          Icon(
            informational
                ? Icons.mark_email_read_outlined
                : Icons.info_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: KayleoSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, height: 1.45, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: KayleoSpacing.md),
        child: Text(
          'OR',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: context.kayleoMuted,
          ),
        ),
      ),
      const Expanded(child: Divider()),
    ],
  );
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/kayleo-auth-bg.jpg',
          fit: BoxFit.cover,
          color: dark ? const Color(0xFF243A2B) : null,
          colorBlendMode: BlendMode.multiply,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                context.kayleoBackground.withValues(alpha: dark ? .62 : .14),
                context.kayleoBackground.withValues(alpha: dark ? .36 : 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthStory extends StatelessWidget {
  const _AuthStory();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Brand(size: 36),
      const Spacer(),
      Text(
        'Know your food.\nKeep your balance.',
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -2,
          height: 1.04,
        ),
      ),
      const SizedBox(height: KayleoSpacing.lg),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Text(
          'Thoughtful nutrition, made simple for real days.',
          style: TextStyle(
            fontSize: 16,
            height: 1.65,
            color: context.kayleoMuted,
          ),
        ),
      ),
      const Spacer(flex: 2),
    ],
  );
}
