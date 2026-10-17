import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app_state.dart';
import 'auth_repository.dart';

/// Firebase owns credentials and sessions; the local diary is isolated by UID.
class FirebaseAuthRepository
    implements
        AccountAuthRepository,
        AppleAuthRepository,
        EmailVerificationRepository {
  FirebaseAuthRepository({this._auth});
  static final instance = FirebaseAuthRepository();
  final FirebaseAuth? _auth;
  FirebaseAuth get auth => _auth ?? FirebaseAuth.instance;
  static Future<void>? _googleInitialization;

  Future<AppState> _activate(User user) async {
    final state = await AppState.load(
      recordKey: 'kayleo_firebase_${user.uid}_v1',
    );
    state.accountUid = user.uid;
    state.accountEmail = user.email;
    if (!state.onboarded) {
      state.profile.name =
          user.displayName ?? user.email?.split('@').first ?? 'You';
    }
    return state;
  }

  @override
  Future<AppState?> restore() async {
    final user = await auth.authStateChanges().first;
    return user == null || requiresEmailVerification ? null : _activate(user);
  }

  @override
  Future<AppState> signIn(String email, String password) async {
    final result = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return await _activate(result.user!);
  }

  @override
  Future<AppState> register(String name, String email, String password) async {
    if (name.trim().isEmpty || name.trim().length > 60) {
      throw const FormatException('Enter a name of 1–60 characters.');
    }
    final result = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = result.user!;
    await user.updateDisplayName(name.trim());
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException {
      // The account exists even if initial delivery fails. The verification
      // screen provides a safe, explicit retry without creating a duplicate.
    }
    return _activate(user);
  }

  bool _isPasswordUser(User user) =>
      user.providerData.any((provider) => provider.providerId == 'password');

  @override
  bool get requiresEmailVerification {
    final user = auth.currentUser;
    return user != null && _isPasswordUser(user) && !user.emailVerified;
  }

  @override
  String? get verificationEmail => auth.currentUser?.email;

  @override
  Future<void> resendEmailVerification() async {
    final user = auth.currentUser;
    if (user == null || !_isPasswordUser(user) || user.emailVerified) return;
    await user.sendEmailVerification();
  }

  @override
  Future<bool> refreshEmailVerification() async {
    final user = auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return auth.currentUser?.emailVerified ?? false;
  }

  @override
  Future<AppState?> activateVerifiedUser() async {
    final user = auth.currentUser;
    if (user == null || requiresEmailVerification) return null;
    return _activate(user);
  }

  @override
  Future<AppState?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final result = await auth.signInWithPopup(GoogleAuthProvider());
        return await _activate(result.user!);
      }
      _googleInitialization ??= GoogleSignIn.instance.initialize();
      await _googleInitialization;
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw StateError('Google did not provide a sign-in token.');
      }
      final result = await auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: token),
      );
      return await _activate(result.user!);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<AppState?> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    try {
      final result = kIsWeb
          ? await auth.signInWithPopup(provider)
          : await auth.signInWithProvider(provider);
      return await _activate(result.user!);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' ||
          e.code == 'web-context-canceled' ||
          e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> resetPassword(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());

  @override
  Future<void> signOut() async {
    await auth.signOut();
    // Firebase sign-out is authoritative even if clearing Google's chooser fails.
    if (!kIsWeb && _googleInitialization != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }
}

String authErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'The email or password is incorrect.',
      'email-already-in-use' =>
        'This email already has an account. Sign in or reset your password.',
      'invalid-email' => 'Enter a valid email address.',
      'weak-password' =>
        'Choose a stronger password with at least 6 characters.',
      'network-request-failed' => 'Check your connection and try again.',
      'too-many-requests' => 'Too many attempts. Please try again later.',
      'user-disabled' => 'This account has been disabled.',
      'operation-not-allowed' =>
        'This sign-in method is unavailable. Please contact support.',
      'account-exists-with-different-credential' =>
        'Sign in using the method you originally used for this email.',
      'popup-blocked' => 'Allow the Google sign-in popup and try again.',
      _ => 'Sign-in could not finish. Please try again.',
    };
  }
  if (error is GoogleSignInException) {
    return 'Google sign-in could not finish. Please try again.';
  }
  return error.toString().replaceFirst(
    RegExp(r'^(Bad state|FormatException):\s*'),
    '',
  );
}
