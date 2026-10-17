import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';

class DemoIdentity {
  const DemoIdentity(this.email, this.name);
  final String email, name;
}

abstract interface class AuthRepository {
  Future<AppState?> restore();
  Future<AppState> signIn(String email, String password);
  Future<AppState> register(String name, String email, String password);
  Future<void> signOut();
}

abstract interface class AccountAuthRepository implements AuthRepository {
  Future<AppState?> signInWithGoogle();
  Future<void> resetPassword(String email);
}

/// Capabilities for password accounts that must verify their email address.
abstract interface class EmailVerificationRepository {
  bool get requiresEmailVerification;
  String? get verificationEmail;
  Future<void> resendEmailVerification();
  Future<bool> refreshEmailVerification();
  Future<AppState?> activateVerifiedUser();
}

abstract interface class AppleAuthRepository {
  Future<AppState?> signInWithApple();
}

/// Intentionally permissive demo auth. Passwords are never stored or compared.
class DemoAuthRepository implements AuthRepository {
  static const sessionKey = 'kayleo_demo_session_v1';
  static const accountsKey = 'kayleo_demo_accounts_v1';
  static bool validEmail(String email) =>
      email.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  static String recordKey(String email) =>
      'kayleo_account_${Uri.encodeComponent(email.toLowerCase())}_v1';
  Future<Map<String, String>> _accounts(SharedPreferences prefs) async {
    final raw = prefs.getString(accountsKey);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw));
    } catch (_) {
      await prefs.setString('${accountsKey}_recovery', raw);
      throw StateError(
        'Demo accounts could not be read. Your backup has been preserved.',
      );
    }
  }

  Future<AppState> _activate(
    String name,
    String email,
    SharedPreferences prefs,
  ) async {
    final key = recordKey(email);
    final legacy = prefs.getString(AppState.storageKey);
    final owner = prefs.getString('kayleo_legacy_owner_v1');
    if (legacy != null && (owner == null || owner == email)) {
      if (owner == null &&
          !await prefs.setString('kayleo_legacy_owner_v1', email)) {
        throw StateError('Could not reserve existing data.');
      }
      if (!prefs.containsKey(key) && !await prefs.setString(key, legacy)) {
        throw StateError('Could not save existing data.');
      }
    }
    final state = await AppState.load(recordKey: key);
    state.accountEmail = email;
    if (!state.onboarded) state.profile.name = name;
    if (!await prefs.setString(sessionKey, email)) {
      state.dispose();
      throw StateError('Could not save this session.');
    }
    return state;
  }

  void _validate(String email, String password) {
    if (!validEmail(email)) {
      throw const FormatException('Enter a valid email address.');
    }
    if (password.length < 6 || password.length > 128) {
      throw const FormatException('Use a dummy password of 6–128 characters.');
    }
  }

  @override
  Future<AppState?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(sessionKey);
    if (saved == null) return null;
    final accounts = await _accounts(prefs);
    if (!validEmail(saved) || !accounts.containsKey(saved)) {
      await prefs.remove(sessionKey);
      return null;
    }
    return _activate(accounts[saved]!, saved, prefs);
  }

  @override
  Future<AppState> signIn(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    _validate(normalized, password);
    final prefs = await SharedPreferences.getInstance();
    final accounts = await _accounts(prefs);
    final name = accounts[normalized] ?? normalized.split('@').first;
    accounts[normalized] = name;
    if (!await prefs.setString(accountsKey, jsonEncode(accounts))) {
      throw StateError('Could not save the demo account.');
    }
    return _activate(name, normalized, prefs);
  }

  @override
  Future<AppState> register(String name, String email, String password) async {
    final normalized = email.trim().toLowerCase();
    _validate(normalized, password);
    if (name.trim().isEmpty || name.trim().length > 60) {
      throw const FormatException('Enter a name of 1–60 characters.');
    }
    final prefs = await SharedPreferences.getInstance();
    final accounts = await _accounts(prefs);
    if (accounts.containsKey(normalized)) {
      throw StateError(
        'That demo email is already registered. Sign in instead.',
      );
    }
    accounts[normalized] = name.trim();
    if (!await prefs.setString(accountsKey, jsonEncode(accounts))) {
      throw StateError('Could not save the demo account.');
    }
    return _activate(name.trim(), normalized, prefs);
  }

  @override
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(sessionKey)) {
      throw StateError('Could not sign out. Try again.');
    }
  }
}
