import 'package:calorie_app/core/auth_repository.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/main.dart';
import 'package:calorie_app/screens/food_camera_screen.dart';
import 'package:calorie_app/services/food_ai_service.dart';

import 'food_ai_service_test.dart' show LabelsBundle, Detector;
import 'meal_camera_test.dart' show TestCameraPlatform;

final image = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8l0AAAAASUVORK5CYII=',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> scanner(
    WidgetTester tester,
    AppState state,
    FoodAIService service, {
    Brightness brightness = Brightness.light,
  }) async {
    final original = CameraPlatform.instance;
    CameraPlatform.instance = TestCameraPlatform()..noCamera = true;
    addTearDown(() => CameraPlatform.instance = original);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(brightness: brightness),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FoodCameraScreen(
                    state: state,
                    service: service,
                    initialPhoto: image,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('Non-food dialog makes no HTTP and retake returns to camera', (
    tester,
  ) async {
    var requests = 0;
    final state = await AppState.load();
    final service = FoodAIService(
      detector: Detector([.8, .1, .05, .05]),
      bundle: LabelsBundle(),
      client: MockClient((r) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await scanner(tester, state, service);
    expect(find.text('⚠️ No Food Detected'), findsOneWidget);
    expect(requests, 0);
    await tester.tap(find.text('Retake Photo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meal-camera')), findsOneWidget);
    expect(state.meals, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'Ambiguity custom choice, portion scaling and logging in ${brightness.name}',
      (tester) async {
        var query = '';
        final state = await AppState.load();
        final service = FoodAIService(
          detector: Detector([.05, .6, .3, .05]),
          bundle: LabelsBundle(),
          client: MockClient((r) async {
            query = r.url.queryParameters['search_terms']!;
            return http.Response(
              jsonEncode({
                'products': [
                  {
                    'code': '12345',
                    'product_name': 'Cooked rice',
                    'nutriments': {
                      'energy-kcal_100g': 130,
                      'proteins_100g': 2.7,
                      'carbohydrates_100g': 28.2,
                      'fat_100g': .3,
                      'fiber_100g': .4,
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );
        await scanner(tester, state, service, brightness: brightness);
        expect(find.text('Clarify Your Meal'), findsOneWidget);
        expect(query, '');
        await tester.enterText(
          find.widgetWithText(TextField, 'A different food name'),
          'custom rice ${brightness.name}',
        );
        await tester.pump();
        await tester.ensureVisible(find.text('Confirm food'));
        await tester.tap(find.text('Confirm food'));
        await tester.pumpAndSettle();
        expect(query, 'custom rice ${brightness.name}');
        await tester.pump();
        expect(find.text('Review your meal'), findsOneWidget);
        final slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.min, 50);
        expect(slider.max, 800);
        slider.onChanged!(200);
        await tester.pump();
        expect(find.text('Portion: 200 g'), findsOneWidget);
        await tester.ensureVisible(find.text('Confirm & Log Meal'));
        await tester.tap(find.text('Confirm & Log Meal'));
        await tester.pumpAndSettle();
        expect(state.meals, hasLength(1));
        expect(state.totalsFor(DateTime.now()).calories, 260);
        expect(state.totalsFor(DateTime.now()).fiber, .8);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        await service.dispose();
      },
    );
  }
  testWidgets('Shared custom confirmation logs the eaten fraction', (
    tester,
  ) async {
    final state = await AppState.load();
    const food = FoodNutrition(
      id: 'off:shared',
      name: 'Shared rice',
      source: 'Open Food Facts',
      sourceUrl: '',
      values: [130, 2.7, 28.2, .3, .4],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: FoodConfirmationScreen(state: state, food: food),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom amount or shared portion'));
    await tester.tap(find.text('Custom amount or shared portion'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('portion-quantity')), '600');
    await tester.tap(find.text('Shared dish total'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('portion-share')), '1/4');
    await tester.ensureVisible(find.text('Update portion'));
    await tester.tap(find.text('Update portion'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('Portion: 150 g'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirm & Log Meal'));
    await tester.tap(find.text('Confirm & Log Meal'));
    await tester.pumpAndSettle();
    expect(state.meals.single.items.single.grams, 150);
    expect(state.meals.single.items.single.portion!['share'], .25);
  });
  testWidgets('Splash remains visible for the default 1.5 seconds', (
    tester,
  ) async {
    await tester.pumpWidget(KayleoApp(repository: DemoAuthRepository()));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1499));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('Welcome to your day.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
