import 'dart:io';
import 'dart:ui' as ui;

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/meal_engine.dart';
import 'package:calorie_app/core/milestones.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/features/milestones.dart';
import 'package:calorie_app/features/dashboard.dart';
import 'package:calorie_app/features/shell.dart';
import 'package:calorie_app/features/widget_gallery.dart';
import 'package:calorie_app/main.dart';
import 'package:calorie_app/services/home_widget_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show prepare, snapshot, screenshotKey;

Future<AppState> fresh() async {
  SharedPreferences.setMockInitialValues({});
  final state = await AppState.load();
  await state.completeOnboarding(state.profile);
  return state;
}

void main() {
  test('Kayleo greets the local morning, afternoon and evening', () {
    expect(kayleoGreeting(DateTime(2026, 10, 9, 0)), 'Good morning');
    expect(kayleoGreeting(DateTime(2026, 10, 9, 11, 59)), 'Good morning');
    expect(kayleoGreeting(DateTime(2026, 10, 9, 12)), 'Good afternoon');
    expect(kayleoGreeting(DateTime(2026, 10, 9, 16, 59)), 'Good afternoon');
    expect(kayleoGreeting(DateTime(2026, 10, 9, 17)), 'Good evening');
    expect(kayleoGreeting(DateTime(2026, 10, 9, 23, 59)), 'Good evening');
  });
  setUpAll(() async {
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'A new milestone waits for logging to close and celebrates only once',
    (t) async {
      final state = await fresh();
      final navigator = GlobalKey<NavigatorState>();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        state.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await prepare(
        t,
        const Size(390, 844),
        MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigator,
          navigatorObservers: [kayleoRouteObserver],
          theme: kayleoTheme(),
          home: AppShell(state: state),
        ),
      );
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Logging a meal')),
        ),
      );
      await t.pumpAndSettle();
      final meal = MealEngine.parse('100 g rice').meal;
      await state.saveMeal(meal);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('milestone-celebration')), findsNothing);
      navigator.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('milestone-celebration')), findsOneWidget);
      expect(state.celebratedMilestones, contains('meal1'));
      await snapshot(t, 'kayleo-celebration');
      await t.tap(find.byTooltip('Close celebration'));
      await t.pumpAndSettle();
      await state.saveMeal(meal);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('milestone-celebration')), findsNothing);
      final restored = await AppState.load();
      expect(restored.celebratedMilestones, contains('meal1'));
      restored.dispose();
    },
  );

  test('Disabled celebrations and historical records keep earned badges without replay', () async {
    final state = await fresh();
    state.preferences['Milestone celebrations'] = false;
    await state.saveMeal(MealEngine.parse('100 g rice').meal);
    expect(state.milestoneUnlocks, contains('meal1'));
    expect(state.celebratedMilestones, contains('meal1'));
    final legacy = state.toJson()..remove('celebratedMilestones');
    await state.applyCloudSnapshot(legacy);
    expect(state.celebratedMilestones, contains('meal1'));
    state.dispose();
  });

  testWidgets(
    'Widget shortcuts return to Today and open the streak collection',
    (t) async {
      final state = await fresh();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        state.dispose();
      });
      await t.pumpWidget(
        KayleoApp(state: state, splashDuration: Duration.zero),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Progress').last);
      await t.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsNothing);
      HomeWidgetService.instance.onAction!('today');
      await t.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);
      HomeWidgetService.instance.onAction!('streak');
      await t.pumpAndSettle();
      expect(find.byType(MilestonesScreen), findsOneWidget);
    },
  );

  testWidgets('Main routes and widget gallery have coherent phone previews', (
    t,
  ) async {
    final state = await fresh();
    state.seedDemo();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      state.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await prepare(
      t,
      const Size(390, 844),
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: kayleoTheme(),
        home: AppShell(state: state),
      ),
    );
    await snapshot(t, 'kayleo-home');
    expect(find.text(kayleoGreeting(DateTime.now())), findsOneWidget);
    expect(find.byType(BottomAppBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    final camera = t.widget<FloatingActionButton>(
      find.byKey(const Key('bottom-camera-button')),
    );
    expect(camera.backgroundColor, KayleoColors.lime);
    await t.tap(find.text('Progress').last);
    await t.pumpAndSettle();
    await snapshot(t, 'kayleo-progress');
    await t.tap(find.byKey(const Key('open-milestones')));
    await t.pumpAndSettle();
    expect(find.byType(MilestonesScreen), findsOneWidget);
    await snapshot(t, 'kayleo-milestones');
    await t.ensureVisible(find.text('Water'));
    await t.tap(find.text('Water'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('milestone-water1')), findsOneWidget);
    expect(find.byKey(const Key('milestone-meal1')), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('You').last);
    await t.pumpAndSettle();
    await snapshot(t, 'kayleo-profile');
    await t.ensureVisible(find.text('Home screen widgets'));
    await t.tap(find.text('Home screen widgets'));
    await t.pumpAndSettle();
    expect(find.byType(WidgetGalleryScreen), findsOneWidget);
    await snapshot(t, 'kayleo-widget-gallery');
    await t.drag(find.byType(ListView), const Offset(0, -380));
    await t.pumpAndSettle();
    await snapshot(t, 'kayleo-widget-gallery-streak');
  });

  testWidgets(
    'Wide nutrition widget keeps its large ring and three shortcuts readable',
    (t) async {
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await prepare(
        t,
        const Size(360, 220),
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: kayleoTheme(),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: KayleoWidgetPreview(kind: 'rings')),
            ),
          ),
        ),
      );
      expect(find.text('Kayleo Calories'), findsOneWidget);
      expect(find.text('Scan food'), findsOneWidget);
      expect(find.text('Barcode'), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
      await snapshot(t, 'kayleo-wide-widget');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Streak widget preview renders native flame and streak count',
    (t) async {
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await prepare(
        t,
        const Size(160, 160),
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: kayleoTheme(),
          home: const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: KayleoWidgetPreview(kind: 'streak', streak: 2)),
          ),
        ),
      );
      expect(find.byType(KayleoWidgetPreview), findsOneWidget);
      await snapshot(t, 'kayleo-streak-widget');

      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await t.runAsync(() async {
          final boundary = screenshotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final androidFile = File('android/app/src/main/res/drawable-nodpi/widget_preview_streak.png');
          await androidFile.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Milestone celebration and gallery support large text and reduced motion',
    (t) async {
      final state = await fresh();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        state.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await prepare(
        t,
        const Size(320, 640),
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: kayleoTheme(brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: MilestoneCelebrationScreen(
            state: state,
            earned: [milestones.first],
          ),
        ),
      );
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('View all milestones'));
      await t.tap(find.text('View all milestones'));
      await t.pumpAndSettle();
      expect(find.byType(MilestonesScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
