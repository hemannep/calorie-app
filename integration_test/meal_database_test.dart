import 'dart:convert';

import 'package:calorie_app/services/food_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android can search samosa across live nutrition providers', (
    tester,
  ) async {
    final service = FoodAIService();
    try {
      final results = await service.searchAll('samosa');
      // Public sample query only: no user diary, profile, microphone or camera.
      // ignore: avoid_print
      print(
        'MEAL_DATABASE_PROBE ${jsonEncode({
          'foods': results.foods.map((f) => {'name': f.name, 'source': f.source, 'complete': f.complete}).toList(),
          'unavailable': results.unavailableSources,
        })}',
      );
      expect(
        results.foods,
        isNotEmpty,
        reason: 'At least one live provider must return samosa records.',
      );
      expect(
        results.foods.any((f) => f.name.toLowerCase().contains('samosa')),
        true,
      );
    } finally {
      await service.dispose();
    }
  });
}
