import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'BMI uses current measurements and the profile photo survives reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = await AppState.load();
      final profile = BodyProfile(
        name: 'Jamie',
        age: 30,
        height: 170,
        weight: 68,
        photoBase64: base64Encode([1, 2, 3, 4]),
      );
      expect(profile.bmi, closeTo(23.53, .01));
      expect(profile.bmiCategory, 'In range');
      await state.completeOnboarding(profile);
      final restored = await AppState.load();
      expect(restored.profile.photoBase64, profile.photoBase64);
      expect(restored.profile.bmi, closeTo(23.53, .01));
    },
  );

  test('weight-loss target and timeline determine a capped deficit', () {
    final gradual = BodyProfile(
      weight: 80,
      targetWeight: 74,
      goalDurationMonths: 6,
      goal: 'Lose weight',
    );
    gradual.calculateTargets();
    expect(gradual.plannedDailyDeficit, closeTo(253, 1));
    expect(
      gradual.calorieTarget,
      gradual.maintenance - gradual.plannedDailyDeficit,
    );

    final ambitious = BodyProfile(
      weight: 100,
      targetWeight: 60,
      goalDurationMonths: 3,
      goal: 'Lose weight',
    );
    expect(ambitious.plannedDailyDeficit, 750);
    final restored = BodyProfile.fromJson(ambitious.toJson());
    expect(restored.targetWeight, 60);
    expect(restored.goalDurationMonths, 3);
  });

  test('legacy profiles default to a three-month goal timeline', () {
    final profile = BodyProfile.fromJson({
      'goal': 'Lose weight',
      'weight': 70,
      'targetWeight': 65,
    });

    expect(profile.goalDurationMonths, 3);
    expect(profile.plannedDailyDeficit, greaterThan(0));
  });
}
