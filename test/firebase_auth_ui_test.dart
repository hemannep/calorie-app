import 'dart:async';

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/auth_repository.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/features/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAccountAuth implements AccountAuthRepository, AppleAuthRepository {
  final apple = Completer<AppState?>();
  int appleCalls = 0;
  @override
  Future<AppState?> signInWithApple() {
    appleCalls++;
    return apple.future;
  }

  final google = Completer<AppState?>();
  String? resetEmail;
  int googleCalls = 0;
  @override
  Future<AppState?> signInWithGoogle() {
    googleCalls++;
    return google.future;
  }

  @override
  Future<void> resetPassword(String email) async {
    resetEmail = email;
  }

  @override
  Future<AppState?> restore() async => null;
  @override
  Future<AppState> signIn(String email, String password) async =>
      throw StateError('Invalid credentials');
  @override
  Future<AppState> register(String name, String email, String password) async =>
      throw StateError('Duplicate email');
  @override
  Future<void> signOut() async {}
}

class FakeVerificationAuth
    implements AuthRepository, EmailVerificationRepository {
  FakeVerificationAuth(this.state);
  final AppState state;
  bool pending = true, verified = false;
  int resendCalls = 0;

  @override
  bool get requiresEmailVerification => pending;
  @override
  String? get verificationEmail => 'new@example.test';
  @override
  Future<void> resendEmailVerification() async {
    resendCalls++;
  }

  @override
  Future<bool> refreshEmailVerification() async {
    if (verified) pending = false;
    return verified;
  }

  @override
  Future<AppState?> activateVerifiedUser() async => verified ? state : null;
  @override
  Future<AppState?> restore() async => null;
  @override
  Future<AppState> signIn(String email, String password) async => state;
  @override
  Future<AppState> register(String name, String email, String password) async =>
      state;
  @override
  Future<void> signOut() async => pending = false;
}

void main() {
  testWidgets(
    'Apple sign-in on iOS follows the build capability and handles cancellation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final repo = FakeAccountAuth();
      var authenticated = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AuthScreen(
            repository: repo,
            onAuthenticated: (_) => authenticated = true,
          ),
        ),
      );
      if (!const bool.fromEnvironment('KAYLEO_APPLE_SIGN_IN_ENABLED')) {
        expect(find.text('Sign in with Apple'), findsNothing);
        expect(repo.appleCalls, 0);
        debugDefaultTargetPlatformOverride = null;
        return;
      }
      await tester.ensureVisible(find.text('Sign in with Apple'));
      await tester.tap(find.text('Sign in with Apple'));
      await tester.pump();
      expect(repo.appleCalls, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Sign in with Apple'),
            )
            .onPressed,
        null,
      );
      repo.apple.complete(null);
      await tester.pumpAndSettle();
      expect(authenticated, false);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Sign in with Apple'),
            )
            .onPressed,
        isNotNull,
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('Apple sign-in is hidden on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          repository: FakeAccountAuth(),
          onAuthenticated: (_) {},
        ),
      ),
    );
    expect(find.text('Sign in with Apple'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'Google cancellation preserves login and prevents duplicate submissions',
    (tester) async {
      final repo = FakeAccountAuth();
      var authenticated = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: kayleoTheme(),
          home: AuthScreen(
            repository: repo,
            onAuthenticated: (_) => authenticated = true,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      expect(repo.googleCalls, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Continue with Google'),
            )
            .onPressed,
        null,
      );
      expect(find.text('Please wait…'), findsOneWidget);
      repo.google.complete(null);
      await tester.pumpAndSettle();
      expect(authenticated, false);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Continue with Google'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Welcome back.'), findsOneWidget);
    },
  );
  testWidgets(
    'password reset validates email and displays a private generic response',
    (tester) async {
      final repo = FakeAccountAuth();
      await tester.pumpWidget(
        MaterialApp(
          theme: kayleoTheme(),
          home: AuthScreen(repository: repo, onAuthenticated: (_) {}),
        ),
      );
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(repo.resetEmail, null);
      expect(find.text('Reset your password.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('send-reset-email')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('reset-email')),
        'owner@example.test',
      );
      await tester.tap(find.byKey(const Key('send-reset-email')));
      await tester.pumpAndSettle();
      expect(repo.resetEmail, 'owner@example.test');
      expect(find.textContaining('If an account exists'), findsOneWidget);
      expect(find.text('Check your email.'), findsOneWidget);
    },
  );

  testWidgets('registration mode is usable on a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: AuthScreen(
          repository: FakeAccountAuth(),
          onAuthenticated: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your space.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Your name'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Confirm password'),
      findsOneWidget,
    );
    expect(find.text('Create my account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login and registration switch with horizontal swipes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: AuthScreen(
          repository: FakeAccountAuth(),
          onAuthenticated: (_) {},
        ),
      ),
    );
    await tester.dragFrom(const Offset(400, 300), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(find.text('Create your space.'), findsOneWidget);
    await tester.dragFrom(const Offset(400, 300), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back.'), findsOneWidget);
  });

  testWidgets('pending email verification supports resend and refresh', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.load();
    final repo = FakeVerificationAuth(state);
    AppState? authenticated;
    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: AuthScreen(
          repository: repo,
          onAuthenticated: (value) => authenticated = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verify your email.'), findsOneWidget);
    expect(find.text('new@example.test'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('verification-resend')));
    await tester.tap(find.byKey(const Key('verification-resend')));
    await tester.pumpAndSettle();
    expect(repo.resendCalls, 1);
    repo.verified = true;
    await tester.ensureVisible(find.byKey(const Key('verification-refresh')));
    await tester.tap(find.byKey(const Key('verification-refresh')));
    await tester.pumpAndSettle();
    expect(authenticated, same(state));
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
