import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/meal_engine.dart';
import 'package:calorie_app/data/food_database.dart';
import 'package:calorie_app/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Rice and curry ask portions for both foods and preparation; answers recalculate nutrition', () {
    final result = MealEngine.parse('Rice and chicken curry');
    expect(result.meal.items.map((i) => i.foodId), ['rice', 'curry']);
    expect(result.questions.length, 3);
    MealEngine.answer(result.meal, result.questions[0], 2);
    MealEngine.answer(result.meal, result.questions[1], 0);
    MealEngine.answer(result.meal, result.questions[2], 1);
    expect(result.meal.items.first.grams, 316);
    expect(mealNutrition(result.meal).calories, closeTo(809.2, .1));
    expect(result.meal.items.where((i) => i.foodId == 'oil').length, 1);
    MealEngine.answer(result.meal, result.questions[2], 0);
    expect(result.meal.items.where((i) => i.foodId == 'oil'), isEmpty);
  });

  test(
    'Explicit portions, preparation, and time avoid unnecessary questions',
    () {
      final result = MealEngine.parse(
        'At 1 AM yesterday I had 2 cups of rice and 200 g home-style chicken curry',
        now: DateTime(2026, 10, 6, 14),
      );
      expect(result.questions, isEmpty);
      expect(result.meal.items.length, 2);
      expect(result.meal.items.first.grams, 316);
      expect(result.meal.items.last.grams, 200);
      expect(result.meal.time, DateTime(2026, 10, 5, 1));
    },
  );

  test(
    'Natural voice quantities and ounce conversions use the same pipeline',
    () {
      final result = MealEngine.parse(
        'I had a veg burger with five ounces of French fries',
        input: 'Voice',
      );
      expect(result.meal.items.map((i) => i.foodId), ['vegburger', 'fries']);
      expect(result.meal.items.last.grams, closeTo(141.7475, .001));
      expect(result.meal.input, 'Voice');
      final eggs = MealEngine.parse('two eggs and avocado toast');
      expect(eggs.meal.items.first.grams, 100);
    },
  );

  test('Regional and unknown foods do not create invented matches', () {
    final result = MealEngine.parse('8 chicken momo and dal bhat');
    expect(result.meal.items.map((i) => i.foodId), ['momo', 'dalbhat']);
    expect(result.meal.items.first.grams, 240);
    expect(MealEngine.parse('mystery casserole').unmatched, isTrue);
    expect(MealEngine.parse('mystery casserole').meal.items, isEmpty);
  });

  test('Manual nutrition combines with deterministic food portions', () {
    final m = Meal(
      id: 'test',
      name: 'My recipe',
      time: DateTime.now(),
      category: 'Lunch',
      items: [MealItem(foodId: 'rice', grams: 100)],
      manual: const Nutrients(200, 15, 25, 7),
    );
    expect(mealNutrition(m).calories, 330);
    expect(mealNutrition(m).protein, closeTo(17.7, .01));
    expect(
      mealNutrition(Meal.fromJson(jsonDecode(jsonEncode(m.toJson())))).calories,
      330,
    );
  });

  test(
    'Meal, template, hydration, weight, activity and settings survive reload',
    () async {
      final state = await AppState.load();
      await state.completeOnboarding(BodyProfile(name: 'Test'));
      final m = MealEngine.parse('2 eggs').meal;
      await state.saveMeal(m);
      await state.saveTemplate(m);
      await state.addWater(250);
      await state.logWeight(68.2);
      await state.addActivity(20);
      state.preferences['Hydration reminders'] = true;
      state.joined.add('regional');
      await state.persist();
      final restored = await AppState.load();
      expect(restored.onboarded, isTrue);
      expect(restored.meals.length, 1);
      expect(restored.templates.length, 1);
      expect(restored.waterFor(DateTime.now()), 250);
      expect(restored.profile.weight, 68.2);
      expect(restored.activityMinutes[dateKey(DateTime.now())], 20);
      expect(restored.preferences['Hydration reminders'], isTrue);
      expect(restored.joined, contains('regional'));
      final draft = restored.meals.first.copy();
      draft.items.first.grams = 1000;
      expect(restored.meals.first.items.first.grams, 100);
    },
  );

  test('Edits replace one record and deleting removes its totals', () async {
    final state = await AppState.load();
    final meal = MealEngine.parse('100g rice').meal;
    await state.saveMeal(meal);
    final edit = meal.copy();
    edit.items.first.grams = 200;
    await state.saveMeal(edit);
    expect(state.meals.length, 1);
    expect(state.totalsFor(meal.time).calories, 260);
    await state.deleteMeal(meal.id);
    expect(state.totalsFor(meal.time).calories, 0);
  });

  test(
    'Photo retention preference and resetting clear sensitive local data',
    () async {
      final state = await AppState.load();
      state.seedDemo();
      state.onboarded = true;
      await state.persist();
      await state.addWater(-10000);
      expect(state.waterFor(DateTime.now()), 0);
      await state.reset();
      final clean = await AppState.load();
      expect(clean.onboarded, isFalse);
      expect(clean.meals, isEmpty);
      expect(clean.weights, isEmpty);
      expect(clean.activityMinutes, isEmpty);
    },
  );

  test('Corrupt records preserve an exportable recovery backup', () async {
    SharedPreferences.setMockInitialValues({'nouri_state_v1': '{invalid'});
    final state = await AppState.load();
    expect(state.storageError, isNotNull);
    expect(state.storage.getString('nouri_recovery_backup_v1'), '{invalid');
    await state.persist();
    expect(state.storage.getString('nouri_recovery_backup_v1'), '{invalid');
  });

  test(
    'Target estimate responds to body profile and goal with adult guardrails',
    () {
      final p = BodyProfile(weight: 70, height: 172, age: 28, sex: 'Male');
      final maintenance = p.maintenance;
      p.goal = 'Lose weight';
      p.calculateTargets();
      expect(p.calorieTarget, maintenance - 250);
      p.goal = 'Build muscle';
      p.calculateTargets();
      expect(p.calorieTarget, maintenance + 250);
      p.weight = 30;
      p.height = 100;
      p.age = 100;
      p.goal = 'Lose weight';
      p.calculateTargets();
      expect(p.calorieTarget, 1500);
    },
  );
}
