import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';
import 'gemini_env.local.dart';

class CaloriePlanResult {
  const CaloriePlanResult({required this.usedGemini, this.explanation = ''});

  final bool usedGemini;
  final String explanation;
}

/// Builds a conservative starting nutrition plan. Gemini can refine the
/// estimate, but the deterministic Mifflin-St Jeor plan remains the fallback
/// and bounds every model-provided value.
class CaloriePlanService {
  CaloriePlanService({
    http.Client? client,
    String? geminiApiKey,
    String? geminiModel,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _geminiApiKey = _resolveGeminiApiKey(geminiApiKey),
       _geminiModel =
           geminiModel ??
           const String.fromEnvironment(
             'GEMINI_MODEL',
             defaultValue: localGeminiModel,
           );

  final http.Client _client;
  final bool _ownsClient;
  final String _geminiApiKey;
  final String _geminiModel;

  bool get geminiConfigured => _geminiApiKey.trim().isNotEmpty;

  static String _resolveGeminiApiKey(String? explicit) {
    if (explicit != null) return explicit;
    const defined = String.fromEnvironment('GEMINI_API_KEY');
    if (defined.trim().isNotEmpty) return defined;
    try {
      final binding = WidgetsBinding.instance.runtimeType.toString();
      if (!binding.contains('Test')) return localGeminiApiKey;
    } catch (_) {}
    return '';
  }

  Future<CaloriePlanResult> calculate(BodyProfile profile) async {
    profile.calculateTargets();
    if (!geminiConfigured) {
      return const CaloriePlanResult(usedGemini: false);
    }

    final baselineCalories = profile.calorieTarget;
    final baselineMaintenance = profile.maintenance;
    try {
      final response = await _client
          .post(
            Uri.https(
              'generativelanguage.googleapis.com',
              '/v1beta/models/$_geminiModel:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _geminiApiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text':
                          'Create a conservative adult daily nutrition starting point. '
                          'Use Mifflin-St Jeor as the anchor, interpret the stated activity '
                          'level conservatively, and use a gradual goal adjustment. Do not '
                          'diagnose or account for medical conditions. Return integers only.\n'
                          'Profile: age=${profile.age}, sex=${profile.sex}, '
                          'heightCm=${profile.height}, weightKg=${profile.weight}, '
                          'activity=${profile.activity}, goal=${profile.goal}, '
                          'targetWeightKg=${profile.targetWeight}, '
                          'goalDurationMonths=${profile.goalDurationMonths}, '
                          'diet=${profile.diet}.\n'
                          'App baseline: maintenance=$baselineMaintenance kcal, '
                          'target=$baselineCalories kcal. Keep calories within 12% of the '
                          'app baseline and 1500-4500 kcal. For weight loss, never return '
                          'calories above the app target. Keep protein 0.8-2.2 g/kg, fat '
                          'at least 20% of calories, and make protein/carbs/fat calories '
                          'approximately equal the calorie target. Include a short plain-language reason.',
                    },
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.1,
                'maxOutputTokens': 350,
                'responseMimeType': 'application/json',
                'responseJsonSchema': {
                  'type': 'object',
                  'required': [
                    'calories',
                    'proteinGrams',
                    'carbGrams',
                    'fatGrams',
                    'reason',
                  ],
                  'properties': {
                    'calories': {'type': 'integer'},
                    'proteinGrams': {'type': 'integer'},
                    'carbGrams': {'type': 'integer'},
                    'fatGrams': {'type': 'integer'},
                    'reason': {'type': 'string'},
                  },
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const CaloriePlanResult(usedGemini: false);
      }
      final envelope = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = envelope['candidates'] as List?;
      final content = candidates?.firstOrNull as Map<String, dynamic>?;
      final parts = (content?['content'] as Map?)?['parts'] as List?;
      final text = (parts?.firstOrNull as Map?)?['text'] as String?;
      if (text == null) return const CaloriePlanResult(usedGemini: false);
      final plan = jsonDecode(text) as Map<String, dynamic>;
      final calories = (plan['calories'] as num?)?.round();
      final protein = (plan['proteinGrams'] as num?)?.round();
      final carbs = (plan['carbGrams'] as num?)?.round();
      final fat = (plan['fatGrams'] as num?)?.round();
      if (!_validPlan(
        profile,
        baselineCalories,
        calories,
        protein,
        carbs,
        fat,
      )) {
        return const CaloriePlanResult(usedGemini: false);
      }
      profile
        ..calorieTarget = calories!
        ..proteinTarget = protein!
        ..carbTarget = carbs!
        ..fatTarget = fat!;
      return CaloriePlanResult(
        usedGemini: true,
        explanation: (plan['reason'] as String? ?? '').trim(),
      );
    } on Object {
      return const CaloriePlanResult(usedGemini: false);
    }
  }

  bool _validPlan(
    BodyProfile profile,
    int baseline,
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
  ) {
    if (calories == null || protein == null || carbs == null || fat == null) {
      return false;
    }
    final minCalories = (baseline * .88).round().clamp(1500, 4500);
    final maxCalories = profile.goal == 'Lose weight'
        ? baseline
        : (baseline * 1.12).round().clamp(1500, 4500);
    final macroCalories = protein * 4 + carbs * 4 + fat * 9;
    return calories >= minCalories &&
        calories <= maxCalories &&
        protein >= (profile.weight * .8).round() &&
        protein <= (profile.weight * 2.2).round() &&
        carbs > 0 &&
        fat > 0 &&
        fat * 9 >= calories * .2 &&
        (macroCalories - calories).abs() <= calories * .12;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
