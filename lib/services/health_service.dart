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
    this.basalCalories = 0,
    this.floorsClimbed = 0,
    this.heartRateAvg = 0,
    this.isAuthorized = false,
    this.isAvailable = true,
    this.errorMessage,
    this.rawActiveMinutes = false,
    this.rawActiveCalories = false,
    this.rawDistance = false,
  });

  final int steps;
  final int activeMinutes;
  final int activeCalories;
  final double motionKm;

  /// Basal (resting) energy burned in kcal today from HealthKit / Health Connect.
  final int basalCalories;

  /// Flights of stairs climbed (iOS HealthKit).
  final int floorsClimbed;

  /// Average resting heart rate in bpm (0 if unavailable).
  final int heartRateAvg;
  final bool isAuthorized;
  final bool isAvailable;
  final String? errorMessage;

  /// Whether activeMinutes came directly from the health app (true) or was estimated from steps (false).
  final bool rawActiveMinutes;

  /// Whether activeCalories came directly from the health app (true) or was estimated from steps (false).
  final bool rawActiveCalories;

  /// Whether motionKm came directly from the health app (true) or was estimated from steps (false).
  final bool rawDistance;

  /// Total calories burned today = basal metabolism + activity calories.
  int get totalCaloriesBurned => basalCalories + activeCalories;

  HealthActivityData copyWith({
    int? steps,
    int? activeMinutes,
    int? activeCalories,
    double? motionKm,
    int? basalCalories,
    int? floorsClimbed,
    int? heartRateAvg,
    bool? isAuthorized,
    bool? isAvailable,
    String? errorMessage,
    bool? rawActiveMinutes,
    bool? rawActiveCalories,
    bool? rawDistance,
  }) => HealthActivityData(
    steps: steps ?? this.steps,
    activeMinutes: activeMinutes ?? this.activeMinutes,
    activeCalories: activeCalories ?? this.activeCalories,
    motionKm: motionKm ?? this.motionKm,
    basalCalories: basalCalories ?? this.basalCalories,
    floorsClimbed: floorsClimbed ?? this.floorsClimbed,
    heartRateAvg: heartRateAvg ?? this.heartRateAvg,
    isAuthorized: isAuthorized ?? this.isAuthorized,
    isAvailable: isAvailable ?? this.isAvailable,
    errorMessage: errorMessage ?? this.errorMessage,
    rawActiveMinutes: rawActiveMinutes ?? this.rawActiveMinutes,
    rawActiveCalories: rawActiveCalories ?? this.rawActiveCalories,
    rawDistance: rawDistance ?? this.rawDistance,
  );

  static const zero = HealthActivityData();

  // ── Step-based estimation helpers ──────────────────────────────────
  // Used as fallback when the health app reports steps but not the
  // specific metric. Based on standard exercise physiology averages.

  /// Estimate active minutes from steps.
  /// Average walking cadence ≈ 100 steps/min.
  static int estimateActiveMinutesFromSteps(int steps) {
    if (steps <= 0) return 0;
    return (steps / 100).round().clamp(0, 1440);
  }

  /// Estimate active calories from steps.
  /// Average person burns ~0.04 kcal per step walking (≈ 40 cal / 1000 steps).
  static int estimateActiveCaloriesFromSteps(int steps) {
    if (steps <= 0) return 0;
    return (steps * 0.04).round();
  }

  /// Estimate distance in km from steps.
  /// Average stride length ≈ 0.762 m (30 inches).
  static double estimateDistanceKmFromSteps(int steps) {
    if (steps <= 0) return 0.0;
    return double.parse((steps * 0.000762).toStringAsFixed(2));
  }
}

/// Service to connect and synchronize daily fitness and motion data
/// directly with Apple Health (iOS), Health Connect (Android), and the
/// phone's built-in hardware step counter sensor on Android.
class HealthService extends ChangeNotifier {
  HealthService({Health? health}) : _health = health ?? Health();

