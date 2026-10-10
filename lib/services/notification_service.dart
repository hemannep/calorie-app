import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_state.dart';
import '../core/milestones.dart';

class ReminderRequest {
  const ReminderRequest(
    this.id,
    this.title,
    this.body,
    this.at, {
    this.weekly = false,
    this.repeat = true,
  });
  final int id;
  final String title, body;
  final tz.TZDateTime at;
  final bool weekly, repeat;
}

abstract class NotificationDriver {
  bool get supported;
  Future<void> initialize();
  Future<bool> permitted();
  Future<bool> requestPermission();
  Future<void> refreshTimezone();
  Future<void> cancelAll();
  Future<void> cancel(int id);
  Future<void> schedule(ReminderRequest request);
  Future<void> show(int id, String title, String body);
}

class DeviceNotificationDriver implements NotificationDriver {
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  @override
  bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'kayleo_care_v1',
      'Reminders & celebrations',
      channelDescription:
          'Meal check-ins, hydration, weekly reviews and earned milestones',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
    ),
  );
  @override
  Future<void> initialize() async {
    if (initialized || !supported) return;
    tzdata.initializeTimeZones();
    await refreshTimezone();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    initialized = true;
  }

  @override
  Future<void> refreshTimezone() async {
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
  }

  @override
  Future<bool> permitted() async {
    if (!supported) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }
    return (await plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.checkPermissions())
            ?.isEnabled ??
        false;
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true, badge: false) ??
        false;
  }

  @override
  Future<void> cancelAll() => plugin.cancelAll();
  @override
  Future<void> cancel(int id) => plugin.cancel(id: id);
  @override
  Future<void> show(int id, String title, String body) => plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: details,
  );
  @override
  Future<void> schedule(ReminderRequest r) => plugin.zonedSchedule(
    id: r.id,
    title: r.title,
    body: r.body,
    scheduledDate: r.at,
    notificationDetails: details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: !r.repeat
        ? null
        : r.weekly
        ? DateTimeComponents.dayOfWeekAndTime
        : DateTimeComponents.time,
  );
}

List<ReminderRequest> reminderPlan(
  Map<String, bool> preferences,
  tz.TZDateTime now,
) {
  tz.TZDateTime next(int hour, int minute, {int? weekday}) {
    var at = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!at.isAfter(now)) {
      at = tz.TZDateTime(
        now.location,
        at.year,
        at.month,
        at.day + 1,
        hour,
        minute,
      );
    }
    if (weekday != null) {
      while (at.weekday != weekday) {
        at = tz.TZDateTime(
          now.location,
          at.year,
          at.month,
          at.day + 1,
          hour,
          minute,
        );
      }
    }
    return at;
  }

  return [
    if (preferences['Meal reminders'] == true) ...[
      ReminderRequest(
        10,
        'A little meal check-in',
        'Whenever you’re ready, add your meal to Kayleo.',
        next(12, 30),
      ),
      ReminderRequest(
        11,
        'How was your day?',
        'Take a moment to record your meals, at your own pace.',
        next(19, 30),
      ),
    ],
    if (preferences['Hydration reminders'] == true)
      for (final hour in [10, 14, 18])
        ReminderRequest(
          12 + [10, 14, 18].indexOf(hour),
          'Time for water?',
          'A gentle reminder to take a sip and log your water.',
          next(hour, 0),
        ),
    if (preferences['Weekly review'] == true)
      ReminderRequest(
        15,
        'Your week has a story',
        'See your check-ins and celebrate your progress in Kayleo.',
        next(18, 0, weekday: DateTime.sunday),
        weekly: true,
      ),
  ];
}

const _smartNudgeMessages = <(String, String)>[
  ('A small win counts', 'Log one meal today and keep your momentum going.'),
  (
    'Make your next choice easier',
    'Add a meal or save a favorite so future logging takes less time.',
  ),
  (
    'Check in with yourself',
    'How hungry, energized, or satisfied do you feel right now?',
  ),
  (
    'Progress, not perfection',
    'One useful choice is enough for this moment. Kayleo is here when you are.',
  ),
  (
    'A quick hydration check',
    'Take a sip and see whether your water goal needs a little attention.',
  ),
  (
    'Your future self will thank you',
    'A quick food or water check-in now can make the rest of the day clearer.',
  ),
  (
    'Keep the streak gentle',
    'Consistency grows from small check-ins, not perfect days.',
  ),
];

List<ReminderRequest> smartNudgePlan(
  Map<String, bool> preferences,
  tz.TZDateTime now, {
  String seed = '',
}) {
  if (preferences['Smart nudges'] != true) return const [];
  var hash = seed.codeUnits.fold<int>(
    17,
    (value, code) => (value * 31 + code) & 0x7fffffff,
  );
  final requests = <ReminderRequest>[];
  for (var day = 0; day < 7; day++) {
    for (var slot = 0; slot < 2; slot++) {
      hash = (hash * 1103515245 + 12345) & 0x7fffffff;
      final hour = 9 + (hash % 11); // 9 AM–7 PM, always outside quiet hours.
      hash = (hash * 1103515245 + 12345) & 0x7fffffff;
      final minute = (hash % 4) * 15;
      var at = tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day + day,
        hour,
        minute,
      );
      if (!at.isAfter(now)) continue;
      final message =
          _smartNudgeMessages[(day * 2 + slot) % _smartNudgeMessages.length];
      requests.add(
        ReminderRequest(
          200 + day * 2 + slot,
          message.$1,
          message.$2,
          at,
          repeat: false,
        ),
      );
    }
  }
  return requests;
}

