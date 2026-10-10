import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_state.dart';

/// Aggregated daily health activity metrics synced from Apple Health / Google Health Connect.
class HealthActivityData {
  const HealthActivityData({
    this.steps = 0,
    this.activeMinutes = 0,
    this.activeCalories = 0,
    this.motionKm = 0.0,
    this.isAuthorized = false,
    this.isAvailable = true,
    this.errorMessage,
  });

  final int steps;
  final int activeMinutes;
  final int activeCalories;
  final double motionKm;
  final bool isAuthorized;
  final bool isAvailable;
  final String? errorMessage;

  HealthActivityData copyWith({
    int? steps,
    int? activeMinutes,
    int? activeCalories,
    double? motionKm,
    bool? isAuthorized,
    bool? isAvailable,
    String? errorMessage,
  }) => HealthActivityData(
    steps: steps ?? this.steps,
    activeMinutes: activeMinutes ?? this.activeMinutes,
    activeCalories: activeCalories ?? this.activeCalories,
    motionKm: motionKm ?? this.motionKm,
    isAuthorized: isAuthorized ?? this.isAuthorized,
    isAvailable: isAvailable ?? this.isAvailable,
    errorMessage: errorMessage ?? this.errorMessage,
  );

  static const zero = HealthActivityData();
}

/// Service to connect and synchronize daily fitness and motion data
/// directly with Apple Health (iOS) and Health Connect (Android).
class HealthService {
  HealthService({Health? health}) : _health = health ?? Health();

  static HealthService instance = HealthService();

  static const String healthConnectedPrefKey = 'kayleo_health_connected';

  final Health _health;
  static const _platformChannel = MethodChannel('kayleo/health');
  bool _configured = false;

  @visibleForTesting
  HealthActivityData? mockActivityData;

  @visibleForTesting
  bool? mockIsAuthorized;

  bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  /// Human-friendly name of the platform health application.
  String get platformHealthAppName {
    if (kIsWeb) return 'Health App';
    if (Platform.isIOS) return 'Apple Health';
    if (Platform.isAndroid) return 'Google Health Connect';
    return 'Health App';
  }

  String get phoneHealthSourceLabel {
    if (kIsWeb) return 'Phone health apps';
    if (Platform.isIOS) return 'Apple Health';
    if (Platform.isAndroid) return 'Phone health apps · Health Connect';
    return 'Phone health apps';
  }

  String get shortHealthSourceLabel {
    if (kIsWeb) return 'Health';
    if (Platform.isIOS) return 'Apple Health';
    if (Platform.isAndroid) return 'Health Connect';
    return 'Health';
  }

