import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:calorie_app/services/food_ai_service.dart';

class LabelsBundle extends CachingAssetBundle {
  LabelsBundle([
    this.labels = const {
      '0': 'non_food',
      '1': 'rice',
      '2': 'chicken',
      '3': 'apple',
    },
  ]);
  final Map<String, String> labels;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(labels))));
}

class Detector implements FoodDetector {
  Detector(this.probs);
  List<double> probs;
  int loads = 0, calls = 0, releases = 0, active = 0, maxActive = 0;
  Completer<void>? gate;
  @override
  Future<void> initialize(int classes) async {
    loads++;
    expect(classes, 4);
  }

  @override
  Future<List<double>> predict(Uint8List image) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    await gate?.future;
    active--;
    return probs;
  }

  @override
  Future<void> dispose() async {
    releases++;
    expect(active, 0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Live Gemini recognizes the bundled meal photo',
    () async {
      final bytes = await File('assets/images/bowl.jpg').readAsBytes();
      HttpOverrides.global = null;
      final client = IOClient(HttpClient());
      final service = FoodAIService(client: client);
      final result = await service.analyzeMealPhoto(bytes);
      expect(result.name, isNotEmpty);
      expect(result.servingGrams, greaterThan(0));
      expect(result.values.first, greaterThan(0));
      await service.dispose();
      client.close();
    },
    skip: !const bool.fromEnvironment('GEMINI_LIVE_TEST'),
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test('Gemini photo analysis sends image and converts serving totals to per 100 g', () async {
    late http.Request request;
    final service = FoodAIService(
      geminiApiKey: 'test-key',
      geminiModel: 'test-flash',
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode({
            'interaction': {
              'output_text': jsonEncode({
                'classification': 'food',
                'mealName': 'Dal bhat with chicken',
                'items': [
                  {
                    'name': 'rice',
                    'portion': '1.5 cups',
                    'grams': 300,
                    'calories': 390,
                    'proteinGrams': 8,
                    'carbsGrams': 85,
                    'fatGrams': 1,
                    'fiberGrams': 2,
                  },
                  {
                    'name': 'lentil soup and chicken curry',
                    'portion': '1 bowl',
                    'grams': 200,
                    'calories': 360,
                    'proteinGrams': 27,
                    'carbsGrams': 20,
                    'fatGrams': 19,
                    'fiberGrams': 10,
                  },
                ],
                'confidence': .82,
                'assumptions': 'Sauce amount is uncertain',
              }),
            },
          }),
          200,
        );
      }),
    );
    final result = await service.analyzeMealPhoto(
      Uint8List.fromList([0xff, 0xd8, 0xff]),
    );
    expect(request.url.path, '/v1beta/interactions');
    expect(request.headers['x-goog-api-key'], 'test-key');
    expect(request.url.queryParameters, isEmpty);
    final requestBody = jsonDecode(request.body) as Map<String, dynamic>;
    expect(requestBody['model'], 'test-flash');
    expect(
      (requestBody['response_format'] as Map)['mime_type'],
      'application/json',
    );
    expect(result.name, 'Dal bhat with chicken');
    expect(result.servingGrams, 500);
    expect(result.values.take(4), [150, 7, 21, 4]);
    expect(result.values[4], closeTo(2.4, .000001));
    expect(result.details, contains('rice (1.5 cups)'));
    expect(result.details, contains('lentil soup and chicken curry (1 bowl)'));
    expect(result.details, contains('82%'));
    await service.dispose();
  });

  test(
    'Gemini photo analysis rejects non-food without a second request',
    () async {
      var calls = 0;
      final service = FoodAIService(
        geminiApiKey: 'test-key',
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'interaction': {
                'output_text': jsonEncode({
                  'classification': 'not_food',
                  'mealName': '',
                  'items': <Object>[],
                  'confidence': .95,
                  'assumptions': '',
                }),
              },
            }),
            200,
          );
        }),
      );
      await expectLater(
        service.analyzeMealPhoto(Uint8List.fromList([1, 2, 3])),
        throwsA(
          isA<PhotoAnalysisException>().having(
            (error) => error.issue,
            'issue',
            PhotoAnalysisIssue.noFood,
          ),
        ),
      );
      expect(calls, 1);
      await service.dispose();
    },
  );

  for (final sample in <(List<double>, ScanStatus)>[
    ([.8, .1, .05, .05], ScanStatus.noFood),
    ([.3, .39, .2, .11], ScanStatus.noFood),
    ([.1, .4, .3, .2], ScanStatus.ambiguous),
    ([.05, .6, .3, .05], ScanStatus.ambiguous),
    ([.1, .7, .1, .1], ScanStatus.confident),
  ]) {
    test('Guardrail ${sample.$1} gives ${sample.$2} without HTTP', () async {
      var requests = 0;
      final detector = Detector(sample.$1);
      final service = FoodAIService(
        detector: detector,
        bundle: LabelsBundle(),
        client: MockClient((r) async {
          requests++;
          throw StateError('Unexpected network');
        }),
      );
      final result = await service.scanMeal(Uint8List.fromList([1]));
      expect(result.status, sample.$2);
      expect(requests, 0);
      expect(result.first.name, sample.$1.first == .8 ? 'non food' : 'rice');
      await service.dispose();
      expect(detector.releases, 1);
    });
  }
  test(
    'Inference serializes and release waits for running inference',
    () async {
      final detector = Detector([.1, .7, .1, .1])..gate = Completer<void>();
      final service = FoodAIService(detector: detector, bundle: LabelsBundle());
      final first = service.scanMeal(Uint8List.fromList([1]));
      final second = service.scanMeal(Uint8List.fromList([1]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(detector.calls, 1);
      detector.gate!.complete();
      await Future.wait([first, second]);
      expect(detector.maxActive, 1);
      expect(detector.loads, 1);
      await service.dispose();
      await service.dispose();
      expect(detector.releases, 1);
      await expectLater(
        service.scanMeal(Uint8List.fromList([1])),
        throwsStateError,
      );
    },
  );
  for (final bad in [
    [.7, .1],
    [double.nan, .1, .1, .7],
    [.1, .2, .1, .1],
  ]) {
    test('Reject invalid output $bad', () async {
      final service = FoodAIService(
        detector: Detector(bad),
        bundle: LabelsBundle(),
      );
      await expectLater(
        service.scanMeal(Uint8List.fromList([1])),
        throwsFormatException,
      );
      await service.dispose();
    });
  }
  test('Invalid JSON label mapping fails before model loading', () async {
    final detector = Detector([]);
    final service = FoodAIService(
      detector: detector,
      bundle: LabelsBundle({'0': 'apple', '2': 'rice'}),
    );
    await expectLater(service.initialize(), throwsFormatException);
    expect(detector.loads, 0);
    await service.dispose();
  });
  test('Empty image is rejected before initialization', () async {
    final detector = Detector([]);
    final service = FoodAIService(detector: detector, bundle: LabelsBundle());
    await expectLater(service.scanMeal(Uint8List(0)), throwsFormatException);
    expect(detector.loads, 0);
    await service.dispose();
  });
  test(
    'OFF parses numbers, kJ, fiber and missing values without invented zero',
    () {
      final food = FoodAIService.parseOff({
        'code': '123',
        'product_name': 'Rice',
        'nutriments': {
          'energy_100g': 418.4,
          'proteins_100g': '2.3',
          'carbohydrates_100g': 28,
          'fat_100g': .3,
          'fiber_100g': '1.2',
        },
      })!;
      expect(food.values.first, closeTo(100, .00001));
      expect(food.values.skip(1), [2.3, 28, .3, 1.2]);
      expect(food.sourceUrl, contains('/123'));
      final missing = FoodAIService.parseOff({
        'product_name': 'Unknown',
        'nutriments': {'proteins_100g': double.infinity},
      })!;
      expect(missing.complete, false);
      expect(missing.values, everyElement(isNull));
    },
  );
  test('Drink labels preserve volume without assuming density', () {
    final drink = FoodAIService.parseOff({
      'product_name': 'Milk',
      'serving_size': '250 ml',
      'nutriments': {'energy-kcal_100g': 60},
    })!;
    expect(drink.unit, 'ml');
  });
  test(
    'Search URI encodes input and uses three results and identification',
    () async {
      final service = FoodAIService(
        client: MockClient((r) async {
          expect(r.url.queryParameters['search_terms'], 'rice & curry test');
          expect(r.url.queryParameters['page_size'], '3');
          expect(r.headers['user-agent'], contains('Kayleo'));
          return http.Response(
            jsonEncode({
              'products': [
                {
                  'product_name': 'Rice',
                  'nutriments': {
                    'energy-kcal_100g': 130,
                    'proteins_100g': 2.7,
                    'carbohydrates_100g': 28.2,
                    'fat_100g': .3,
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      expect(
        (await service.fetchNutrition('rice & curry test')).single.values.first,
        130,
      );
      await service.dispose();
    },
  );
  test('Offline known food uses clearly marked local estimate', () async {
    final service = FoodAIService(
      client: MockClient((r) async => throw http.ClientException('offline')),
    );
    final food = (await service.fetchNutrition('steamed rice offline')).single;
    expect(food.estimated, true);
    expect(food.source, contains('offline'));
    expect(food.values.first, 130);
    await service.dispose();
  });
  test('Unknown offline food fails instead of fabricated values', () async {
    final service = FoodAIService(
      client: MockClient((r) async => throw http.ClientException('offline')),
    );
    await expectLater(
      service.fetchNutrition('unmatched cassoulet xyz'),
      throwsA(isA<http.ClientException>()),
    );
    await service.dispose();
  });
  test('USDA energy alternatives and units are normalized correctly', () async {
    final service = FoodAIService(
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'foods': [
              {
                'fdcId': 123,
                'description': 'Cooked rice',
                'foodNutrients': [
                  {'nutrientId': 2048, 'unitName': 'KCAL', 'value': 130},
                  {'nutrientId': 1003, 'unitName': 'G', 'value': 2.7},
                  {'nutrientId': 1005, 'unitName': 'G', 'value': 28.2},
                  {'nutrientId': 1004, 'unitName': 'G', 'value': .3},
                  {'nutrientId': 1079, 'unitName': 'G', 'value': .4},
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );
    expect((await service.searchUsda('rice')).single.values, [
      130,
      2.7,
      28.2,
      .3,
      .4,
    ]);
    await service.dispose();
  });
  test('Barcode lookup uses real endpoint; not found is null', () async {
    var calls = 0;
    final service = FoodAIService(
      client: MockClient((r) async {
        calls++;
        expect(r.url.path, '/api/v2/product/3017620422003.json');
        return http.Response('{"status":0}', 200);
      }),
    );
    await expectLater(service.lookupBarcode('bad'), throwsFormatException);
    expect(calls, 0);
    expect(await service.lookupBarcode('3017620422003'), null);
    await service.dispose();
  });
}