  static HealthService instance = HealthService();

  static const String healthConnectedPrefKey = 'kayleo_health_connected';

  final Health _health;
  static const _platformChannel = MethodChannel('kayleo/health');
  bool _configured = false;
  bool _channelListening = false;
  bool _promptedSensorOnce = false;
  final Map<String, Future<HealthActivityData>> _inFlight = {};
  final Map<String, (DateTime, HealthActivityData)> _cache = {};

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
        HealthDataType.BASAL_ENERGY_BURNED,
        HealthDataType.EXERCISE_TIME,
        HealthDataType.DISTANCE_WALKING_RUNNING,
        HealthDataType.FLIGHTS_CLIMBED,
        HealthDataType.HEART_RATE,
      ];
    } else if (Platform.isAndroid) {
      return const [
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.BASAL_ENERGY_BURNED,
        HealthDataType.HEART_RATE,
        HealthDataType.DISTANCE_DELTA,
        HealthDataType.WORKOUT,
      ];
    }
    return const [];
  }

  Future<void> _ensureConfigured() async {
    if (!isPlatformSupported) return;
    if (!_channelListening && !kIsWeb && Platform.isAndroid) {
      try {
        _platformChannel.setMethodCallHandler(_handleNativeCall);
        _channelListening = true;
      } catch (_) {}
    }
    if (_configured) return;
    try {
      await _health.configure();
      _configured = true;
    } catch (e) {
      debugPrint('HealthService configure error: $e');
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onStepsChanged') {
      final now = DateTime.now();
      final todayKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final newSteps = call.arguments is int ? call.arguments as int : null;
      final cached = _cache[todayKey];
      if (newSteps != null && cached != null && newSteps > cached.$2.steps) {
        final prev = cached.$2;
        final min = prev.rawActiveMinutes
            ? prev.activeMinutes
            : HealthActivityData.estimateActiveMinutesFromSteps(newSteps);
        final cal = prev.rawActiveCalories
            ? prev.activeCalories
            : HealthActivityData.estimateActiveCaloriesFromSteps(newSteps);
        final km = prev.rawDistance
            ? prev.motionKm
            : HealthActivityData.estimateDistanceKmFromSteps(newSteps);
        _cache[todayKey] = (
          now,
          prev.copyWith(
            steps: newSteps,
            activeMinutes: min,
            activeCalories: cal,
            motionKm: km,
            isAuthorized: true,
          ),
        );
      } else {
        _cache.remove(todayKey);
      }
      notifyListeners();
    }
  }

  Future<bool> _hasHealthConnectPermissions() async {
    try {
      const types = [HealthDataType.STEPS];
      const permissions = [HealthDataAccess.READ];
      final has = await _health.hasPermissions(types, permissions: permissions);
      return has == true;
    } catch (e) {
      debugPrint('HealthService _hasHealthConnectPermissions error: $e');
      return false;
    }
  }

  Future<bool> _hasSensorPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _platformChannel.invokeMethod<bool>('hasSensorPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _requestSensorPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _platformChannel.invokeMethod<bool>(
            'requestSensorPermission',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<int> _getHardwareSteps(String dateKey, bool isToday) async {
    if (kIsWeb || !Platform.isAndroid) return 0;
    try {
      return await _platformChannel.invokeMethod<int>('getDailySteps', {
            'date': dateKey,
            'isToday': isToday,
          }) ??
          0;
    } catch (_) {
      return 0;
    }
  }

  /// Check whether health permissions have been granted.
  Future<bool> hasPermissions() async {
    if (mockIsAuthorized != null) return mockIsAuthorized!;
    if (!isPlatformSupported) return false;
    await _ensureConfigured();
    try {
      if (Platform.isAndroid) {
        final results = await Future.wait([
          _hasHealthConnectPermissions(),
          _hasSensorPermission(),
        ]);
        return results[0] || results[1];
      }
      final types = dataTypes;
      if (types.isEmpty) return false;
      final permissions = List.filled(types.length, HealthDataAccess.READ);
      final has = await _health.hasPermissions(types, permissions: permissions);
      return has == true;
    } catch (e) {
      debugPrint('HealthService hasPermissions error: $e');
      return false;
    }
  }

  /// Request user authorization for HealthKit or Health Connect + phone step sensor.
  Future<bool> requestPermissions() async {
    if (mockIsAuthorized != null) return mockIsAuthorized!;
    if (!isPlatformSupported) return false;
    await _ensureConfigured();
    try {
      var sensorOk = false;
      var healthConnectOk = false;
      if (Platform.isAndroid) {
        sensorOk = await _requestSensorPermission();
        final available = await isHealthConnectAvailable();
        if (available) {
          final types = dataTypes;
          final permissions = List.filled(types.length, HealthDataAccess.READ);
          try {
            healthConnectOk = await _health.requestAuthorization(
              types,
              permissions: permissions,
            );
          } catch (e) {
            debugPrint('HealthService Health Connect auth error: $e');
          }
        } else if (!sensorOk) {
          await installHealthConnect();
          return false;
        }
        final ok = sensorOk || healthConnectOk;
        if (ok) {
          _cache.clear();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(healthConnectedPrefKey, true);
        }
        return ok;
      }
      final types = dataTypes;
      if (types.isEmpty) return false;
      final permissions = List.filled(types.length, HealthDataAccess.READ);
      final ok = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
      if (ok) {
        _cache.clear();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(healthConnectedPrefKey, true);
      }
      return ok;
    } catch (e) {
      debugPrint('HealthService requestAuthorization error: $e');
      return false;
    }
  }

  /// Fetch steps, active time, activity calories, distance, basal energy,
  /// heart rate, and flights climbed for a specific day.
  ///
  /// When the health app provides steps but not a specific metric (e.g. active
  /// calories), we derive a reasonable estimate from the step count using
  /// standard exercise physiology formulas. The `raw*` flags on the returned
  /// [HealthActivityData] indicate whether a value came directly from the
  /// health app (true) or was estimated from steps (false).
  Future<HealthActivityData> fetchActivityData(
    DateTime date, {
    AppState? state,
    bool forceRefresh = false,
  }) async {
    if (mockActivityData != null) {
      return mockActivityData!;
    }

    // When running in demo mode without real health hardware, provide sample activity
    // data so the user can experience the rings immediately.
    if ((state?.demo == true || !isPlatformSupported) &&
        mockActivityData == null) {
      final isDemo = state?.demo == true;
      final baseSteps = isDemo ? 7540 : 0;
      final baseMin = isDemo ? 38 : 0;
      final baseCal = isDemo ? 420 : 0;
      final baseMotion = isDemo ? 5.4 : 0.0;
      final baseBasal = isDemo ? 1650 : 0;
      final baseFloors = isDemo ? 8 : 0;
      final baseHr = isDemo ? 72 : 0;
      return HealthActivityData(
        steps: baseSteps,
        activeMinutes: baseMin,
        activeCalories: baseCal,
        motionKm: baseMotion,
        basalCalories: baseBasal,
        floorsClimbed: baseFloors,
        heartRateAvg: baseHr,
        isAuthorized: isDemo,
        isAvailable: isPlatformSupported,
        rawActiveMinutes: isDemo,
        rawActiveCalories: isDemo,
        rawDistance: isDemo,
      );
    }

    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final isSameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;

    if (!forceRefresh) {
      final cached = _cache[key];
      if (cached != null) {
        final ttl = isSameDay
            ? const Duration(seconds: 15)
            : const Duration(minutes: 5);
        if (now.difference(cached.$1) < ttl) {
          return cached.$2;
        }
      }
      final existing = _inFlight[key];
      if (existing != null) {
        return existing;
      }
    }

    final future = _fetchActivityDataInternal(date, now, isSameDay);
    _inFlight[key] = future;
    try {
      final result = await future;
      _cache[key] = (DateTime.now(), result);
      return result;
    } finally {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }
  }

  Future<HealthActivityData> _fetchActivityDataInternal(
    DateTime date,
    DateTime now,
    bool isSameDay,
  ) async {
    await _ensureConfigured();

    final prefs = await SharedPreferences.getInstance();
    final isConnectedPref = prefs.getBool(healthConnectedPrefKey) ?? false;

    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    var hasHealthConnectPerm = false;
    var hasSensorPerm = false;

    // Check authorization beforehand to avoid SecurityException on Android Health Connect
    if (Platform.isAndroid) {
      final perms = await Future.wait([
        _hasHealthConnectPermissions(),
        _hasSensorPermission(),
      ]);
      hasHealthConnectPerm = perms[0];
      hasSensorPerm = perms[1];
      if ((hasHealthConnectPerm || isConnectedPref) &&
          !hasSensorPerm &&
          !_promptedSensorOnce) {
        _promptedSensorOnce = true;
        hasSensorPerm = await _requestSensorPermission();
      }
      if (!hasHealthConnectPerm && !hasSensorPerm) {
        return const HealthActivityData(isAuthorized: false, isAvailable: true);
      }
    } else if (Platform.isIOS) {
      if (!isConnectedPref) {
        return const HealthActivityData(isAuthorized: false, isAvailable: true);
      }
      hasHealthConnectPerm = true;
    }

    final startTime = DateTime(date.year, date.month, date.day, 0, 0, 0);
    if (startTime.isAfter(now)) {
      return const HealthActivityData(isAuthorized: true, isAvailable: true);
    }
    final endTime = isSameDay
        ? now
        : DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    var totalSteps = 0;
    var totalActiveMinutes = 0;
    var totalActiveCalories = 0;
    var totalMotionMeters = 0.0;
    var totalBasalCalories = 0;
    var totalFloorsClimbed = 0;
    var heartRateSum = 0.0;
    var heartRateCount = 0;
    var authorized = true;

    // Track whether each metric came directly from the health API.
    var gotRawActiveMinutes = false;
    var gotRawActiveCalories = false;
    var gotRawDistance = false;

    try {
      if (hasHealthConnectPerm) {
        // 1. Fetch aggregate steps safely from HealthKit / Health Connect
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

        // 2. Fetch data points for remaining health types (skip raw STEPS if aggregate succeeded)
        final types = totalSteps > 0
            ? dataTypes.where((t) => t != HealthDataType.STEPS).toList()
            : dataTypes;
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
                    gotRawActiveCalories = true;
                    break;
                  case HealthDataType.BASAL_ENERGY_BURNED:
                    totalBasalCalories += numVal.round();
                    break;
                  case HealthDataType.EXERCISE_TIME:
                    totalActiveMinutes += numVal.round();
                    gotRawActiveMinutes = true;
                    break;
                  case HealthDataType.APPLE_MOVE_TIME:
                    totalActiveMinutes += (numVal / 60).round();
                    gotRawActiveMinutes = true;
                    break;
                  case HealthDataType.DISTANCE_DELTA:
                  case HealthDataType.DISTANCE_WALKING_RUNNING:
                    totalMotionMeters += numVal.toDouble();
                    gotRawDistance = true;
                    break;
                  case HealthDataType.FLIGHTS_CLIMBED:
                    totalFloorsClimbed += numVal.round();
                    break;
                  case HealthDataType.HEART_RATE:
                    heartRateSum += numVal.toDouble();
                    heartRateCount++;
                    break;
                  default:
                    break;
                }
              } else if (dp.type == HealthDataType.WORKOUT) {
                final durationMin = dp.dateTo.difference(dp.dateFrom).inMinutes;
                if (durationMin > 0) {
                  totalActiveMinutes += durationMin;
                  gotRawActiveMinutes = true;
                }
              }
            }
          } catch (e) {
            debugPrint('HealthService getHealthDataFromTypes error: $e');
          }
        }
      }

      // 2b. On Android, also read the phone's built-in hardware step counter
      // sensor so phones where Health Connect has 0 steps (e.g. Honor, Xiaomi,
      // Vivo, Oppo, or Samsung without Health Connect sync enabled) still
      // report accurate daily steps.
      if (Platform.isAndroid && hasSensorPerm) {
        final sensorSteps = await _getHardwareSteps(dateKey, isSameDay);
        if (sensorSteps > totalSteps) {
          totalSteps = sensorSteps;
        }
      }

      // 3. Step-based estimation fallbacks:
      // If we have steps but the health app didn't return a specific metric,
      // derive a reasonable estimate so the rings aren't stuck at zero.
      if (totalSteps > 0) {
        if (!gotRawActiveMinutes && totalActiveMinutes == 0) {
          totalActiveMinutes =
              HealthActivityData.estimateActiveMinutesFromSteps(totalSteps);
        }
        if (!gotRawActiveCalories && totalActiveCalories == 0) {
          totalActiveCalories =
              HealthActivityData.estimateActiveCaloriesFromSteps(totalSteps);
        }
        if (!gotRawDistance && totalMotionMeters == 0.0) {
          totalMotionMeters =
              HealthActivityData.estimateDistanceKmFromSteps(totalSteps) *
              1000.0;
          // motionMeters is converted to km below, so store in meters here
        }
      }

      final motionKm = double.parse(
        (totalMotionMeters / 1000.0).toStringAsFixed(2),
      );
      final avgHeartRate = heartRateCount > 0
          ? (heartRateSum / heartRateCount).round()
          : 0;

      return HealthActivityData(
        steps: totalSteps,
        activeMinutes: totalActiveMinutes,
        activeCalories: totalActiveCalories,
        motionKm: motionKm,
        basalCalories: totalBasalCalories,
        floorsClimbed: totalFloorsClimbed,
        heartRateAvg: avgHeartRate,
        isAuthorized: authorized,
        isAvailable: true,
        rawActiveMinutes: gotRawActiveMinutes,
        rawActiveCalories: gotRawActiveCalories,
        rawDistance: gotRawDistance,
      );
    } catch (e) {
      debugPrint('HealthService fetchActivityData error: $e');

      // Even on error, apply step-based fallbacks for whatever data we have.
      if (totalSteps > 0) {
        if (!gotRawActiveMinutes && totalActiveMinutes == 0) {
          totalActiveMinutes =
              HealthActivityData.estimateActiveMinutesFromSteps(totalSteps);
        }
        if (!gotRawActiveCalories && totalActiveCalories == 0) {
          totalActiveCalories =
              HealthActivityData.estimateActiveCaloriesFromSteps(totalSteps);
        }
        if (!gotRawDistance && totalMotionMeters == 0.0) {
          totalMotionMeters =
              HealthActivityData.estimateDistanceKmFromSteps(totalSteps) *
              1000.0;
        }
      }

      return HealthActivityData(
        steps: totalSteps,
        activeMinutes: totalActiveMinutes,
        activeCalories: totalActiveCalories,
        motionKm: totalMotionMeters / 1000.0,
        basalCalories: totalBasalCalories,
        floorsClimbed: totalFloorsClimbed,
        heartRateAvg: heartRateCount > 0
            ? (heartRateSum / heartRateCount).round()
            : 0,
        isAuthorized: authorized,
        isAvailable: true,
        errorMessage: e.toString(),
        rawActiveMinutes: gotRawActiveMinutes,
        rawActiveCalories: gotRawActiveCalories,
        rawDistance: gotRawDistance,
      );
    }
  }
}
