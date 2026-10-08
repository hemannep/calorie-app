import 'dart:convert';

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/meal_engine.dart';
import 'package:calorie_app/core/milestones.dart';
import 'package:calorie_app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class FakeNotifications implements NotificationDriver {
  @override
  bool supported = true;
  bool permission = true, fail = false;
  int requests = 0, clears = 0;
  final pending = <int, ReminderRequest>{};
  final shown = <int>[];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refreshTimezone() async {}
  @override
  Future<bool> permitted() async => permission;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return permission;
  }

  @override
  Future<void> cancelAll() async {
    clears++;
    pending.clear();
  }

  @override
  Future<void> cancel(int id) async {
    pending.remove(id);
  }

  @override
  Future<void> schedule(ReminderRequest r) async {
    if (fail) throw StateError('OS unavailable');
    pending[r.id] = r;
  }

  @override
  Future<void> show(int id, String title, String body) async {
    if (fail) throw StateError('OS unavailable');
    shown.add(id);
  }
}

Future<AppState> fresh({String key = AppState.storageKey}) async {
  final s = await AppState.load(recordKey: key);
  await s.completeOnboarding(s.profile);
  addTearDown(s.dispose);
  return s;
}

Future<void> drain(NotificationService s) async {
  for (var i = 0; i < 3; i++) {
    await s.settled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kathmandu'));
  });
  test('21 unique milestones all have compliments', () {
    expect(milestones.length, 21);
    expect(milestones.map((m) => m.id).toSet().length, 21);
    expect(
      milestones.every((m) => m.target > 0 && m.compliment.isNotEmpty),
      isTrue,
    );
  });
  test(
    'Unlocks and compliments persist once despite edits and deletion',
    () async {
      final s = await fresh();
      final m = MealEngine.parse('100 g rice').meal;
      await s.saveMeal(m);
      await s.saveMeal(m);
      await s.persist();
      expect(s.milestoneNotices, ['meal1']);
      final restored = await AppState.load();
      addTearDown(restored.dispose);
      await restored.deleteMeal(m.id);
      await restored.saveMeal(m);
      expect(restored.milestoneNotices, ['meal1']);
      expect(restored.milestoneUnlocks, contains('meal1'));
    },
  );
  test('Sample records do not earn milestones, personal records do', () async {
    final s = await fresh();
    s.seedDemo();
    await s.persist();
    expect(s.milestoneUnlocks, isEmpty);
    expect(s.milestoneCounts.values.every((v) => v == 0), isTrue);
    await s.saveMeal(MealEngine.parse('100 g rice').meal);
    expect(s.milestoneNotices, ['meal1']);
  });
  test('Historical logs migrate silently', () async {
    final s = await fresh();
    s.meals.add(MealEngine.parse('100 g rice').meal);
    final old = s.toJson()
      ..remove('milestoneUnlocks')
      ..remove('milestoneNotices')
      ..remove('notifiedMilestones');
    await s.storage.setString(s.recordKey, jsonEncode(old));
    final restored = await AppState.load();
    addTearDown(restored.dispose);
    expect(restored.milestoneUnlocks, contains('meal1'));
    expect(restored.milestoneNotices, isEmpty);
    for (var i = 0; i < 4; i++) {
      await restored.saveMeal(
        MealEngine.parse('100 g rice').meal.copy(id: 'new-$i'),
      );
    }
    expect(restored.milestoneNotices, ['meal5']);
  });
  test('Calendar-day best streak and hydration goal days', () async {
    final s = await fresh();
    for (var i = 0; i < 3; i++) {
      final m = MealEngine.parse('100 g rice').meal.copy(id: 'day-$i');
      m.time = DateTime(2026, 3, 7 + i);
      await s.saveMeal(m);
      await s.addWater(s.profile.waterTarget, date: m.time);
    }
    expect(s.milestoneCounts['streak'], 3);
    expect(s.milestoneCounts['water'], 3);
    expect(
      s.milestoneUnlocks.keys,
      containsAll(['days3', 'streak3', 'water1', 'water3']),
    );
  });
  test(
    'Schedules use next local occurrence and Sunday with six bounded reminders',
    () {
      final now = tz.TZDateTime(tz.local, 2026, 10, 8, 20);
      final plan = reminderPlan({
        'Meal reminders': true,
        'Hydration reminders': true,
        'Weekly review': true,
      }, now);
      expect(plan.length, 6);
      expect(
        plan.every(
          (r) => r.at.isAfter(now) && r.at.location.name == 'Asia/Kathmandu',
        ),
        isTrue,
      );
      expect(plan.where((r) => r.weekly).single.at.weekday, DateTime.sunday);
      expect(reminderPlan({}, now), isEmpty);
    },
  );
  test('DST keeps local wall-clock schedule', () {
    final zone = tz.getLocation('America/New_York');
    final plan = reminderPlan({
      'Meal reminders': true,
    }, tz.TZDateTime(zone, 2026, 3, 7, 20));
    expect(plan.first.at.day, 8);
    expect(plan.first.at.hour, 12);
    expect(plan.first.at.minute, 30);
    expect(plan.first.at.timeZoneOffset, const Duration(hours: -4));
  });
  test('Quiet hours defer to 8 AM', () {
    final now = tz.TZDateTime(tz.local, 2026, 10, 8, 22);
    expect(celebrationTime(now, true)!.day, 9);
    expect(celebrationTime(now, true)!.hour, 8);
    expect(celebrationTime(now, false), isNull);
    expect(
      celebrationTime(tz.TZDateTime(tz.local, 2026, 10, 9, 8), true),
      isNull,
    );
  });
  test('No unsolicited permission request; denial is surfaced', () async {
    final s = await fresh();
    final d = FakeNotifications()..permission = false;
    final n = NotificationService(driver: d);
    n.attach(s);
    await drain(n);
    expect(d.requests, 0);
    expect(await n.enable(s), isFalse);
    expect(n.error, contains('blocked'));
    expect(d.pending, isEmpty);
    n.dispose();
  });
  test('Enable and category toggles reconcile; sign-out cancels', () async {
    final s = await fresh();
    final d = FakeNotifications();
    final n = NotificationService(driver: d);
    n.attach(s);
    await drain(n);
    await n.enable(s);
    await drain(n);
    expect(d.pending.keys, unorderedEquals([10, 11, 15]));
    s.preferences['Meal reminders'] = false;
    s.preferences['Hydration reminders'] = true;
    await s.persist();
    await drain(n);
    expect(d.pending.keys, unorderedEquals([12, 13, 14, 15]));
    s.markSignedOut();
    await drain(n);
    expect(d.pending, isEmpty);
    n.dispose();
  });
  test('Milestone device notification sends once and reset cancels', () async {
    final s = await fresh();
    final d = FakeNotifications();
    final n = NotificationService(
      driver: d,
      clock: () => tz.TZDateTime(tz.local, 2026, 10, 8, 12),
    );
    n.attach(s);
    await drain(n);
    await n.enable(s);
    await s.saveMeal(MealEngine.parse('100 g rice').meal);
    await drain(n);
    expect(d.shown, [1000]);
    n.refresh();
    await drain(n);
    expect(d.shown, [1000]);
    expect(s.notifiedMilestones, {'meal1'});
    await s.reset();
    await drain(n);
    expect(d.pending, isEmpty);
    expect(s.milestoneNotices, isEmpty);
    n.dispose();
  });
  test('Deferred milestone survives app restart for same account', () async {
    final s = await fresh();
    final d = FakeNotifications();
    tz.TZDateTime clock() => tz.TZDateTime(tz.local, 2026, 10, 8, 22);
    final n = NotificationService(driver: d, clock: clock);
    n.attach(s);
    await drain(n);
    await n.enable(s);
    await s.saveMeal(MealEngine.parse('100 g rice').meal);
    await drain(n);
    expect(d.pending[1000]!.repeat, isFalse);
    final clears = d.clears;
    n.dispose();
    final restored = await AppState.load();
    addTearDown(restored.dispose);
    final next = NotificationService(driver: d, clock: clock);
    next.attach(restored);
    await drain(next);
    expect(d.clears, clears);
    expect(d.pending[1000], isNotNull);
    restored.preferences['Milestone celebrations'] = false;
    await restored.persist();
    await drain(next);
    expect(d.pending, isNot(contains(1000)));
    next.dispose();
  });
  test('Account switch cancels old reminders', () async {
    final a = await fresh(key: 'one'), b = await fresh(key: 'two');
    final d = FakeNotifications();
    final n = NotificationService(driver: d);
    n.attach(a);
    await drain(n);
    await n.enable(a);
    expect(d.pending, isNotEmpty);
    n.attach(b);
    await drain(n);
    expect(d.pending, isEmpty);
    n.dispose();
  });
  test('OS failures retry and do not mark undelivered milestones', () async {
    final s = await fresh();
    final d = FakeNotifications();
    final n = NotificationService(
      driver: d,
      clock: () => tz.TZDateTime(tz.local, 2026, 10, 8, 12),
    );
    n.attach(s);
    await drain(n);
    await n.enable(s);
    d.fail = true;
    await s.saveMeal(MealEngine.parse('100 g rice').meal);
    await drain(n);
    expect(n.error, isNotNull);
    expect(s.notifiedMilestones, isEmpty);
    d.fail = false;
    n.refresh();
    await drain(n);
    expect(d.shown, [1000]);
    expect(n.error, isNull);
    n.dispose();
  });
  test('Unsupported platforms retain inbox without native calls', () async {
    final s = await fresh();
    final d = FakeNotifications()..supported = false;
    final n = NotificationService(driver: d);
    n.attach(s);
    await drain(n);
    expect(await n.enable(s), isFalse);
    await s.saveMeal(MealEngine.parse('100 g rice').meal);
    await drain(n);
    expect(s.milestoneNotices, ['meal1']);
    expect(d.requests, 0);
    expect(d.shown, isEmpty);
    n.dispose();
  });
}
