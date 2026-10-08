import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:calorie_app/services/food_ai_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Uploaded TorchScript runs on Android and releases its native model',
    (tester) async {
      final service = FoodAIService();
      for (final name in ['bowl', 'curry', 'salad']) {
        final bytes = (await rootBundle.load('assets/images/$name.jpg')).buffer
            .asUint8List();
        final result = await service.scanMeal(bytes);
        // Runtime evidence, not an accuracy certification.
        // ignore: avoid_print
        print(
          'MODEL_PROBE ${jsonEncode({'image': name, 'status': result.status.name, 'first': result.first.name, 'p1': result.first.confidence, 'second': result.second.name, 'p2': result.second.confidence})}',
        );
        expect(result.first.confidence, isNonNegative);
        expect(result.first.confidence, lessThanOrEqualTo(1));
      }
      await service.dispose();
      await service.dispose();
      for (var i = 0; i < 3; i++) {
        final repeated = FoodAIService();
        await repeated.initialize();
        await repeated.dispose();
      }
    },
  );
}
