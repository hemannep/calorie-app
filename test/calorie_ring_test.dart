import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/data/models.dart';
import 'package:calorie_app/features/dashboard.dart';
import 'package:calorie_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  testWidgets('Calorie arcs retain each color and excess has a separate ring', (
    t,
  ) async {
    final key = GlobalKey();
    for (final progress in [.0, .3, .7, .75, 1.0, 1.25]) {
      await t.pumpWidget(
        MaterialApp(
          theme: kayleoTheme(),
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: KayleoRing(
                size: 112,
                stroke: 9,
                progress: progress,
                segmented: true,
                track: KayleoColors.sage,
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await t.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
      final bytes = (await t.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      Color sample(double fraction, double radius) {
        final angle = -math.pi / 2 + math.pi * 2 * fraction;
        final x = (56 + math.cos(angle) * radius).floor();
        final y = (56 + math.sin(angle) * radius).floor();
        final offset = (y * image.width + x) * 4;
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }

      final radius = progress > 1 ? 38.5 : 51.5;
      expect(sample(.15, radius), progress >= .3 ? forest : mint);
      expect(
        sample(.5, radius),
        progress >= .7 ? const Color(0xFF6B9F52) : mint,
      );
      expect(sample(.725, radius), progress >= .75 ? lime : mint);
      if (progress > 1) {
        expect(sample(.1, 51.5), orange);
        expect(sample(.5, 51.5), mint);
      }
      image.dispose();
    }
  });

  testWidgets(
    'Today switches remaining and consumed calories and remembers the choice',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final state = await AppState.load();
      await state.completeOnboarding(state.profile);
      state.preferences['Milestone celebrations'] = false;
      final target = state.profile.calorieTarget;
      await state.saveMeal(
        Meal(
          id: 'ring',
          name: 'Meal',
          time: DateTime.now(),
          category: 'Lunch',
          items: [],
          manual: Nutrients(target * 1.25, 0, 0, 0),
        ),
      );
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
          theme: kayleoTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: state,
                builder: (_, _) =>
                    DashboardScreen(state: state, navigate: (_) {}),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Calories over'), findsOneWidget);
      expect(find.text('Mon'), findsNothing);
      await snapshot(t, 'kayleo-calorie-over');
      await t.tap(find.byKey(const Key('today-calorie-ring')));
      await t.pumpAndSettle();
      expect(find.text('Calories consumed'), findsOneWidget);
      final restored = await AppState.load();
      expect(restored.showConsumedCalories, isTrue);
      restored.dispose();
      await t.tap(find.byKey(const Key('calorie-display-toggle')));
      await t.pumpAndSettle();
      expect(find.text('Calories over'), findsOneWidget);
    },
  );

  testWidgets('Splash uses the original vegetable artwork', (t) async {
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await prepare(
      t,
      const Size(390, 844),
      MaterialApp(
        theme: kayleoTheme(),
        home: const SplashScreen(duration: Duration.zero),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t.widget<Image>(find.byType(Image)).image,
      const AssetImage('assets/images/kayleo-splash.png'),
    );
    await t.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/kayleo-splash.png'),
        t.element(find.byType(SplashScreen)),
      ),
    );
    await snapshot(t, 'kayleo-veggie-splash');
  });
}
