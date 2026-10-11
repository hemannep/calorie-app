import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/features/dashboard.dart';
import 'package:calorie_app/services/health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show prepare, snapshot;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  tearDown(() {
    HealthService.instance.mockActivityData = null;
    HealthService.instance.mockIsAuthorized = null;
  });

  for (final source in ['reported', 'estimated', 'mixed']) {
    for (final layout in [
      (width: 360.0, scale: 1.0),
      (width: 390.0, scale: 1.0),
      (width: 360.0, scale: 1.3),
      (width: 390.0, scale: 2.0),
    ]) {
      testWidgets('Nutrition and $source activity cards match at '
          '${layout.width}px / ${layout.scale}x text', (tester) async {
        SharedPreferences.setMockInitialValues({});
        HealthService.instance.mockActivityData = HealthActivityData(
          steps: 8420,
          activeMinutes: 125,
          activeCalories: 390,
          motionKm: 5.8,
          isAuthorized: true,
          rawActiveMinutes: source != 'estimated',
          rawActiveCalories: source == 'reported',
          rawDistance: source == 'reported',
        );
        final state = await AppState.load();
        await state.completeOnboarding(state.profile);
        addTearDown(() {
          state.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await prepare(
          tester,
          Size(layout.width, 980),
          MaterialApp(
            theme: kayleoTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(layout.scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DashboardScreen(state: state, navigate: (_) {}),
              ),
            ),
          ),
        );

        final nutritionSizes = [
          for (final metric in ['protein', 'carbs', 'fats'])
            tester.getSize(find.byKey(Key('today-$metric-card'))),
        ];
        for (final size in nutritionSizes) {
          expect(size, nutritionSizes.first);
        }
        final preview =
            source == 'reported' && layout.width == 390 && layout.scale == 1;
        if (preview) await snapshot(tester, 'dashboard-nutrition-matched');

        final activityPill = find.byKey(const Key('rings-pill-activity'));
          if (activityPill.hitTestable().evaluate().isEmpty) {
            await tester.ensureVisible(activityPill);
          }
        await tester.tap(activityPill);
        await tester.pumpAndSettle();
        for (final metric in ['active-time', 'activity-calorie', 'motion']) {
          final card = find.byKey(Key('today-$metric-ring-card'));
          expect(tester.getSize(card), nutritionSizes.first);
        }
        final visibleEstimates = tester
            .widgetList<Visibility>(
              find.ancestor(
                of: find.text('from steps'),
                matching: find.byType(Visibility),
              ),
            )
            .where((hint) => hint.visible)
            .length;
        expect(
          visibleEstimates,
          source == 'reported' ? 0 : (source == 'estimated' ? 3 : 2),
        );
        expect(tester.takeException(), isNull);
        if (preview) await snapshot(tester, 'dashboard-activity-matched');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
