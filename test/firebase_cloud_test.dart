import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/firebase_auth_repository.dart';
import 'package:calorie_app/core/meal_engine.dart';
import 'package:calorie_app/services/cloud_sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCloud implements CloudDiaryBackend {
  @override
  String? currentUid = 'alice';
  bool fail = false;
  final updates = StreamController<CloudDiarySnapshot>.broadcast();
  final saved = <String, Map<String, String>>{};
  @override
  Stream<CloudDiarySnapshot> watch(String uid) => updates.stream;
  @override
  Future<void> write(String uid, Map<String, String?> records) async {
    if (fail) throw StateError('Offline');
    final data = saved.putIfAbsent(uid, () => {});
    for (final e in records.entries) {
      if (e.value == null) {
        data.remove(e.key);
      } else {
        data[e.key] = e.value!;
      }
    }
  }
}

Future<void> drain(CloudSyncService service) async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
    await service.settled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<AppState> fresh(String key) async {
    final s = await AppState.load(recordKey: key);
    addTearDown(s.dispose);
    await s.completeOnboarding(s.profile);
    return s;
  }

  test(
    'cloud diary restores nutrition and hydration while photos stay local',
    () async {
      final source = await fresh('source');
      final meal = MealEngine.parse('100 g rice').meal;
      meal.photo = Uint8List.fromList([1, 2, 3]);
      await source.saveMeal(meal);
      await source.recordDrink(350);
      await source.addActivity(15);
      final records = CloudDiaryCodec.encode(source);
      expect(records.values.join(), isNot(contains('AQID')));
      expect(records.keys.where((k) => k.startsWith('meals:')), hasLength(1));
      final destination = await fresh('destination');
      destination.accountEmail = 'other@example.test';
      await destination.applyCloudSnapshot(
        CloudDiaryCodec.merge(destination, records),
      );
      expect(destination.accountEmail, 'other@example.test');
      expect(
        destination.meals.single.items.single.foodId,
        source.meals.single.items.single.foodId,
      );
      expect(destination.meals.single.photo, null);
      expect(destination.waterFor(DateTime.now()), 350);
      expect(destination.activityMinutes, source.activityMinutes);
      await source.applyCloudSnapshot(CloudDiaryCodec.merge(source, records));
      expect(source.meals.single.photo, [1, 2, 3]);
    },
  );

  test(
    'invalid remote profile cannot partially replace or erase local diary',
    () async {
      final state = await fresh('atomic');
      await state.saveMeal(MealEngine.parse('100 g rice').meal);
      final before = jsonEncode(state.toJson());
      final malformed = state.toJson();
      malformed['profile'] = {...state.profile.toJson(), 'height': -1};
      malformed['meals'] = [];
      await expectLater(
        state.applyCloudSnapshot(malformed),
        throwsFormatException,
      );
      expect(jsonEncode(state.toJson()), before);
      final restored = await AppState.load(recordKey: 'atomic');
      addTearDown(restored.dispose);
      expect(restored.meals, hasLength(1));
    },
  );

  test(
    'remote meal deletion removes cached item and sample data is excluded',
    () async {
      final state = await fresh('delete');
      await state.saveMeal(MealEngine.parse('100 g rice').meal);
      final records = CloudDiaryCodec.encode(state)
        ..removeWhere((k, _) => k.startsWith('meals:'));
      await state.applyCloudSnapshot(CloudDiaryCodec.merge(state, records));
      expect(state.meals, isEmpty);
      state.seedDemo();
      expect(CloudDiaryCodec.encode(state), isEmpty);
    },
  );

  test('offline edits survive restart and sign-out; another UID cannot upload them', () async {
    final state = await fresh('alice-local');
    state.accountUid = 'alice';
    final backend = FakeCloud()..fail = true;
    final first = CloudSyncService(backend: backend)..attach(state);
    await drain(first);
    await state.recordDrink(425);
    await first.prepareSignOut();
    await drain(first);
    expect(state.cloudStatus, contains('local diary'));
    expect(
      state.storage.getString('kayleo_cloud_outbox_alice_v1'),
      contains('425'),
    );
    first.attach(null);
    backend.currentUid = 'bob';
    final bob = await fresh('bob-local');
    bob.accountUid = 'bob';
    final second = CloudSyncService(backend: backend)..attach(bob);
    backend.fail = false;
    await drain(second);
    expect(backend.saved['bob']?.values.join(), isNot(contains('425')));
    second.attach(null);
    backend.currentUid = 'alice';
    final restored = await AppState.load(recordKey: 'alice-local');
    restored.accountUid = 'alice';
    addTearDown(restored.dispose);
    final third = CloudSyncService(backend: backend)..attach(restored);
    await drain(third);
    expect(backend.saved['alice']!.values.join(), contains('425'));
    expect(
      jsonDecode(
        restored.storage.getString('kayleo_cloud_outbox_alice_v1')!,
      )['pending'],
      isEmpty,
    );
    third.attach(null);
    await backend.updates.close();
  });

  test('cached partial snapshots cannot erase local records; independent remote meals merge', () async {
    final state = await fresh('merge-local');
    state.accountUid = 'alice';
    final localMeal = MealEngine.parse('100 g rice').meal;
    await state.saveMeal(localMeal);
    final backend = FakeCloud()..fail = true;
    final service = CloudSyncService(backend: backend)..attach(state);
    await drain(service);
    backend.updates.add(const CloudDiarySnapshot({}, fromCache: true));
    await drain(service);
    expect(state.meals, hasLength(1));
    expect(state.cloudStatus, isNot('Cloud backup up to date'));
    final remote = await fresh('remote');
    await remote.saveMeal(MealEngine.parse('100 g chicken').meal);
    backend.updates.add(CloudDiarySnapshot(CloudDiaryCodec.encode(remote)));
    await drain(service);
    expect(state.meals, hasLength(2));
    expect(state.meals.any((m) => m.id == localMeal.id), true);
    service.attach(null);
    await backend.updates.close();
  });

  test(
    'Firebase errors give actionable messages without credential details',
    () {
      expect(
        authErrorMessage(FirebaseAuthException(code: 'invalid-credential')),
        contains('incorrect'),
      );
      expect(
        authErrorMessage(FirebaseAuthException(code: 'email-already-in-use')),
        contains('reset'),
      );
      expect(
        authErrorMessage(FirebaseAuthException(code: 'network-request-failed')),
        contains('connection'),
      );
      expect(
        authErrorMessage(
          FirebaseAuthException(code: 'unknown', message: 'secret internals'),
        ),
        isNot(contains('secret')),
      );
    },
  );
}
