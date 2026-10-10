import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/features/dashboard.dart';
import 'package:calorie_app/services/health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show prepare;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HealthService.instance.mockActivityData = null;
    HealthService.instance.mockIsAuthorized = null;
  });

  tearDown(() {
    HealthService.instance.mockActivityData = null;
    HealthService.instance.mockIsAuthorized = null;
  });

  group('AppState Health Targets & Persistence', () {
    test('Defaults and clamps stepTarget correctly', () async {
      final state = await AppState.load();
      expect(state.stepTarget, 10000);
      expect(state.activeMinutesTarget, 30);
      expect(state.activeCaloriesTarget, 400);
      expect(state.motionKmTarget, 5.0);

      await state.updateStepTarget(8500);
      expect(state.stepTarget, 8500);

      // Clamping test
      await state.updateStepTarget(100);
      expect(state.stepTarget, 500);

      await state.updateStepTarget(200000);
      expect(state.stepTarget, 100000);

      state.dispose();
    });

    test('Persists and restores step and activity targets from storage', () async {
      final state = await AppState.load();
      await state.updateStepTarget(12500);
      await state.updateActivityTargets(
        activeMinutes: 45,
        activeCalories: 550,
        motionKm: 6.5,
      );

      final restored = await AppState.load();
      expect(restored.stepTarget, 12500);
      expect(restored.activeMinutesTarget, 45);
      expect(restored.activeCaloriesTarget, 550);
      expect(restored.motionKmTarget, 6.5);

      state.dispose();
      restored.dispose();
    });
  });

  group('HealthService Activity Data', () {
    test('Returns mock activity data when provided', () async {
      HealthService.instance.mockActivityData = const HealthActivityData(
        steps: 8420,
        activeMinutes: 42,
        activeCalories: 390,
        motionKm: 5.8,
        isAuthorized: true,
      );

      final state = await AppState.load();
      final data = await HealthService.instance.fetchActivityData(
        DateTime.now(),
        state: state,
      );

      expect(data.steps, 8420);
      expect(data.activeMinutes, 42);
      expect(data.activeCalories, 390);
      expect(data.motionKm, 5.8);
      expect(data.isAuthorized, isTrue);

      state.dispose();
    });

    test('Falls back to demo activity data in demo mode', () async {
      final state = await AppState.load();
      state.demo = true;

      final data = await HealthService.instance.fetchActivityData(
        DateTime.now(),
        state: state,
      );

      expect(data.steps, greaterThan(0));
      expect(data.activeMinutes, greaterThan(0));
      expect(data.activeCalories, greaterThan(0));
      expect(data.motionKm, greaterThan(0.0));

      state.dispose();
    });
  });

  group('Dashboard Rings Carousel & Interaction', () {
    testWidgets('Swiping or tapping pill reveals Step ring and 3 down rings', (
      tester,
    ) async {
      HealthService.instance.mockActivityData = const HealthActivityData(
        steps: 7200,
        activeMinutes: 35,
        activeCalories: 360,
        motionKm: 4.8,
        isAuthorized: true,
      );

      final state = await AppState.load();
      await state.completeOnboarding(state.profile);
      addTearDown(() {
        state.dispose();
      });

      await prepare(
        tester,
        const Size(390, 844),
        MaterialApp(
          theme: kayleoTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardScreen(state: state, navigate: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial slide is Nutrition (Calorie ring visible)
      expect(find.byKey(const Key('today-calorie-ring')), findsOneWidget);
      expect(find.byKey(const Key('rings-pill-nutrition')), findsOneWidget);
      expect(find.byKey(const Key('rings-pill-activity')), findsOneWidget);

      // 2. Switch to Activity slide via pill tap
      await tester.tap(find.byKey(const Key('rings-pill-activity')));
      await tester.pumpAndSettle();

      // Main Step ring is visible
      expect(find.byKey(const Key('today-step-ring')), findsOneWidget);
      expect(find.text('7,200'), findsOneWidget);
      expect(find.textContaining('7,200 / 10,000 steps'), findsOneWidget);

      // 3 down rings are visible: Active Time, Activity Calorie, Motion
      expect(find.byKey(const Key('today-active-time-ring')), findsOneWidget);
      expect(find.text('35m'), findsOneWidget);
      expect(find.text('Active time'), findsOneWidget);

      expect(find.byKey(const Key('today-activity-calorie-ring')), findsOneWidget);
      expect(find.text('360'), findsOneWidget);
      expect(find.text('Activity cal'), findsOneWidget);

      expect(find.byKey(const Key('today-motion-ring')), findsOneWidget);
      expect(find.text('4.8km'), findsOneWidget);
      expect(find.text('Motion'), findsOneWidget);

      // 3. Click the step ring / card to open the Goal dialog
      await tester.tap(find.byKey(const Key('step-goal-trigger')));
      await tester.pumpAndSettle();

      expect(find.text('Daily Step Goal'), findsOneWidget);
      expect(find.byKey(const Key('step-goal-input')), findsOneWidget);

      // 4. Update the goal using a preset chip or typing
      await tester.enterText(find.byKey(const Key('step-goal-input')), '12000');
      await tester.tap(find.byKey(const Key('save-step-goal-button')));
      await tester.pumpAndSettle();

      // Dialog is dismissed
      expect(find.text('Daily Step Goal'), findsNothing);

      // AppState stepTarget was updated and persisted
      expect(state.stepTarget, 12000);

      // Ring subtitle reflects the new target!
      expect(find.textContaining('7,200 / 12,000 steps'), findsOneWidget);

      // 5. Switch back to Nutrition slide via pill tap
      await tester.tap(find.byKey(const Key('rings-pill-nutrition')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('today-calorie-ring')), findsOneWidget);
    });

    testWidgets('Horizontal drag gestures scroll between Nutrition and Activity', (
      tester,
    ) async {
      HealthService.instance.mockActivityData = const HealthActivityData(
        steps: 9000,
        activeMinutes: 40,
        activeCalories: 450,
        motionKm: 6.0,
        isAuthorized: true,
      );

      final state = await AppState.load();
      await state.completeOnboarding(state.profile);
      addTearDown(() {
        state.dispose();
      });

      await prepare(
        tester,
        const Size(390, 844),
        MaterialApp(
          theme: kayleoTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardScreen(state: state, navigate: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially on Nutrition
      expect(find.byKey(const Key('today-calorie-ring')), findsOneWidget);

      // Drag left to page 1
      await tester.drag(
        find.byKey(const Key('today-rings-pageview')),
        const Offset(-350, 0),
      );
      await tester.pumpAndSettle();

      // Now on Activity
      expect(find.byKey(const Key('today-step-ring')), findsOneWidget);
      expect(find.text('9,000'), findsOneWidget);

      // Drag right back to page 0
      await tester.drag(
        find.byKey(const Key('today-rings-pageview')),
        const Offset(350, 0),
      );
      await tester.pumpAndSettle();

      // Back on Nutrition
      expect(find.byKey(const Key('today-calorie-ring')), findsOneWidget);
    });

    testWidgets('Displays prominent Not connected badge and Connect Health button when unauthorized', (
      tester,
    ) async {
      HealthService.instance.mockActivityData = const HealthActivityData(
        steps: 0,
        activeMinutes: 0,
        activeCalories: 0,
        motionKm: 0.0,
        isAuthorized: false,
      );
      HealthService.instance.mockIsAuthorized = true; // requestPermissions will return true

      final state = await AppState.load();
      await state.completeOnboarding(state.profile);
      addTearDown(() {
        state.dispose();
      });

      await prepare(
        tester,
        const Size(390, 844),
        MaterialApp(
          theme: kayleoTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardScreen(state: state, navigate: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Activity slide
      await tester.tap(find.byKey(const Key('rings-pill-activity')));
      await tester.pumpAndSettle();

      // Verify "Not connected" badge and Connect button are prominently displayed
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.byKey(const Key('connect-health-button')), findsOneWidget);
      expect(
        find.textContaining('Connect ${HealthService.instance.platformHealthAppName}'),
        findsOneWidget,
      );

      // Tap Connect button
      await tester.tap(find.byKey(const Key('connect-health-button')));
      await tester.pumpAndSettle();

      // SnackBar shows connected feedback
      expect(find.textContaining('Connected to'), findsOneWidget);
    });

    testWidgets('Step goal dialog renders without overflow in constrained height', (
      tester,
    ) async {
      final state = await AppState.load();
      addTearDown(() {
        state.dispose();
      });

      // Render in tight height simulating keyboard covering bottom of screen
      await prepare(
        tester,
        const Size(360, 400),
        MaterialApp(
          theme: kayleoTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showStepGoalDialog(ctx, state),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Dialog is open and no overflow error was thrown
      expect(find.text('Daily Step Goal'), findsOneWidget);
      expect(find.byKey(const Key('step-goal-input')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

