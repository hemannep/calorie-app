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
}
