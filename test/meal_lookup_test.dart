import 'dart:async';
import 'dart:convert';

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/meal_lookup.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/data/food_database.dart';
import 'package:calorie_app/features/logging.dart';
import 'package:calorie_app/services/food_ai_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MatchService extends FoodAIService {
  final queries = <String>[];
  bool empty = false;
  bool incomplete = false;
  Completer<FoodSearchResults>? pending;
  @override
  Future<FoodSearchResults> searchAll(String query) async {
    queries.add(query);
    if (pending != null) return pending!.future;
    if (incomplete) {
      return const FoodSearchResults([
        FoodNutrition(
          id: 'off:incomplete',
          name: 'Samosa incomplete label',
          source: 'Open Food Facts',
          sourceUrl: '',
          values: [300, null, 40, 12, null],
        ),
      ], []);
    }
    return FoodSearchResults(
      empty
          ? []
          : [
              const FoodNutrition(
                id: 'usda:samosa',
                name: 'Vegetable samosa',
                source: 'USDA FoodData Central',
                sourceUrl:
                    'https://fdc.nal.usda.gov/food-details/123/nutrients',
                values: [300, 6, 40, 12, 3],
              ),
            ],
      empty ? ['Open Food Facts', 'USDA FoodData Central'] : [],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 7, 12);
  MealLookupPlan plan(String text) =>
      MealLookupPlan.parse(text, now: now, input: 'Text');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Natural speech resolves a known piece count offline', () {
    final p = plan('Yesterday around 1 AM I had two samosas');
    expect(p.requests, isEmpty);
    expect(p.analysis.meal.items.single.grams, 150);
    expect(p.analysis.meal.items.single.portion?['quantity'], 2);
    expect(p.analysis.meal.time, DateTime(2026, 10, 6, 1));
  });
  test('Mixed meals retain local foods and exact amounts', () {
    final p = plan('100 g rice and 150 g samosa');
    expect(p.analysis.meal.items, hasLength(2));
    expect(p.analysis.meal.items.first.foodId, 'rice');
    expect(p.analysis.meal.items.first.grams, 100);
    expect(p.analysis.meal.items.last.grams, 150);
    expect(p.requests, isEmpty);
  });
  test('Chicken biryani resolves as the full dish', () {
    final p = plan('I ate chicken biryani');
    expect(p.requests, isEmpty);
    expect(
      mealItemFood(p.analysis.meal.items.single).name,
      'Biryani with chicken',
    );
  });
  test('Known dish names containing with stay together', () {
    final p = plan('I had biryani with chicken');
    expect(p.requests, isEmpty);
    expect(p.analysis.meal.items, hasLength(1));
    expect(
      mealItemFood(p.analysis.meal.items.single).name,
      'Biryani with chicken',
    );
  });
  test('Natural plural and region-specific piece units work offline', () {
    final p = plan('I had 2 fish tacos and one samosa');
    expect(p.requests, isEmpty);
    expect(p.analysis.questions, isEmpty);
    expect(p.analysis.meal.items, hasLength(2));
    expect(mealItemFood(p.analysis.meal.items.first).name, 'Taco, fish');
    expect(p.analysis.meal.items.first.portion?['quantity'], 2);
    expect(p.analysis.meal.items.first.portion?['unit'], 'piece');
  });
  test('Known foods use standard servings without a question sequence', () {
    final p = plan('rice and chicken curry');
    expect(p.requests, isEmpty);
    expect(p.analysis.questions, isEmpty);
    expect(p.analysis.meal.items.map((item) => item.grams), [158, 200]);
  });
  test(
    'Measured fractions and ounces are normalized independently of counts',
    () {
      expect(
        plan('five ounces of samosa').analysis.meal.items.single.grams,
        closeTo(141.7475, .0001),
      );
      expect(
        plan('1 1/2 oz samosa').analysis.meal.items.single.grams,
        closeTo(42.52425, .0001),
      );
      expect(plan('250 ml lassi').requests.single.unit, 'ml');
      expect(() => plan('4000 g samosa'), throwsFormatException);
    },
  );
  test(
    'Both databases queried and complete relevant records ranked first',
    () async {
      final hosts = <String>{};
      final service = FoodAIService(
        client: MockClient((r) async {
          hosts.add(r.url.host);
          return http.Response(
            jsonEncode(
              r.url.host.contains('openfoodfacts')
                  ? {
                      'products': [
                        {
                          'code': 'test-lookup',
                          'product_name': 'Samosa sauce',
                          'nutriments': {},
                        },
                      ],
                    }
                  : {
                      'foods': [
                        {
                          'fdcId': 999,
                          'description': 'Vegetable samosa',
                          'foodNutrients': [
                            {
                              'nutrientId': 1008,
                              'unitName': 'KCAL',
                              'value': 300,
                            },
                            {'nutrientId': 1003, 'unitName': 'G', 'value': 6},
                            {'nutrientId': 1005, 'unitName': 'G', 'value': 40},
                            {'nutrientId': 1004, 'unitName': 'G', 'value': 12},
                          ],
                        },
                      ],
                    },
            ),
            200,
          );
        }),
      );
      final result = await service.searchAll('samosa test lookup');
      expect(hosts, {'world.openfoodfacts.org', 'api.nal.usda.gov'});
      expect(result.foods, hasLength(2));
      expect(result.foods.first.complete, true);
      expect(result.unavailableSources, isEmpty);
      await service.dispose();
    },
  );
  test('Exact dish names rank above related products and invalid queries fail clearly', () async {
    final service = FoodAIService(
      client: MockClient(
        (r) async => http.Response(
          jsonEncode(
            r.url.host.contains('openfoodfacts')
                ? {'products': []}
                : {
                    'foods': [
                      {
                        'fdcId': 80,
                        'description': 'BURRITO, EXACT DISH PROBE',
                        'foodNutrients': [],
                      },
                      {
                        'fdcId': 81,
                        'description': 'Exact dish probe',
                        'foodNutrients': [],
                      },
                    ],
                  },
          ),
          200,
        ),
      ),
    );
    expect(
      (await service.searchAll('exact dish probe')).foods.first.id,
      'usda:81',
    );
    await expectLater(service.searchAll(' '), throwsFormatException);
    await service.dispose();
  });
  test('One provider failure preserves results from the other', () async {
    final service = FoodAIService(
      client: MockClient((r) async {
        if (r.url.host.contains('openfoodfacts')) {
          throw http.ClientException('offline');
        }
        return http.Response(
          '{"foods":[{"fdcId":77,"description":"Dosa","foodNutrients":[]}]}',
          200,
        );
      }),
    );
    final result = await service.searchAll('dosa fallback probe');
    expect(result.foods.single.name, 'Dosa');
    expect(result.unavailableSources, ['Open Food Facts']);
    expect(result.foods.single.complete, false);
    await service.dispose();
  });
  test('Both providers offline returns a usable local match or explicit empty result', () async {
    final service = FoodAIService(
      client: MockClient((r) async => throw http.ClientException('offline')),
    );
    expect((await service.searchAll('rice')).foods.single.estimated, true);
    final unknown = await service.searchAll('unknown regional probe');
    expect(unknown.foods, isEmpty);
    expect(unknown.unavailableSources, hasLength(2));
    await service.dispose();
  });

  Future<void> openLogger(
    WidgetTester tester,
    AppState state,
    MatchService service,
    String mode,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSheet<void>(
                context,
                LoggingFlow(
                  state: state,
                  initialMode: mode,
                  foodService: service,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final mode in ['Text', 'Voice']) {
    testWidgets(
      '$mode samosa count goes straight to review and survives reload',
      (tester) async {
        final state = await AppState.load();
        final service = MatchService();
        await openLogger(tester, state, service, mode);
        final entry = find.byType(TextField).first;
        await tester.enterText(entry, 'I had 3 samosas today');
        final understand = find.text('Understand my meal');
        await tester.ensureVisible(understand);
        await tester.tap(understand);
        await tester.pumpAndSettle();
        expect(service.queries, isEmpty);
        expect(find.text('3 × Samosa'), findsOneWidget);
        expect(find.textContaining('3 pieces'), findsOneWidget);
        expect(find.textContaining('USDA FoodData Central'), findsWidgets);
        final save = find.text('Add meal');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        final restored = await AppState.load();
        expect(restored.meals, hasLength(1));
        expect(
          mealNutrition(restored.meals.single).calories,
          closeTo(697.5, .1),
        );
        expect(restored.meals.single.items.single.portion?['quantity'], 3);
        expect(
          mealItemFood(restored.meals.single.items.single).sourceUrl,
          contains('/food-details/'),
        );
        await tester.pumpWidget(const SizedBox());
        await service.dispose();
      },
    );
  }
  testWidgets(
    'No results or connection shows recovery instead of silent empty meal',
    (tester) async {
      final state = await AppState.load();
      final service = MatchService()..empty = true;
      await openLogger(tester, state, service, 'Text');
      await tester.enterText(find.byType(TextField).first, 'unlisted pastry');
      await tester.tap(find.text('Understand my meal'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Not included: unlisted pastry (databases unavailable)',
        ),
        findsOneWidget,
      );
      expect(state.meals, isEmpty);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
    },
  );
  testWidgets('Incomplete records require missing macros before review', (
    tester,
  ) async {
    final state = await AppState.load();
    final service = MatchService()..incomplete = true;
    await openLogger(tester, state, service, 'Text');
    await tester.enterText(
      find.byType(TextField).first,
      '150 g unlisted pastry',
    );
    await tester.tap(find.text('Understand my meal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Samosa incomplete label'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this food'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid label value'), findsOneWidget);
    final protein = find.widgetWithText(TextFormField, 'Protein (g)');
    await tester.ensureVisible(protein);
    await tester.enterText(protein, '6');
    await tester.tap(find.text('Use this food'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('label values completed by you'),
      findsOneWidget,
    );
    expect(state.meals, isEmpty); // Review has not confirmed a record yet.
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });
  testWidgets('Cancel database selection preserves draft and permits retry', (
    tester,
  ) async {
    final state = await AppState.load();
    final service = MatchService();
    await openLogger(tester, state, service, 'Text');
    await tester.enterText(find.byType(TextField).first, 'unlisted pastry');
    await tester.tap(find.text('Understand my meal'));
    await tester.pumpAndSettle();
    final sheetContext = tester.element(find.text('Match your food'));
    Navigator.pop(sheetContext);
    await tester.pumpAndSettle();
    expect(find.text('unlisted pastry'), findsOneWidget);
    expect(state.meals, isEmpty);
    await tester.tap(find.text('Understand my meal'));
    await tester.pumpAndSettle();
    expect(find.text('Match your food'), findsOneWidget);
    expect(service.queries, ['unlisted pastry', 'unlisted pastry']);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });
  testWidgets('Changing mode discards a late database response', (
    tester,
  ) async {
    final state = await AppState.load();
    final service = MatchService()..pending = Completer<FoodSearchResults>();
    await openLogger(tester, state, service, 'Text');
    await tester.enterText(find.byType(TextField).first, 'unlisted pastry');
    await tester.tap(find.text('Understand my meal'));
    await tester.pump();
    await tester.ensureVisible(find.text('Manual'));
    await tester.tap(find.text('Manual'));
    await tester.pump();
    service.pending!.complete(
      const FoodSearchResults([
        FoodNutrition(
          id: 'usda:late',
          name: 'Late samosa',
          source: 'USDA',
          sourceUrl: '',
          values: [300, 6, 40, 12, 3],
        ),
      ], []),
    );
    await tester.pumpAndSettle();
    expect(find.text('Match your food'), findsNothing);
    expect(state.meals, isEmpty);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });
}
