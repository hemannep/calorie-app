import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/core/nutrition_view.dart';
import 'package:calorie_app/data/models.dart';
import 'package:calorie_app/main.dart';
import 'package:calorie_app/features/onboarding.dart';
import 'package:calorie_app/features/logging.dart';
import 'package:calorie_app/features/dashboard.dart';
import 'package:calorie_app/features/shell.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';

import 'meal_camera_test.dart' show TestCameraPlatform;

final screenshotKey = GlobalKey();
Future<AppState> fresh({bool demo = true}) async {
  SharedPreferences.setMockInitialValues({});
  final s = await AppState.load();
  if (demo) {
    await s.completeOnboarding(BodyProfile(), withDemo: true);
  }
  return s;
}

Future<void> prepare(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(RepaintBoundary(key: screenshotKey, child: child));
  await tester.pumpAndSettle();
}

Future<void> snapshot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    for (final image in [
      'salad',
      'bowl',
      'breakfast',
      'burger',
      'pancakes',
      'curry',
      'momo',
    ]) {
      await precacheImage(
        AssetImage('assets/images/$image.jpg'),
        screenshotKey.currentContext!,
      );
    }
  });
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: '$name should not have layout exceptions',
  );
  if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
    return;
  }
  await tester.runAsync(() async {
    final boundary =
        screenshotKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('output/previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    final original = CameraPlatform.instance;
    CameraPlatform.instance = TestCameraPlatform()..noCamera = true;
    addTearDown(() => CameraPlatform.instance = original);
  });

  testWidgets('Splash types the wordmark before revealing the tagline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: const SplashScreen(duration: Duration(milliseconds: 1200)),
      ),
    );
    int visibleCount() => tester
        .widgetList<Brand>(find.byType(Brand))
        .map((brand) => brand.visibleCharacters)
        .whereType<int>()
        .single;
    expect(visibleCount(), 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(visibleCount(), inInclusiveRange(1, 6));
    await tester.pump(const Duration(milliseconds: 900));
    expect(visibleCount(), 7);
    await tester.pumpAndSettle();
    expect(find.text('Your day, in balance.'), findsOneWidget);
  });

  testWidgets(
    'Splash, onboarding, and sample exploration are usable without authentication',
    (tester) async {
      final s = await fresh(demo: false);
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        RepaintBoundary(
          key: screenshotKey,
          child: KayleoApp(
            state: s,
            splashDuration: const Duration(milliseconds: 600),
          ),
        ),
      );
      expect(find.byKey(const Key('splash-typewriter')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(find.text('Snap it.\nKayleo gets it.'), findsOneWidget);
      await snapshot(tester, 'onboarding-desktop');
      await tester.tap(find.byKey(const Key('explore-demo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-food-search')), findsOneWidget);
      expect(s.onboarded, isTrue);
      expect(s.demo, isTrue);
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'Text with known foods reviews directly and updates the daily records',
    (tester) async {
      final s = await fresh();
      final count = s.meals.length;
      await prepare(
        tester,
        const Size(390, 844),
        KayleoApp(state: s, splashDuration: Duration.zero),
      );
      await tester.ensureVisible(find.text('Type it'));
      await tester.tap(find.text('Type it'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('meal-description')),
        'Rice and chicken curry',
      );
      await tester.tap(find.byKey(const Key('logging-continue')));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('Kayleo sees'), findsOneWidget);
      await snapshot(tester, 'meal-review-mobile');
      await tester.tap(find.byKey(const Key('save-meal')));
      await tester.pumpAndSettle();
      expect(find.text('Your meal is added.'), findsOneWidget);
      expect(s.meals.length, count + 1);
      expect(s.meals.last.items.first.grams, 158);
      await snapshot(tester, 'meal-success-mobile');
      await tester.tap(find.byKey(const Key('logging-continue')));
      await tester.pumpAndSettle();
      final restored = await AppState.load();
      expect(restored.meals.length, count + 1);
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('Desktop routes render and all navigation destinations work', (
    tester,
  ) async {
    final s = await fresh();
    s.community = true;
    await prepare(
      tester,
      const Size(1440, 1000),
      KayleoApp(state: s, splashDuration: Duration.zero),
    );
    await snapshot(tester, 'today-desktop');
    for (final (label, name, title) in [
      ('Diary', 'diary-desktop', 'Diary'),
      ('Scan food', 'capture-desktop', 'What’s on your plate?'),
      ('Progress', 'progress-desktop', 'Progress'),
      ('Saved meals', 'saved-meals-desktop', 'Your usuals, ready.'),
      ('Community', 'community-desktop', 'Better, together.'),
    ]) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(
        find.text(title),
        title == label ? findsNWidgets(2) : findsOneWidget,
      );
      await snapshot(tester, name);
    }
    await tester.tap(find.text('Alex').first);
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    await snapshot(tester, 'settings-desktop');
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Mobile routes and hydration controls work with no overflow', (
    tester,
  ) async {
    final s = await fresh();
    await prepare(
      tester,
      const Size(390, 844),
      KayleoApp(state: s, splashDuration: Duration.zero),
    );
    await snapshot(tester, 'today-mobile');
    for (final (label, name) in [
      ('Diary', 'diary-mobile'),
      ('Progress', 'progress-mobile'),
      ('You', 'settings-mobile'),
    ]) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      await snapshot(tester, name);
    }
    // The part raised above the bar must remain a working tap target.
    final cameraBounds = tester.getRect(
      find.byKey(const Key('bottom-camera-button')),
    );
    await tester.tapAt(Offset(cameraBounds.center.dx, cameraBounds.top + 6));
    await tester.pumpAndSettle();
    await snapshot(tester, 'capture-mobile');
    await tester.tap(find.byKey(const Key('close-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    final water = s.waterFor(DateTime.now());
    await tester.ensureVisible(find.byKey(const Key('add-water')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-water')));
    await tester.pumpAndSettle();
    expect(s.waterFor(DateTime.now()), water + 250);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'Onboarding renders on small mobile and validates adult profile',
    (tester) async {
      final s = await fresh(demo: false);
      await prepare(
        tester,
        const Size(360, 780),
        MaterialApp(
          theme: kayleoTheme(),
          home: OnboardingScreen(state: s),
        ),
      );
      await snapshot(tester, 'onboarding-mobile');
      for (var i = 0; i < 4; i++) {
        await tester.ensureVisible(
          find.byKey(const Key('onboarding-continue')),
        );
        await tester.tap(find.byKey(const Key('onboarding-continue')));
        await tester.pumpAndSettle();
      }
      expect(find.text('About you.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Age'), '16');
      await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
      await tester.tap(find.byKey(const Key('onboarding-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Adults 18–100'), findsOneWidget);
      expect(s.onboarded, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'Empty manual flow offers custom nutrition rather than inventing an estimate',
    (tester) async {
      final s = await fresh(demo: false);
      await prepare(
        tester,
        const Size(390, 844),
        MaterialApp(
          theme: kayleoTheme(),
          home: Scaffold(
            body: LoggingFlow(state: s, initialMode: 'Text'),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('meal-description')),
        'unrecognized casserole',
      );
      await tester.tap(find.byKey(const Key('logging-continue')));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-meal')));
      await tester.pumpAndSettle();
      expect(s.meals, isEmpty);
      expect(
        find.text('Add a food or enter nutrition before saving.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('Full onboarding creates a personal plan and an empty diary', (
    tester,
  ) async {
    final s = await fresh(demo: false);
    await prepare(
      tester,
      const Size(390, 844),
      KayleoApp(state: s, splashDuration: Duration.zero),
    );
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
      await tester.tap(find.byKey(const Key('onboarding-continue')));
      await tester.pumpAndSettle();
      if (i == 2) await snapshot(tester, 'onboarding-v2-goal');
      if (i == 3) await snapshot(tester, 'onboarding-v2-details');
    }
    await tester.enterText(
      find.widgetWithText(TextFormField, 'What should we call you?'),
      'Jamie',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Age'), '30');
    await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
    await tester.tap(find.byKey(const Key('onboarding-continue')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Moderately active'));
    await tester.tap(find.text('Moderately active'));
    await tester.pumpAndSettle();
    await snapshot(tester, 'onboarding-v2-activity');
    await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
    await tester.tap(find.byKey(const Key('onboarding-continue')));
    await tester.pumpAndSettle();
    expect(find.text('What feels\ngood to eat?'), findsOneWidget);
    await tester.ensureVisible(find.text('Vegetarian'));
    await tester.tap(find.text('Vegetarian'));
    await tester.pumpAndSettle();
    await snapshot(tester, 'onboarding-v2-diet');
    await tester.tap(find.byKey(const Key('onboarding-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Your plan,\nin balance.'), findsOneWidget);
    expect(s.onboarded, isFalse);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Your plan.\nYour pace.'), findsOneWidget);
    await snapshot(tester, 'personal-plan-mobile');
    await tester.ensureVisible(find.text('Edit answers'));
    await tester.tap(find.text('Edit answers'));
    await tester.pumpAndSettle();
    expect(find.text('What brings\nyou here?'), findsOneWidget);
    await tester.tap(find.text('Build muscle'));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('onboarding-continue')));
      await tester.pumpAndSettle();
      if (i == 0) {
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'What should we call you?'),
              )
              .controller!
              .text,
          'Jamie',
        );
      }
    }
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Your plan.\nYour pace.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('onboarding-continue')));
    await tester.tap(find.byKey(const Key('onboarding-continue')));
    await tester.pumpAndSettle();
    expect(s.onboarded, isTrue);
    expect(s.profile.name, 'Jamie');
    expect(s.meals, isEmpty);
    expect(s.weights.length, 1);
    expect(s.profile.activity, 'Moderately active');
    expect(s.profile.diet, 'Vegetarian');
    expect(s.profile.goal, 'Build muscle');
    expect(find.byKey(const Key('home-food-search')), findsOneWidget);
    await snapshot(tester, 'empty-day-mobile');
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Unknown food can be logged through manual label nutrition', (
    tester,
  ) async {
    final s = await fresh(demo: false);
    await prepare(
      tester,
      const Size(390, 844),
      MaterialApp(
        theme: kayleoTheme(),
        home: Scaffold(
          body: LoggingFlow(state: s, initialMode: 'Text'),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('meal-description')),
      'unknown casserole',
    );
    await tester.tap(find.byKey(const Key('logging-continue')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enter nutrition from a label'));
    await tester.tap(find.text('Enter nutrition from a label'));
    await tester.pumpAndSettle();
    for (final (label, value) in [
      ('Meal name', 'My casserole'),
      ('Calories (kcal)', '333'),
      ('Protein (g)', '12'),
      ('Carbs (g)', '34'),
      ('Fat (g)', '5'),
    ]) {
      await tester.enterText(find.widgetWithText(TextFormField, label), value);
    }
    await tester.tap(find.text('Use these values'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-meal')));
    await tester.pumpAndSettle();
    expect(s.meals.length, 1);
    expect(s.meals.first.name, 'My casserole');
    expect(s.meals.first.manual!.calories, 333);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'Editing portions changes one existing record without duplication',
    (tester) async {
      final s = await fresh(demo: false);
      final m = Meal(
        id: 'portion-test',
        name: 'Rice',
        time: DateTime.now(),
        category: 'Lunch',
        items: [MealItem(foodId: 'rice', grams: 100)],
      );
      await s.saveMeal(m);
      await prepare(
        tester,
        const Size(390, 844),
        MaterialApp(
          theme: kayleoTheme(),
          home: Scaffold(
            body: LoggingFlow(state: s, existing: m),
          ),
        ),
      );
      await tester.ensureVisible(find.byTooltip('Edit Steamed rice'));
      await tester.tap(find.byTooltip('Edit Steamed rice'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('portion-quantity')), '200');
      await tester.tap(find.text('Update portion'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-meal')));
      await tester.pumpAndSettle();
      expect(s.meals.length, 1);
      expect(s.meals.first.items.first.grams, 200);
      expect(s.totalsFor(DateTime.now()).calories, 260);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('Short desktop and small mobile community remain usable', (
    tester,
  ) async {
    final s = await fresh();
    s.community = true;
    await prepare(
      tester,
      const Size(1440, 720),
      KayleoApp(state: s, splashDuration: Duration.zero),
    );
    await snapshot(tester, 'short-desktop');
    tester.view.physicalSize = const Size(360, 780);
    await tester.pumpAndSettle();
    await tester.tap(find.text('You').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Community'));
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();
    await snapshot(tester, 'community-mobile');
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('Logging from a past diary date keeps that date by default', (
    tester,
  ) async {
    final s = await fresh(demo: false);
    final day = DateTime.now().subtract(const Duration(days: 3));
    await prepare(
      tester,
      const Size(390, 844),
      MaterialApp(
        theme: kayleoTheme(),
        home: Scaffold(
          body: LoggingFlow(state: s, initialMode: 'Text', initialDate: day),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('meal-description')), '2 eggs');
    await tester.tap(find.byKey(const Key('logging-continue')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-meal')));
    await tester.pumpAndSettle();
    expect(dateKey(s.meals.first.time), dateKey(day));
    expect(s.mealsFor(day).length, 1);
    expect(s.mealsFor(DateTime.now()), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'Daily macro rings include food portions and manual nutrition, and update after an edit',
    (tester) async {
      final s = await fresh();
      final now = DateTime.now();
      final lunch = Meal(
        id: 'lunch',
        name: 'Rice and curry',
        time: now,
        category: 'Lunch',
        items: [
          MealItem(foodId: 'rice', grams: 158),
          MealItem(foodId: 'curry', grams: 200),
        ],
      );
      s.meals = [
        lunch,
        Meal(
          id: 'snack',
          name: 'Snack',
          time: now,
          category: 'Snack',
          items: [],
          manual: const Nutrients(160, 25, 10, 2),
        ),
      ];
      await prepare(
        tester,
        const Size(390, 844),
        MaterialApp(
          theme: kayleoTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: s,
                builder: (_, _) => EnergyPanel(state: s, date: now),
              ),
            ),
          ),
        ),
      );
      final rings = tester
          .widgetList<KayleoRing>(find.byType(KayleoRing))
          .where(
            (r) => [
              NutritionMetric.protein.color,
              NutritionMetric.carbs.color,
              NutritionMetric.fats.color,
            ].contains(r.color),
          )
          .toList();
      expect(rings.length, 3);
      expect(rings[0].progress, closeTo(57.266 / 120, .001));
      expect(rings[1].progress, closeTo(64.556 / 275, .001));
      expect(rings[2].progress, closeTo(20.074 / 65, .001));
      final edit = lunch.copy();
      edit.items.first.grams = 316;
      await s.saveMeal(edit);
      await tester.pumpAndSettle();
      final updated = tester
          .widgetList<KayleoRing>(find.byType(KayleoRing))
          .where(
            (r) => [
              NutritionMetric.protein.color,
              NutritionMetric.carbs.color,
              NutritionMetric.fats.color,
            ].contains(r.color),
          )
          .toList();
      expect(updated[0].progress, closeTo(61.532 / 120, .001));
      expect(updated[1].progress, closeTo(109.112 / 275, .001));
      expect(updated[2].progress, closeTo(20.548 / 65, .001));
      await snapshot(tester, 'macro-rings-mobile');
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'Progress tracks all nutrients with correct averages, units, targets, and date ranges',
    (tester) async {
      final s = await fresh();
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      s.meals = [
        Meal(
          id: 'today',
          name: 'Today',
          time: now,
          category: 'Lunch',
          items: [],
          manual: const Nutrients(500, 25, 60, 15),
        ),
        Meal(
          id: 'rice',
          name: 'Rice',
          time: yesterday,
          category: 'Lunch',
          items: [MealItem(foodId: 'rice', grams: 100)],
        ),
        Meal(
          id: 'dinner',
          name: 'Dinner',
          time: yesterday,
          category: 'Dinner',
          items: [],
          manual: const Nutrients(370, 17.3, 31.8, 14.7),
        ),
        Meal(
          id: 'older',
          name: 'Older meal',
          time: now.subtract(const Duration(days: 10)),
          category: 'Lunch',
          items: [],
          manual: const Nutrients(800, 50, 90, 30),
        ),
      ];
      await prepare(
        tester,
        const Size(1440, 1000),
        KayleoApp(state: s, splashDuration: Duration.zero),
      );
      await tester.tap(find.text('Progress').first);
      await tester.pumpAndSettle();
      for (final label in [
        'Average calories',
        'Average protein',
        'Average carbs',
        'Average fats',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('average-protein-progress')),
            )
            .value,
        closeTo(22.5 / 120, .001),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('average-carbs-progress')),
            )
            .value,
        closeTo(60 / 275, .001),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('average-fats-progress')),
            )
            .value,
        closeTo(15 / 65, .001),
      );
      for (final (metric, intake, target) in [
        (NutritionMetric.calories, 500.0, 2200),
        (NutritionMetric.protein, 25.0, 120),
        (NutritionMetric.carbs, 60.0, 275),
        (NutritionMetric.fats, 15.0, 65),
      ]) {
        await tester.ensureVisible(find.byKey(Key('chart-${metric.name}')));
        await tester.tap(find.byKey(Key('chart-${metric.name}')));
        await tester.pumpAndSettle();
        expect(
          find.text('${metric.label} intake · ${metric.unit}'),
          findsOneWidget,
        );
        expect(
          find.text('Daily target: ${number(target)} ${metric.unit}'),
          findsNWidgets(2),
        );
        final bar = tester.widget<Container>(
          find.byKey(Key('nutrition-bar-${dateKey(now)}')),
        );
        expect(
          bar.constraints!.maxHeight,
          closeTo(150 * intake / (target * 1.2), .01),
        );
      }
      await snapshot(tester, 'nutrient-progress-desktop');
      await tester.ensureVisible(find.text('30 days'));
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('average-protein-progress')),
            )
            .value,
        closeTo((25 + 20 + 50) / 3 / 120, .001),
      );
      expect(
        find.byKey(
          Key(
            'nutrition-bar-${dateKey(now.subtract(const Duration(days: 10)))}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Fats intake · g'), findsOneWidget);
      tester.view.physicalSize = const Size(360, 780);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('chart-protein')));
      await tester.tap(find.byKey(const Key('chart-protein')));
      await tester.pumpAndSettle();
      await snapshot(tester, 'nutrient-progress-mobile');
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
    'Empty nutrition stays at zero and over-target bars preserve actual intake',
    (tester) async {
      final s = await fresh();
      s.meals.clear();
      await prepare(
        tester,
        const Size(390, 844),
        KayleoApp(state: s, splashDuration: Duration.zero),
      );
      for (final ring
          in tester
              .widgetList<KayleoRing>(find.byType(KayleoRing))
              .where(
                (r) => [
                  NutritionMetric.protein.color,
                  NutritionMetric.carbs.color,
                  NutritionMetric.fats.color,
                ].contains(r.color),
              )) {
        expect(ring.progress, 0);
      }
      await s.saveMeal(
        Meal(
          id: 'big',
          name: 'All meals',
          time: DateTime.now(),
          category: 'Lunch',
          items: [],
          manual: const Nutrients(7000, 300, 800, 200),
        ),
      );
      await tester.pumpAndSettle();
      if (find.byTooltip('Close celebration').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Close celebration'));
        await tester.pumpAndSettle();
      }
      expect(find.text('300g'), findsOneWidget);
      expect(find.text('800g'), findsOneWidget);
      expect(find.text('200g'), findsOneWidget);
      for (final ring
          in tester
              .widgetList<KayleoRing>(find.byType(KayleoRing))
              .where(
                (r) => [
                  NutritionMetric.protein.color,
                  NutritionMetric.carbs.color,
                  NutritionMetric.fats.color,
                ].contains(r.color),
              )) {
        expect(ring.progress, greaterThan(1));
      }
      await tester.tap(find.text('Progress').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('chart-fats')));
      await tester.tap(find.byKey(const Key('chart-fats')));
      await tester.pumpAndSettle();
      await s.deleteMeal('big');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('average-fats-progress')),
            )
            .value,
        0,
      );
      final emptyBar = tester.widget<Container>(
        find.byKey(Key('nutrition-bar-${dateKey(DateTime.now())}')),
      );
      expect(emptyBar.constraints!.maxHeight, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('Small-phone navigation and primary screens support large text', (
    tester,
  ) async {
    final s = await fresh();
    await prepare(
      tester,
      const Size(360, 780),
      MaterialApp(
        theme: kayleoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: AppShell(state: s),
      ),
    );
    await snapshot(tester, 'kayleo-large-text-today');
    for (final tab in ['Diary', 'Progress', 'You']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      await snapshot(tester, 'kayleo-large-text-${tab.toLowerCase()}');
    }
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
