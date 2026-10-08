import 'dart:async';

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/auth_repository.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/features/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(find.text('Welcome to your day.'), findsOneWidget);
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
      expect(find.text('Enter your email address first.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'owner@example.test',
      );
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(repo.resetEmail, 'owner@example.test');
      expect(find.textContaining('If an account exists'), findsOneWidget);
    },
  );
}
