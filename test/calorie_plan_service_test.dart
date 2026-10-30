import 'dart:convert';

import 'package:calorie_app/data/models.dart';
import 'package:calorie_app/services/calorie_plan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('applies a valid Gemini onboarding plan', () async {
    final client = MockClient((request) async {
      expect(request.headers['x-goog-api-key'], 'test-key');
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'calories': 2500,
                      'proteinGrams': 140,
                      'carbGrams': 300,
                      'fatGrams': 82,
                      'reason': 'Balanced for your routine and goal.',
                    }),
                  },
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final service = CaloriePlanService(
      client: client,
      geminiApiKey: 'test-key',
      geminiModel: 'test-model',
    );
    final profile = BodyProfile(
      age: 28,
      height: 172,
      weight: 70,
      sex: 'Male',
      activity: 'Moderately active',
      goal: 'Build muscle',
    );

    final result = await service.calculate(profile);

    expect(result.usedGemini, isTrue);
    expect(profile.calorieTarget, 2500);
    expect(profile.proteinTarget, 140);
    expect(profile.carbTarget, 300);
    expect(profile.fatTarget, 82);
  });

  test('keeps the formula plan when Gemini returns unsafe values', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'calories': 700,
                      'proteinGrams': 20,
                      'carbGrams': 20,
                      'fatGrams': 10,
                      'reason': 'Too low',
                    }),
                  },
                ],
              },
            },
          ],
        }),
        200,
      ),
    );
    final service = CaloriePlanService(
      client: client,
      geminiApiKey: 'test-key',
    );
    final profile = BodyProfile(weight: 70, height: 172, age: 28, sex: 'Male');

    final result = await service.calculate(profile);

    expect(result.usedGemini, isFalse);
    expect(profile.calorieTarget, profile.maintenance);
    expect(profile.proteinTarget, greaterThan(0));
  });
}
