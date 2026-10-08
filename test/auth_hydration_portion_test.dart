import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/auth_repository.dart';
import 'package:calorie_app/core/meal_engine.dart';
import 'package:calorie_app/data/models.dart';
import 'package:calorie_app/data/food_database.dart';
import 'package:calorie_app/features/portion_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Demo registration restores session and never persists passwords',
    () async {
      final repo = DemoAuthRepository();
      final state = await repo.register(
        'Heman',
        'HEMAN@example.test',
        'dummy12',
      );
      await state.completeOnboarding(BodyProfile(name: 'Heman'));
      await state.recordDrink(350);
      final restored = await repo.restore();
      expect(restored!.profile.name, 'Heman');
      expect(restored.waterFor(DateTime.now()), 350);
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        expect(prefs.get(key).toString(), isNot(contains('dummy12')));
      }
      await repo.signOut();
      expect(await repo.restore(), null);
      final signedIn = await repo.signIn('heman@example.test', 'random9');
      expect(signedIn.waterFor(DateTime.now()), 350);
    },
  );
  test('Two demo accounts keep meals and water isolated', () async {
    final repo = DemoAuthRepository();
    final first = await repo.signIn('one@example.test', 'dummy12');
    await first.completeOnboarding(BodyProfile(name: 'One'));
    await first.saveMeal(MealEngine.parse('100 g rice').meal);
    await first.recordDrink(400);
    await repo.signOut();
    final second = await repo.register('Two', 'two@example.test', 'dummy12');
    expect(second.meals, isEmpty);
    expect(second.waterFor(DateTime.now()), 0);
    await second.recordDrink(200);
    await repo.signOut();
    final again = await repo.signIn('one@example.test', 'dummy77');
    expect(again.meals, hasLength(1));
    expect(again.waterFor(DateTime.now()), 400);
  });
  test('Legacy data is assigned to only its first account', () async {
    final legacy = await AppState.load();
    await legacy.completeOnboarding(BodyProfile());
    await legacy.recordDrink(250);
    final repo = DemoAuthRepository();
    final first = await repo.signIn('a@example.test', 'dummy12');
    expect(first.waterFor(DateTime.now()), 250);
    await repo.signOut();
    final second = await repo.signIn('b@example.test', 'dummy12');
    expect(second.waterFor(DateTime.now()), 0);
  });
  test(
    'Auth rejects malformed email, short password and duplicate registration',
    () async {
      final repo = DemoAuthRepository();
      await expectLater(repo.signIn('bad', 'dummy12'), throwsFormatException);
      await expectLater(
        repo.register('H', 'h@example.test', 'abc'),
        throwsFormatException,
      );
      await repo.register('H', 'h@example.test', 'dummy12');
      await expectLater(
        repo.register('H', 'h@example.test', 'dummy12'),
        throwsStateError,
      );
    },
  );
  test('Hydration edit, delete, undo, dates and goal survive reload', () async {
    final state = await AppState.load();
    final now = DateTime.now(),
        yesterday = DateTime(now.year, now.month, now.day - 1);
    final entry = await state.recordDrink(350);
    await state.recordDrink(500, date: yesterday);
    await state.recordDrink(450, replaceId: entry.id, date: entry.time);
    expect(state.drinksFor(now), hasLength(1));
    expect(state.waterFor(now), 450);
    await state.removeDrink(entry.id);
    expect(state.waterFor(now), 0);
    final removed = DrinkEntry(id: entry.id, time: entry.time, ml: 450);
    await state.restoreDrink(removed);
    await state.restoreDrink(removed);
    expect(state.waterFor(now), 450);
    await state.setWaterGoal(2500);
    final restored = await AppState.load();
    expect(restored.profile.waterTarget, 2500);
    expect(restored.waterFor(yesterday), 500);
    expect(restored.waterFor(now), 450);
  });
  test('Hydration rejects invalid intake without mutation', () async {
    final state = await AppState.load();
    for (final value in [-1, 0, 2001]) {
      await expectLater(state.recordDrink(value), throwsFormatException);
    }
    expect(state.drinks, isEmpty);
    for (var i = 0; i < 5; i++) {
      await state.recordDrink(2000);
    }
    await expectLater(state.recordDrink(1), throwsFormatException);
    expect(state.waterFor(DateTime.now()), 10000);
  });
  test('Legacy daily water totals migrate to a recoverable ledger', () async {
    final state = await AppState.load();
    final j = state.toJson()..remove('drinks');
    j['water'] = {'2026-10-06': 1250};
    await state.storage.setString(AppState.storageKey, jsonEncode(j));
    final restored = await AppState.load();
    expect(restored.waterFor(DateTime(2026, 10, 6)), 1250);
    expect(restored.drinks, hasLength(1));
    await restored.removeDrink(restored.drinks.single.id);
    expect(restored.waterFor(DateTime(2026, 10, 6)), 0);
  });
  for (final sample in <String, double>{
    '1/2': .5,
    '1 1/2': 1.5,
    '1½': 1.5,
    '0.25': .25,
  }.entries) {
    test('Portions parse ${sample.key}', () {
      expect(portionNumber(sample.key), sample.value);
    });
  }
  test('Shared portions scale independent rice and chicken foods', () async {
    final result = MealEngine.parse('rice and chicken curry');
    expect(result.questions.where((q) => q.portion), hasLength(2));
    final rice = result.meal.items.first;
    rice.grams = consumedPortion(foodById('rice'), {
      'quantity': 2.0,
      'unit': 'cup',
      'share': .25,
    });
    rice.portion = {'quantity': 2.0, 'unit': 'cup', 'share': .25};
    expect(rice.grams, 79);
    final chicken = result.meal.items.last;
    chicken.grams = 150;
    final state = await AppState.load();
    await state.saveMeal(result.meal);
    final restored = await AppState.load();
    expect(restored.meals.single.items.first.portion!['share'], .25);
    expect(restored.meals.single.items.last.grams, 150);
    expect(
      mealNutrition(restored.meals.single).calories,
      closeTo(102.7 + 232.5, .1),
    );
  });
  test('Explicit quantity of one occurrence does not suppress another', () {
    final result = MealEngine.parse('100 g rice and rice');
    expect(result.questions.where((q) => q.portion), hasLength(1));
    expect(result.questions.single.itemIndex, 1);
  });
  test('Direct edits clear stale shared portion metadata', () {
    final item = MealItem(
      foodId: 'rice',
      grams: 100,
      portion: {'quantity': 2, 'unit': 'cup', 'share': .5},
    );
    item.grams = 150;
    expect(item.portion, null);
  });
  test('Invalid portions and shares are rejected', () {
    for (final share in [0.0, -1.0, 1.1, double.nan]) {
      expect(
        () => consumedPortion(foodById('rice'), {
          'quantity': 2,
          'unit': 'cup',
          'share': share,
        }),
        throwsFormatException,
      );
    }
    expect(portionNumber('1/0'), null);
    expect(portionNumber('Infinity'), null);
  });
  test(
    'Corrupt profile restores atomically and retains account backup',
    () async {
      final state = await AppState.load(recordKey: 'test-account');
      final j = state.toJson();
      j['profile']['weight'] = -10;
      j['onboarded'] = true;
      await state.storage.setString('test-account', jsonEncode(j));
      final restored = await AppState.load(recordKey: 'test-account');
      expect(restored.onboarded, false);
      expect(restored.meals, isEmpty);
      expect(restored.storageError, isNotNull);
      expect(restored.storage.getString(restored.backupKey), isNotNull);
    },
  );
  test(
    'API food snapshot and fiber survive reload and portion editing',
    () async {
      const food = Food(
        id: 'off:test',
        name: 'Product',
        aliases: [],
        per100g: Nutrients(100, 5, 10, 4, 2),
        servingGrams: 100,
        unit: 'g',
        source: 'OFF',
        sourceUrl: 'https://world.openfoodfacts.org/product/test',
      );
      final m = Meal(
        id: 'api',
        name: 'Product',
        time: DateTime.now(),
        category: 'Lunch',
        items: [MealItem(foodId: food.id, grams: 250, snapshot: food)],
      );
      final state = await AppState.load();
      await state.saveMeal(m);
      final restored = await AppState.load();
      expect(mealNutrition(restored.meals.single).fiber, 5);
      expect(
        mealItemFood(restored.meals.single.items.single).sourceUrl,
        food.sourceUrl,
      );
    },
  );
}