tz.TZDateTime? celebrationTime(tz.TZDateTime now, bool quiet) {
  if (!quiet || (now.hour >= 8 && now.hour < 21)) return null;
  return tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day + (now.hour >= 21 ? 1 : 0),
    8,
  );
}

class NotificationService extends ChangeNotifier {
  NotificationService({
    NotificationDriver? driver,
    tz.TZDateTime Function()? clock,
  }) : driver = driver ?? DeviceNotificationDriver(),
       clock = clock ?? (() => tz.TZDateTime.now(tz.local));
  static final instance = NotificationService();
  static const ownerKey = 'kayleo_notification_owner_v1';
  final NotificationDriver driver;
  final tz.TZDateTime Function() clock;
  AppState? _state;
  bool _attached = false, _disposed = false;
  Future<void> _queue = Future.value();
  String? _signature;
  bool allowed = false;
  String? error;
  bool get supported => driver.supported;
  Future<void> get settled => _queue;
  void attach(AppState? state) {
    if (_attached && identical(_state, state)) return;
    _attached = true;
    _state?.removeListener(_changed);
    _state = state;
    _signature = null;
    state?.addListener(_changed);
    _enqueue(clear: true);
  }

  void _changed() => _enqueue();
  void refresh() => _enqueue(refreshZone: true);
  void _enqueue({bool clear = false, bool refreshZone = false}) {
    _queue = _queue.then((_) async {
      if (!supported || _disposed) return;
      try {
        await driver.initialize();
        if (clear) {
          final storage =
              _state?.storage ?? await SharedPreferences.getInstance();
          final owner = _state?.signedOut == true ? null : _state?.recordKey;
          if (owner == null || storage.getString(ownerKey) != owner) {
            await driver.cancelAll();
          }
          if (owner == null) {
            await storage.remove(ownerKey);
          } else if (!await storage.setString(ownerKey, owner)) {
            throw StateError('Notification account could not be saved');
          }
        }
        if (refreshZone) {
          await driver.refreshTimezone();
          _signature = null;
        }
        await _sync();
        error = null;
      } catch (_) {
        _signature = null;
        error = 'Device notifications could not be updated. Try again.';
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _sync() async {
    final state = _state;
    allowed = await driver.permitted();
    if (state == null || state.signedOut) {
      await driver.cancelAll();
      _signature = null;
      return;
    }
    await state.writesComplete;
    if (state != _state || state.storageError != null) return;
    final enabled =
        state.onboarded &&
        state.preferences['Device notifications'] == true &&
        allowed;
    final signature =
        '${state.recordKey}|$enabled|${state.preferences}|${tz.local.name}|${state.milestoneUnlocks.keys.join(',')}';
    if (signature != _signature) {
      for (var id = 10; id <= 15; id++) {
        await driver.cancel(id);
      }
      for (var id = 200; id < 214; id++) {
        await driver.cancel(id);
      }
      for (var i = 0; i < milestones.length; i++) {
        if (!enabled ||
            state.preferences['Milestone celebrations'] != true ||
            !state.milestoneUnlocks.containsKey(milestones[i].id)) {
          await driver.cancel(1000 + i);
        }
      }
      if (enabled) {
        for (final request in reminderPlan(state.preferences, clock())) {
          await driver.schedule(request);
        }
        for (final request in smartNudgePlan(
          state.preferences,
          clock(),
          seed: state.recordKey,
        )) {
          await driver.schedule(request);
        }
      }
      _signature = signature;
    }
    var changed = false;
    for (final id in List<String>.of(state.milestoneNotices)) {
      if (state != _state || state.signedOut) break;
      if (state.notifiedMilestones.contains(id)) continue;
      final index = milestones.indexWhere((m) => m.id == id);
      if (index < 0) continue;
      final m = milestones[index];
      if (enabled && state.preferences['Milestone celebrations'] == true) {
        final at = celebrationTime(
          clock(),
          state.preferences['Quiet hours'] == true,
        );
        if (at == null) {
          await driver.show(
            1000 + index,
            'Well done! ${m.title}',
            m.compliment,
          );
        } else {
          await driver.schedule(
            ReminderRequest(
              1000 + index,
              'Well done! ${m.title}',
              m.compliment,
              at,
              repeat: false,
            ),
          );
        }
      } else if (state.preferences['Device notifications'] == true &&
          !allowed) {
        continue;
      }
      state.notifiedMilestones.add(id);
      changed = true;
    }
    if (changed) await state.persist();
  }

  Future<bool> enable(AppState state) async {
    if (!supported) return false;
    try {
      await settled;
      await driver.initialize();
      allowed = await driver.requestPermission();
      if (allowed) {
        error = null;
        state.preferences['Device notifications'] = true;
        await state.persist();
        refresh();
        await settled;
      } else {
        error = 'Notifications are blocked. Allow Kayleo notifications in device settings, then try again.';
      }
    } catch (_) {
      allowed = false;
      error = 'Device notifications could not be enabled. Try again.';
    }
    if (!_disposed) notifyListeners();
    return allowed && error == null;
  }

  Future<bool> sendTest(AppState state) async {
    if (!await enable(state)) return false;
    try {
      await driver.show(
        99,
        'Hello from Kayleo',
        'Your device notifications are working. You’re all set!',
      );
      return true;
    } catch (_) {
      error = 'The test notification could not be sent. Try again.';
      if (!_disposed) notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _state?.removeListener(_changed);
    _state = null;
    super.dispose();
  }
}
