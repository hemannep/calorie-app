import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';

/// Sends a small, account-scoped daily summary to the phone's home widgets.
class HomeWidgetService {
  HomeWidgetService._();
  static final instance = HomeWidgetService._();
  static const channel = MethodChannel('kayleo/home_widgets');
  static const actions = {'photo', 'voice', 'barcode', 'today', 'streak'};

  AppState? _state;
  void Function(String action)? onAction;
  String? _pendingAction;
  bool _initialized = false;

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') _receive(call.arguments as String?);
    });
    try {
      _receive(await channel.invokeMethod<String>('getInitialAction'));
    } on MissingPluginException {
      // Desktop and widget tests have no phone widget host.
    }
  }

  void _receive(String? action) {
    if (action == null || !actions.contains(action)) return;
    if (onAction == null) {
      _pendingAction = action;
    } else {
      onAction!(action);
    }
  }

  void dispatchPending() {
    final action = _pendingAction;
    if (action == null || onAction == null) return;
    _pendingAction = null;
    onAction!(action);
  }

  void attach(AppState? next) {
    if (!identical(_state, next)) {
      _state?.removeListener(_publish);
      _state = next;
      next?.addListener(_publish);
    }
    _publish();
  }

  void refresh() => _publish();

  Future<bool> requestPin(String kind) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    if (!{'calories', 'barcode', 'streak', 'rings'}.contains(kind)) {
      return false;
    }
    try {
      return await channel.invokeMethod<bool>('requestPin', kind) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  void _publish() {
    if (kIsWeb) return;
    final state = _state;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final visible = state != null && state.onboarded && !state.signedOut;
    final total = visible ? state.totalsFor(today) : null;
    final profile = state?.profile;
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final snapshot = <String, Object>{
      'date':
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      'ready': visible,
      'appearance': state?.appearance ?? 'system',
      'calories': total?.calories.round() ?? 0,
      'calorieTarget': visible ? profile!.calorieTarget : 0,
      'protein': total?.protein.round() ?? 0,
      'proteinTarget': visible ? profile!.proteinTarget : 0,
      'carbs': total?.carbs.round() ?? 0,
      'carbTarget': visible ? profile!.carbTarget : 0,
      'fat': total?.fat.round() ?? 0,
      'fatTarget': visible ? profile!.fatTarget : 0,
      'streak': visible ? state.streak : 0,
      'loggedToday': visible && state.mealsFor(today).isNotEmpty,
      'weekLogged': List.generate(
        7,
        (i) =>
            visible && state.mealsFor(monday.add(Duration(days: i))).isNotEmpty
            ? '1'
            : '0',
      ).join(),
    };
    unawaited(
      channel.invokeMethod<void>('update', snapshot).catchError((Object _) {}),
    );
  }
}