  Future<bool> openHealthSourceSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _platformChannel.invokeMethod<bool>('openSettings') ?? false;
    } catch (e) {
      debugPrint('HealthService openHealthSourceSettings error: $e');
      return false;
    }
  }

  /// Check if Google Health Connect is available on Android.
  Future<bool> isHealthConnectAvailable() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _health.isHealthConnectAvailable();
    } catch (e) {
      debugPrint('HealthService isHealthConnectAvailable error: $e');
      return false;
    }
  }

  /// Launch store prompt to install Google Health Connect on Android.
  Future<void> installHealthConnect() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _health.installHealthConnect();
    } catch (e) {
      debugPrint('HealthService installHealthConnect error: $e');
    }
  }

  /// Supported health data types according to current platform.
  List<HealthDataType> get dataTypes {
    if (kIsWeb) return const [];
    if (Platform.isIOS) {
      return const [
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.EXERCISE_TIME,
        HealthDataType.DISTANCE_WALKING_RUNNING,
      ];
    } else if (Platform.isAndroid) {
      return const [
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.DISTANCE_DELTA,
        HealthDataType.WORKOUT,
      ];
    }
    return const [];
  }

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    if (!isPlatformSupported) return;
    try {
      await _health.configure();
      _configured = true;
    } catch (e) {
      debugPrint('HealthService configure error: $e');
    }
  }

  /// Check whether health permissions have been granted.
  Future<bool> hasPermissions() async {
    if (mockIsAuthorized != null) return mockIsAuthorized!;
    if (!isPlatformSupported) return false;
    await _ensureConfigured();
    try {
      // On Android, check if at least steps or core activity types are granted
      final types = Platform.isAndroid
          ? const [HealthDataType.STEPS]
          : dataTypes;
      if (types.isEmpty) return false;
      final permissions = List.filled(types.length, HealthDataAccess.READ);
      final has = await _health.hasPermissions(types, permissions: permissions);
      return has == true;
    } catch (e) {
      debugPrint('HealthService hasPermissions error: $e');
      return false;
    }
  }

  /// Request user authorization for HealthKit or Health Connect.
  Future<bool> requestPermissions() async {
    if (mockIsAuthorized != null) return mockIsAuthorized!;
    if (!isPlatformSupported) return false;
    await _ensureConfigured();
    try {
      if (Platform.isAndroid) {
        final available = await isHealthConnectAvailable();
        if (!available) {
          await installHealthConnect();
          return false;
        }
      }
      final types = dataTypes;
      if (types.isEmpty) return false;
      final permissions = List.filled(types.length, HealthDataAccess.READ);
      final ok = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(healthConnectedPrefKey, true);
      }
      return ok;
    } catch (e) {
      debugPrint('HealthService requestAuthorization error: $e');
      return false;
    }
  }

  /// Fetch steps, active time, activity calories, and motion for a specific day.
  Future<HealthActivityData> fetchActivityData(
    DateTime date, {
    AppState? state,
  }) async {
    if (mockActivityData != null) {
      return mockActivityData!;
    }

    // When running in demo mode without real health hardware, provide sample activity
    // data so the user can experience the rings immediately.
    if ((state?.demo == true || !isPlatformSupported) &&
        mockActivityData == null) {
      final baseSteps = state?.demo == true ? 7540 : 0;
      final baseMin = state?.demo == true ? 38 : 0;
      final baseCal = state?.demo == true ? 420 : 0;
      final baseMotion = state?.demo == true ? 5.4 : 0.0;
      return HealthActivityData(
        steps: baseSteps,
        activeMinutes: baseMin,
        activeCalories: baseCal,
        motionKm: baseMotion,
        isAuthorized: state?.demo == true,
        isAvailable: isPlatformSupported,
      );
    }

    await _ensureConfigured();

    final prefs = await SharedPreferences.getInstance();
    final isConnectedPref = prefs.getBool(healthConnectedPrefKey) ?? false;

    // Check authorization beforehand to avoid SecurityException on Android Health Connect
    if (Platform.isAndroid) {
      final hasPerm = await hasPermissions();
      if (!hasPerm) {
        return HealthActivityData(
          steps: 0,
          activeMinutes: 0,
          activeCalories: 0,
          motionKm: 0.0,
          isAuthorized: false,
          isAvailable: true,
        );
      }
    } else if (Platform.isIOS) {
      if (!isConnectedPref) {
        return HealthActivityData(
          steps: 0,
          activeMinutes: 0,
          activeCalories: 0,
          motionKm: 0.0,
          isAuthorized: false,
          isAvailable: true,
        );
      }
    }

    final now = DateTime.now();
    final isSameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final startTime = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endTime = isSameDay
        ? now
        : DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    var totalSteps = 0;
    var totalActiveMinutes = 0;
    var totalActiveCalories = 0;
    var totalMotionMeters = 0.0;
    var authorized = true;

    try {
      // 1. Fetch aggregate steps safely
      try {
        final stepsAggregate = await _health.getTotalStepsInInterval(
          startTime,
          endTime,
        );
        if (stepsAggregate != null) {
          totalSteps = stepsAggregate;
        }
      } catch (e) {
        debugPrint('HealthService getTotalStepsInInterval error: $e');
      }

      // 2. Fetch data points for active calories, exercise time, and motion safely
      final types = dataTypes;
      if (types.isNotEmpty) {
        try {
          final dataPoints = await _health.getHealthDataFromTypes(
            types: types,
            startTime: startTime,
            endTime: endTime,
          );

          for (final dp in dataPoints) {
            final val = dp.value;
            if (val is NumericHealthValue) {
              final numVal = val.numericValue;
              switch (dp.type) {
                case HealthDataType.STEPS:
                  if (totalSteps == 0) {
                    totalSteps += numVal.round();
                  }
                  break;
                case HealthDataType.ACTIVE_ENERGY_BURNED:
                  totalActiveCalories += numVal.round();
                  break;
                case HealthDataType.EXERCISE_TIME:
                  totalActiveMinutes += numVal.round();
                  break;
                case HealthDataType.APPLE_MOVE_TIME:
                  totalActiveMinutes += (numVal / 60).round();
                  break;
                case HealthDataType.DISTANCE_DELTA:
                case HealthDataType.DISTANCE_WALKING_RUNNING:
                  totalMotionMeters += numVal.toDouble();
                  break;
                default:
                  break;
              }
            } else if (dp.type == HealthDataType.WORKOUT) {
              final durationMin = dp.dateTo.difference(dp.dateFrom).inMinutes;
              if (durationMin > 0) {
                totalActiveMinutes += durationMin;
              }
            }
          }
        } catch (e) {
          debugPrint('HealthService getHealthDataFromTypes error: $e');
        }
      }

      final motionKm = double.parse(
        (totalMotionMeters / 1000.0).toStringAsFixed(2),
      );

      return HealthActivityData(
        steps: totalSteps,
        activeMinutes: totalActiveMinutes,
        activeCalories: totalActiveCalories,
        motionKm: motionKm,
        isAuthorized: authorized,
        isAvailable: true,
      );
    } catch (e) {
      debugPrint('HealthService fetchActivityData error: $e');
      return HealthActivityData(
        steps: totalSteps,
        activeMinutes: totalActiveMinutes,
        activeCalories: totalActiveCalories,
        motionKm: totalMotionMeters / 1000.0,
        isAuthorized: authorized,
        isAvailable: true,
        errorMessage: e.toString(),
      );
    }
  }
}
